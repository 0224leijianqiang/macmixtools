import Foundation
import Darwin

final class LocalTerminalRunner: ObservableObject, TerminalRunner, Cleanable {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var currentPath: String {
        didSet {
            persistCurrentPathIfNeeded()
        }
    }
    @Published var error: String?
    private(set) var connectionID: UUID?

    weak var terminalOutput: TerminalOutputSink?

    private var process: Process?
    private var masterHandle: FileHandle?
    private var slaveHandle: FileHandle?

    private var outputBuffer: [String] = []
    private let maxBufferSize = 50
    private var hookInstalled = false
    private var shellPath: String?
    private var persistenceKey: String?
    private var pendingRestorePath: String?
    private var lastPersistedPath: String?
    private var isShuttingDown = false
    /// Toggle: disable OSC7 hook to keep shell history/prompt clean.
    private static let enableOSC7Hook = false

    init(connectionID: UUID) {
        self.connectionID = connectionID
        let key = "sshtools.local.lastCwd.\(connectionID.uuidString)"
        self.persistenceKey = key
        let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = stored?.isEmpty == false ? stored! : FileManager.default.currentDirectoryPath
        self.currentPath = initial
        self.pendingRestorePath = stored?.isEmpty == false ? stored : nil
        self.lastPersistedPath = stored
    }

    func connect() {
        guard !isConnecting else { return }
        if isConnected {
            disconnect()
        }

        isConnecting = true
        isShuttingDown = false
        error = nil
        hookInstalled = false

        var master: Int32 = 0
        var slave: Int32 = 0
        if openpty(&master, &slave, nil, nil, nil) != 0 {
            error = "Failed to open local PTY"
            isConnecting = false
            return
        }

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        self.masterHandle = masterHandle
        self.slaveHandle = slaveHandle

        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = shell
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l"]

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        process.environment = env

        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isShuttingDown { return }
                self.disconnect()
            }
        }

        do {
            try process.run()
        } catch {
            self.error = error.localizedDescription
            masterHandle.closeFile()
            slaveHandle.closeFile()
            self.masterHandle = nil
            self.slaveHandle = nil
            self.isConnecting = false
            return
        }

        self.process = process
        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                DispatchQueue.main.async {
                    guard let self, !self.isShuttingDown else { return }
                    self.disconnect()
                }
                return
            }

            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.outputBuffer.append(text)
                    if self.outputBuffer.count > self.maxBufferSize {
                        self.outputBuffer.removeFirst()
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.terminalOutput?.writeToTerminal(data)
            }
        }

        isConnected = true
        isConnecting = false
    }

    func disconnect() {
        if isShuttingDown { return }
        isShuttingDown = true
        defer { isShuttingDown = false }

        masterHandle?.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        masterHandle?.closeFile()
        slaveHandle?.closeFile()
        masterHandle = nil
        slaveHandle = nil

        isConnected = false
        isConnecting = false
    }

    func cleanup() {
        disconnect()
    }

    func send(data: Data) {
        masterHandle?.write(data)
    }

    func sendRaw(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data: data)
    }

    func resize(cols: Int, rows: Int) {
        guard let masterHandle else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        ioctl(masterHandle.fileDescriptor, TIOCSWINSZ, &size)
    }

    func notifyTerminalReady() {
        installCwdTrackingHookIfNeeded()
        // 不发送 \r，避免执行空行产生多余空白行
        if let restore = pendingRestorePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !restore.isEmpty
        {
            pendingRestorePath = nil
            let quoted = shellSingleQuoted(restore)
            sendRaw("cd -- \(quoted)\r")
        }
    }

    func getLastOutput() -> String {
        outputBuffer.joined()
    }

    private func installCwdTrackingHookIfNeeded() {
        guard Self.enableOSC7Hook else { return }
        guard !hookInstalled else { return }
        guard let shellPath = shellPath?.lowercased(), !shellPath.isEmpty else { return }

        let isBash = shellPath.contains("bash")
        let isZsh = shellPath.contains("zsh")
        let isFish = shellPath.contains("fish")
        let supportsPOSIXHook = isBash || isZsh || isFish || shellPath.hasSuffix("/sh") || shellPath.contains("/sh")
        if !supportsPOSIXHook {
            // Fallback: best-effort single OSC7 emit.
            sendRaw("printf '\\033]7;file://%s%s\\007' \"${HOSTNAME:-${HOST:-localhost}}\" \"$PWD\"\r")
            return
        }

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
        } else if isFish {
            hook =
            """
             function __SSHTOOLS_OSC7 --on-event fish_prompt; printf '\\033]7;file://%s%s\\007' (hostname) $PWD; end; __SSHTOOLS_OSC7
             """
            .replacingOccurrences(of: "\n", with: " ")
        } else {
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

        hookInstalled = true
        // Prefix space so HIST_IGNORE_SPACE/ignoreboth drops this line from history.
        sendRaw(" " + hook + "\r")
        // Best-effort immediate OSC7 to seed current path
        sendRaw("printf '\\033]7;file://%s%s\\007' \"${HOSTNAME:-${HOST:-localhost}}\" \"$PWD\"\r")
    }

    private func persistCurrentPathIfNeeded() {
        guard let key = persistenceKey, !key.isEmpty else { return }
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == lastPersistedPath { return }
        lastPersistedPath = trimmed
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    private func shellSingleQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
