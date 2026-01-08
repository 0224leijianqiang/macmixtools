import Foundation
import Combine
import Citadel
import NIOSSH
import NIO
import AppKit

class SSHRunner: ObservableObject, Cleanable {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var currentPath: String = ""
    @Published var error: String? = nil
    
    // SFTP Client exposed for the SFTP view
    @Published var sftp: SFTPClient?
    
    // AI Context Buffer
    private var outputBuffer: [String] = []
    private let maxBufferSize = 50
    
    weak var terminalOutput: TerminalOutputSink?
    
    private var client: SSHClient?
    private var ttyWriter: TTYStdinWriter?
    private var activeConnection: SSHConnection? // Store the connection object
    private var connectionID: UUID?
    private var terminalTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var remoteShellPath: String?
    private var cwdHookInstalled = false
    private var needsInitialPromptCleanup = false
    private var pendingRestorePath: String?
    private var pathPersistenceCancellable: AnyCancellable?
    private var pathPersistenceKey: String?
    private var acquiredHost: String?
    private var acquiredPort: Int?
    private var acquiredUsername: String?
    private var didAcquireClient = false

    private static func persistenceKey(for connection: SSHConnection) -> String {
        "sshtools.lastCwd.\(connection.id.uuidString)"
    }

    private static func shellSingleQuoted(_ path: String) -> String {
        // POSIX-safe single-quote: ' -> '\'' (close, escape, reopen)
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    func connect(connection: SSHConnection) {
        guard !isConnecting else { return }
        if isConnected || client != nil {
            disconnect()
        }
        isConnecting = true
        self.activeConnection = connection
        self.connectionID = connection.id
        self.error = nil
        self.pendingRestorePath = nil
        self.pathPersistenceKey = Self.persistenceKey(for: connection)
        self.acquiredHost = connection.host
        self.acquiredPort = Int(connection.port) ?? 22
        self.acquiredUsername = connection.effectiveUsername
        self.didAcquireClient = false
        if let key = self.pathPersistenceKey,
           let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty
        {
            self.pendingRestorePath = stored
            if self.currentPath.isEmpty {
                self.currentPath = stored
            }
        }
        
        Task { @MainActor in
            do {
                let client = try await SSHConnectionManager.shared.getClient(for: connection)
                self.client = client
                self.didAcquireClient = true

                // Best-effort: detect remote login shell to decide whether we can install OSC 7 cwd tracking.
                if let buffer = try? await client.executeCommand("echo $SHELL") {
                    var b = buffer
                    let data = b.readData(length: b.readableBytes) ?? Data()
                    self.remoteShellPath = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    self.remoteShellPath = nil
                }
                
                // 1. Open SFTP
                self.sftp = try await client.openSFTP()
                
                // Consider connected once SFTP is open
                self.isConnected = true
                
                // Best-effort: set initial path from remote `pwd` (more accurate than guessing /home/...).
                if self.currentPath.isEmpty {
                    if let buffer = try? await client.executeCommand("pwd") {
                        let pwd = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                        self.currentPath = pwd.isEmpty ? "/" : pwd
                    } else {
                        self.currentPath = "/"
                    }
                }
                
                self.installPathPersistenceIfNeeded()
                
                // Start Keep-Alive
                startKeepAlive()
                
                // 2. Start Terminal Session
                self.terminalTask = Task {
                    defer { Task { @MainActor [weak self] in self?.disconnect() } }
                    do { try await startTerminal(client: client) }
                    catch {
                        await MainActor.run {
                            self.error = error.localizedDescription
                            self.isConnected = false
                            Logger.log("SSH: Terminal session ended with error: \(error)", level: .error)
                        }
                    }
                }
                
                Logger.log("SSH: Connected successfully via Citadel", level: .info)
            } catch {
                self.error = error.localizedDescription
                self.isConnected = false
                Logger.log("SSH: Connection failed: \(error)", level: .error)
                self.disconnect()
            }
            self.isConnecting = false
        }
    }
    
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
                    guard let client = self?.client else { break }
                    // Execute a no-op command to keep the connection alive
                    _ = try await client.executeCommand("true")
                    Logger.log("SSH: Keep-alive sent", level: .debug)
                } catch {
                    Logger.log("SSH: Keep-alive failed: \(error)", level: .debug)
                    if let runner = self {
                        await MainActor.run { runner.disconnect() }
                    }
                    break
                }
            }
        }
    }
    
    private func startTerminal(client: SSHClient) async throws {
        // Environment variables
        let env: [String: String] = [
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TERM": "xterm-256color"
        ]
        
        let envRequests = env.map { SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: $0.key, value: $0.value) }
        
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        
        try await client.withPTY(request, environment: envRequests) { inbound, outbound in
            await MainActor.run {
                self.ttyWriter = outbound
                self.isConnected = true
            }

            self.installCwdTrackingHookIfNeeded()
            
            for try await event in inbound {
                switch event {
                case .stdout(let buffer), .stderr(let buffer):
                    let data = Data(buffer.readableBytesView)
                    
                    // Add to AI context buffer
                    if let text = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            self.outputBuffer.append(text)
                            if self.outputBuffer.count > self.maxBufferSize {
                                self.outputBuffer.removeFirst()
                            }
                        }
                    }
                    
                    await MainActor.run {
                        self.terminalOutput?.writeToTerminal(data)
                    }
                }
            }
        }
        
        await MainActor.run {
            self.isConnected = false
            self.ttyWriter = nil
        }
    }

    private func installCwdTrackingHookIfNeeded() {
        guard !cwdHookInstalled else { return }
        guard ttyWriter != nil else { return }
        guard let shell = remoteShellPath?.lowercased(), !shell.isEmpty else { return }

        // Avoid breaking non-POSIX shells.
        let isBash = shell.contains("bash")
        let isZsh = shell.contains("zsh")
        let supportsPOSIXHook = isBash || isZsh || shell.hasSuffix("/sh") || shell.contains("/sh")
        guard supportsPOSIXHook else { return }

        let hook: String
        if isZsh {
            hook = "__SSHTOOLS_OSC7(){ printf '\\033]7;file://%s%s\\007' \"${HOSTNAME:-${HOST:-localhost}}\" \"$PWD\"; }; autoload -Uz add-zsh-hook 2>/dev/null || true; add-zsh-hook precmd __SSHTOOLS_OSC7 2>/dev/null || precmd_functions+=(__SSHTOOLS_OSC7); __SSHTOOLS_OSC7"
        } else {
            // Default to bash/sh.
            hook = "__SSHTOOLS_OSC7(){ printf '\\033]7;file://%s%s\\007' \"${HOSTNAME:-${HOST:-localhost}}\" \"$PWD\"; }; PROMPT_COMMAND=\"__SSHTOOLS_OSC7;${PROMPT_COMMAND:-}\"; __SSHTOOLS_OSC7"
        }

        cwdHookInstalled = true
        // Don't clear the user's login banner (MOTD/Last login). Instead, try to hide hook injection by disabling echo.
        needsInitialPromptCleanup = false

        // Best-effort: install OSC 7 cwd reporting so the UI can sync SFTP with `cd`.
        // Any visible injection noise is minimized via `stty -echo`.
        Task { [weak self] in
            guard let self else { return }
            // await self.sendRawOrdered(hook + "\r")
        }
    }

    private func sendRawOrdered(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        let buffer = ByteBuffer(data: data)
        try? await ttyWriter?.write(buffer)
    }

    private func installPathPersistenceIfNeeded() {
        guard pathPersistenceCancellable == nil else { return }
        pathPersistenceCancellable = $currentPath
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] newPath in
                guard let self else { return }
                guard let key = self.pathPersistenceKey, !key.isEmpty else { return }
                guard !newPath.isEmpty else { return }
                UserDefaults.standard.set(newPath, forKey: key)
            }
    }

    @MainActor
    func notifyTerminalReady() {
        if needsInitialPromptCleanup {
            // Clear screen + scrollback locally so users don't see hook injection prompts/echo.
            terminalOutput?.writeToTerminal(Data("\u{1B}[3J\u{1B}[2J\u{1B}[H".utf8))
            needsInitialPromptCleanup = false
        }
        Task { [weak self] in
            // Ask the remote shell to redraw a fresh prompt (empty command).
            guard let self else { return }
            await self.sendRawOrdered("\r")
            if let restore = self.pendingRestorePath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !restore.isEmpty
            {
                self.pendingRestorePath = nil
                let quoted = Self.shellSingleQuoted(restore)
                await self.sendRawOrdered("cd -- \(quoted)\r")
            }
        }
    }
    
    func send(data: Data) {
        let buffer = ByteBuffer(data: data)
        Task {
            try? await ttyWriter?.write(buffer)
        }
    }
    
    func sendRaw(_ text: String) {
        if let data = text.data(using: .utf8) {
            send(data: data)
        }
    }
    
    func resize(cols: Int, rows: Int) {
        Task {
            try? await ttyWriter?.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }
    
    func getLastOutput() -> String {
        return outputBuffer.joined()
    }
    
    func disconnect() {
        terminalTask?.cancel()
        terminalTask = nil
        
        keepAliveTask?.cancel()
        keepAliveTask = nil
        
        // Notify Manager to release reference using the exact key acquired at connect-time.
        if didAcquireClient,
           let host = acquiredHost,
           let port = acquiredPort,
           let username = acquiredUsername
        {
            Task {
                await SSHConnectionManager.shared.releaseClient(host: host, port: port, username: username)
            }
        }
        
        // Release references
        client = nil
        sftp = nil
        ttyWriter = nil
        activeConnection = nil
        pathPersistenceCancellable?.cancel()
        pathPersistenceCancellable = nil
        pathPersistenceKey = nil
        pendingRestorePath = nil
        acquiredHost = nil
        acquiredPort = nil
        acquiredUsername = nil
        didAcquireClient = false
        
        isConnected = false
    }
    
    func cleanup() {
        disconnect()
    }
    
    func executeCommand(_ command: String) async throws -> String {
        guard let client = client else {
            throw NSError(domain: "SSHRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let outputBuffer = try await client.executeCommand(command)
        return String(buffer: outputBuffer)
    }
    
    func detectSystemInfo() async -> String {
        guard let client = client else { return "Unknown Linux" }
        do {
            let outputBuffer = try await client.executeCommand("cat /etc/os-release")
            let output = String(buffer: outputBuffer)
            
            var result = "Linux"
            output.enumerateLines {
                line, _ in
                if line.starts(with: "PRETTY_NAME=") {
                    result = line.replacingOccurrences(of: "PRETTY_NAME=", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
            
            if result == "Linux" {
                 let unameBuffer = try await client.executeCommand("uname -sr")
                 let uname = String(buffer: unameBuffer)
                 if !uname.isEmpty { result = uname.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            
            return result
        } catch {
            return "Unknown Linux"
        }
    }
}
