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
    private(set) var connectionID: UUID?
    private var terminalTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let reconnectMaxDelay: TimeInterval = 30
    private var remoteShellPath: String?
    private var cwdHookInstalled = false
    private var needsInitialPromptCleanup = false
    private var pendingRestorePath: String?
    private var restoreTargetPath: String?
    private(set) var isRestoringPath = false
    private var pathPersistenceCancellable: AnyCancellable?
    private var pathPersistenceKeys: [String] = []
    /// Toggle: disable OSC7 hook to keep shell history and prompt clean (FinalShell-like).
    private static let enableOSC7Hook = false
    private var acquiredHost: String?
    private var acquiredPort: Int?
    private var acquiredUsername: String?
    private var didAcquireClient = false
    private var lastActivity = Date()
    private let keepAliveInterval: TimeInterval = 30
    private let keepAliveIdleThreshold: TimeInterval = 45
    private let autoReconnectEnabled = true
    private var isDisconnecting = false
    private var inputLineBuffer: String = ""
    private var inputHadTab: Bool = false
    private var lastCdCommand: String = ""
    private var lastCdAt: Date = .distantPast

    private static func persistenceKey(for connection: SSHConnection) -> String {
        "sshtools.lastCwd.\(connection.id.uuidString)"
    }

    private static func stablePersistenceKey(for connection: SSHConnection) -> String {
        let raw = "\(connection.effectiveUsername)@\(connection.host):\(connection.port)"
        let safe = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? raw
        return "sshtools.lastCwd.stable.\(safe)"
    }

    private static func persistenceKeys(for connection: SSHConnection) -> [String] {
        let primary = persistenceKey(for: connection)
        let stable = stablePersistenceKey(for: connection)
        if primary == stable {
            return [primary]
        }
        return [primary, stable]
    }

    private static func shellSingleQuoted(_ path: String) -> String {
        // POSIX-safe single-quote: ' -> '\'' (close, escape, reopen)
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func loadPersistedPath(from keys: [String]) -> String? {
        for key in keys {
            if let stored = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !stored.isEmpty
            {
                return stored
            }
        }
        return nil
    }
    
    func connect(connection: SSHConnection) {
        guard !isConnecting else { return }
        if isConnected || client != nil {
            disconnect(reason: .user)
        }
        reconnectTask?.cancel()
        reconnectAttempts = 0
        isConnecting = true
        self.activeConnection = connection
        self.connectionID = connection.id
        self.error = nil
        self.pendingRestorePath = nil
        self.pathPersistenceKeys = Self.persistenceKeys(for: connection)
        self.acquiredHost = connection.host
        self.acquiredPort = Int(connection.port) ?? 22
        self.acquiredUsername = connection.effectiveUsername
        self.didAcquireClient = false
        self.lastActivity = Date()
        if let stored = Self.loadPersistedPath(from: self.pathPersistenceKeys) {
            self.pendingRestorePath = stored
            self.restoreTargetPath = stored
            self.isRestoringPath = true
            if self.currentPath != stored {
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
                self.reconnectAttempts = 0
                
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
                    defer { Task { @MainActor [weak self] in self?.disconnect(reason: .error) } }
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
                self.disconnect(reason: .error)
            }
            self.isConnecting = false
        }
    }
    
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let self else { break }
                    try await Task.sleep(nanoseconds: UInt64(self.keepAliveInterval * 1_000_000_000))
                    guard let client = self.client, client.isConnected else { break }
                    let lastActivity = await MainActor.run { self.lastActivity }
                    let idleTime = Date().timeIntervalSince(lastActivity)
                    if idleTime < self.keepAliveIdleThreshold {
                        continue
                    }
                    // Execute a no-op command to keep the connection alive
                    _ = try await client.executeCommand("true")
                    await MainActor.run { self.lastActivity = Date() }
                    Logger.log("SSH: Keep-alive sent", level: .debug)
                } catch {
                    Logger.log("SSH: Keep-alive failed: \(error)", level: .debug)
                    if let runner = self {
                        await MainActor.run { runner.disconnect(reason: .error) }
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
            Task { [weak self] in
                await self?.restoreShellPathIfNeeded()
            }
            
            for try await event in inbound {
                switch event {
                case .stdout(let buffer), .stderr(let buffer):
                    let data = Data(buffer.readableBytesView)
                    
                    let text = String(data: data, encoding: .utf8)

                    await MainActor.run {
                        self.lastActivity = Date()
                        // Add to AI context buffer
                        if let text {
                            self.outputBuffer.append(text)
                            if self.outputBuffer.count > self.maxBufferSize {
                                self.outputBuffer.removeFirst()
                            }
                        }
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
        guard Self.enableOSC7Hook else { return }
        guard !cwdHookInstalled else { return }
        guard ttyWriter != nil else { return }
        guard let shell = remoteShellPath?.lowercased(), !shell.isEmpty else { return }

        // Avoid breaking non-POSIX shells.
        let isBash = shell.contains("bash")
        let isZsh = shell.contains("zsh")
        let supportsPOSIXHook = isBash || isZsh || shell.hasSuffix("/sh") || shell.contains("/sh")
        if !supportsPOSIXHook { return }

        let hook: String
        if isZsh {
            hook =
            """
             setopt HIST_IGNORE_SPACE 2>/dev/null
             __SSHTOOLS_OSC7(){ printf '\\033]7;file://%s%s\\007' "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
             autoload -Uz add-zsh-hook 2>/dev/null || true
             add-zsh-hook precmd __SSHTOOLS_OSC7 2>/dev/null || precmd_functions+=(__SSHTOOLS_OSC7)
             __SSHTOOLS_OSC7
             """
            .replacingOccurrences(of: "\n", with: " ")
        } else {
            // Default to bash/sh.
            hook =
            """
             HISTCONTROL=${HISTCONTROL:-ignoreboth}; export HISTCONTROL;
             __SSHTOOLS_OSC7(){ printf '\\033]7;file://%s%s\\007' "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
             PROMPT_COMMAND="__SSHTOOLS_OSC7;${PROMPT_COMMAND:-}";
             __SSHTOOLS_OSC7;
             builtin history -d $(history 1 2>/dev/null | awk '{print $1}') 2>/dev/null || true
             """
            .replacingOccurrences(of: "\n", with: " ")
        }

        cwdHookInstalled = true
        needsInitialPromptCleanup = false

        // Prefix a space so HIST_IGNORE_SPACE/ignoreboth can drop this line from history.
        sendRaw(" " + hook + "\r")
    }

    private func sendRawOrdered(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        let buffer = ByteBuffer(data: data)
        await MainActor.run {
            self.lastActivity = Date()
        }
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
                guard !self.pathPersistenceKeys.isEmpty else { return }
                guard !newPath.isEmpty else { return }
                if self.isRestoringPath {
                    return
                }
                self.pathPersistenceKeys.forEach { UserDefaults.standard.set(newPath, forKey: $0) }
            }
    }

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
            await self.restoreShellPathIfNeeded()
        }
    }

    private func restoreShellPathIfNeeded() async {
        guard let restore = pendingRestorePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !restore.isEmpty
        else { return }
        await MainActor.run {
            self.isRestoringPath = true
            self.restoreTargetPath = restore
        }
        let quoted = Self.shellSingleQuoted(restore)
        await self.sendRawOrdered("cd -- \(quoted)\r")
    }
    
    func send(data: Data) {
        let buffer = ByteBuffer(data: data)
        Task {
            await MainActor.run {
                self.lastActivity = Date()
                self.trackInputForCwd(data)
            }
            try? await ttyWriter?.write(buffer)
        }
    }

    private func trackInputForCwd(_ data: Data) {
        guard let fragment = String(data: data, encoding: .utf8) else { return }
        for ch in fragment {
            if ch == "\r" || ch == "\n" {
                let line = inputLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                inputLineBuffer = ""
                let hadTab = inputHadTab
                inputHadTab = false
                if !line.isEmpty && !hadTab {
                    maybeHandleCdInput(line)
                }
                continue
            }
            if ch == "\u{7f}" || ch == "\u{8}" { // delete/backspace
                if !inputLineBuffer.isEmpty {
                    inputLineBuffer.removeLast()
                }
                continue
            }
            if ch == "\t" {
                inputHadTab = true
                continue
            }
            if ch.isASCII {
                let v = ch.unicodeScalars.first?.value ?? 0
                if v < 32 || v == 127 {
                    continue
                }
            }
            inputLineBuffer.append(ch)
        }
    }

    private func maybeHandleCdInput(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("cd") else { return }
        let rawArg = trimmed.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawArg.isEmpty else { return }

        let pathPart = normalizeCdArgument(String(rawArg))
        guard !pathPart.isEmpty else { return }

        let resolved = resolvePath(pathPart, current: currentPath.isEmpty ? "/" : currentPath)
        lastCdCommand = pathPart.isEmpty ? "cd" : "cd \(pathPart)"
        lastCdAt = Date()
        Task { @MainActor in
            self.currentPath = resolved
            self.finishRestoringPathIfNeeded()
            NotificationCenter.default.post(name: .sshtoolsCurrentPathChanged, object: resolved)
        }
    }

    func shouldSkipOutputCd(_ command: String) -> Bool {
        guard !lastCdCommand.isEmpty else { return false }
        let delta = Date().timeIntervalSince(lastCdAt)
        return delta < 0.8 && command == lastCdCommand
    }

    private func resolvePath(_ raw: String, current: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return NSString(string: trimmed).standardizingPath
        }
        let base = current.isEmpty ? "/" : current
        let combined = (base as NSString).appendingPathComponent(trimmed)
        return NSString(string: combined).standardizingPath
    }

    private func normalizeCdArgument(_ raw: String) -> String {
        var arg = raw
        if arg.hasPrefix("--") {
            arg = arg.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (arg.hasPrefix("'") && arg.hasSuffix("'")) || (arg.hasPrefix("\"") && arg.hasSuffix("\"")) {
            arg = String(arg.dropFirst().dropLast())
        }
        return arg.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    func changeDirectory(to newPath: String) {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let quoted = Self.shellSingleQuoted(trimmed)
        Task { [weak self] in
            guard let self else { return }
            await self.sendRawOrdered("cd -- \(quoted)\r")
        }
        currentPath = trimmed
        finishRestoringPathIfNeeded()
    }

    @MainActor
    func updateCurrentPathFromOSC7(_ newPath: String) {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isRestoringPath, let target = restoreTargetPath, target != trimmed {
            return
        }
        currentPath = trimmed
        if isRestoringPath, let target = restoreTargetPath, target == trimmed {
            finishRestoringPathIfNeeded()
        }
    }

    @MainActor
    func finishRestoringPathIfNeeded() {
        isRestoringPath = false
        pendingRestorePath = nil
        restoreTargetPath = nil
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
    
    enum DisconnectReason {
        case user
        case error
    }

    func disconnect(reason: DisconnectReason = .user) {
        if isDisconnecting { return }
        isDisconnecting = true
        defer { isDisconnecting = false }

        terminalTask?.cancel()
        terminalTask = nil
        
        keepAliveTask?.cancel()
        keepAliveTask = nil

        if reason == .user {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempts = 0
        }
        
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
        
        // Persist last known path before clearing keys.
        if !pathPersistenceKeys.isEmpty {
            let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pathPersistenceKeys.forEach { UserDefaults.standard.set(trimmed, forKey: $0) }
            }
        }

        let reconnectTarget = (reason == .error) ? activeConnection : nil

        // Release references
        client = nil
        sftp = nil
        ttyWriter = nil
        activeConnection = nil
        pathPersistenceCancellable?.cancel()
        pathPersistenceCancellable = nil
        pathPersistenceKeys.removeAll()
        pendingRestorePath = nil
        restoreTargetPath = nil
        isRestoringPath = false
        acquiredHost = nil
        acquiredPort = nil
        acquiredUsername = nil
        didAcquireClient = false
        
        isConnected = false

        if autoReconnectEnabled, let target = reconnectTarget {
            scheduleReconnect(for: target)
        }
    }

    private func scheduleReconnect(for connection: SSHConnection) {
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), reconnectMaxDelay)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await MainActor.run {
                self.error = "Reconnecting…"
            }
            self.connect(connection: connection)
        }
    }
    
    func cleanup() {
        disconnect(reason: .user)
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

extension SSHRunner: TerminalRunner {}
