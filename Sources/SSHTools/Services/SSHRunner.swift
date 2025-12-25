import Foundation
import Combine
import Citadel
import NIOSSH
import NIO
import SwiftTerm
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
    
    // Reference to the SwiftTerm view to feed data into
    weak var terminalView: SwiftTerm.TerminalView?
    
    private var client: SSHClient?
    private var ttyWriter: TTYStdinWriter?
    private var activeConnection: SSHConnection? // Store the connection object
    private var connectionID: UUID?
    private var terminalTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    
    func connect(connection: SSHConnection) {
        guard !isConnecting else { return }
        isConnecting = true
        self.activeConnection = connection
        self.connectionID = connection.id
        self.error = nil
        
        Task { @MainActor in
            do {
                let client = try await SSHConnectionManager.shared.getClient(for: connection)
                self.client = client
                
                // 1. Open SFTP
                self.sftp = try await client.openSFTP()
                
                // Consider connected once SFTP is open
                self.isConnected = true
                
                // Set initial path if empty
                if self.currentPath.isEmpty {
                    if connection.username == "root" {
                        self.currentPath = "/root"
                    } else {
                        self.currentPath = "/home/\(connection.username)"
                    }
                }
                
                // Start Keep-Alive
                startKeepAlive()
                
                // 2. Start Terminal Session
                self.terminalTask = Task {
                    do {
                        try await startTerminal(client: client)
                    } catch {
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
                // If getClient failed, ensure we notify release if reference was counted
                if let conn = self.activeConnection {
                    Task { await SSHConnectionManager.shared.releaseClient(for: conn) }
                }
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
                    
                    let array = [UInt8](data)
                    await MainActor.run {
                        self.terminalView?.feed(byteArray: ArraySlice(array))
                    }
                }
            }
        }
        
        await MainActor.run {
            self.isConnected = false
            self.ttyWriter = nil
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
        
        // Notify Manager to release reference
        if let conn = activeConnection {
            let taskConn = conn
            Task {
                await SSHConnectionManager.shared.releaseClient(for: taskConn)
            }
        }
        
        // Release references
        client = nil
        sftp = nil
        ttyWriter = nil
        activeConnection = nil
        
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