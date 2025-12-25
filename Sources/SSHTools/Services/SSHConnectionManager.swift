import Foundation
import Citadel
import Crypto

/// Manages SSH connections to enable reuse/multiplexing.
/// Prevents multiple TCP connections for the same host/port/user.
actor SSHConnectionManager {
    static let shared = SSHConnectionManager()
    
    private init() {}
    
    struct ConnectionKey: Hashable {
        let host: String
        let port: Int
        let username: String
    }
    
    private var clients: [ConnectionKey: SSHClient] = [:]
    private var connectionTasks: [ConnectionKey: Task<SSHClient, Error>] = [:]
    private var referenceCounts: [ConnectionKey: Int] = [:]
    
    func getClient(for connection: SSHConnection) async throws -> SSHClient {
        let port = Int(connection.port) ?? 22
        let key = ConnectionKey(host: connection.host, port: port, username: connection.username)
        
        // Update reference count
        referenceCounts[key] = (referenceCounts[key] ?? 0) + 1
        Logger.log("SSH: Client requested for \(connection.host), ref count: \(referenceCounts[key]!)", level: .debug)
        
        // 1. Check existing active clients
        if let existing = clients[key] {
            return existing
        }
        
        // 2. Check in-flight tasks
        if let existingTask = connectionTasks[key] {
            return try await existingTask.value
        }
        
        // 3. Create new connection task
        let task = Task {
            do {
                let client = try await createConnection(for: connection, port: port)
                return client
            } catch {
                throw error
            }
        }
        
        connectionTasks[key] = task
        
        do {
            let client = try await task.value
            clients[key] = client
            connectionTasks[key] = nil // Clear task on success
            return client
        } catch {
            connectionTasks[key] = nil // Clear task on failure
            referenceCounts[key] = max(0, (referenceCounts[key] ?? 1) - 1)
            throw error
        }
    }
    
    /// Decrement reference count and close client if it reaches zero
    func releaseClient(for connection: SSHConnection) {
        let port = Int(connection.port) ?? 22
        let key = ConnectionKey(host: connection.host, port: port, username: connection.username)
        
        let count = (referenceCounts[key] ?? 1) - 1
        referenceCounts[key] = max(0, count)
        
        Logger.log("SSH: Client released for \(connection.host), remaining ref count: \(referenceCounts[key]!)", level: .debug)
        
        if count <= 0 {
            Logger.log("SSH: No more references for \(connection.host), closing connection", level: .info)
            removeClient(for: connection)
            referenceCounts.removeValue(forKey: key)
        }
    }
    
    private func createConnection(for connection: SSHConnection, port: Int) async throws -> SSHClient {
        var authMethod: SSHAuthenticationMethod = .passwordBased(username: connection.username, password: connection.password)
        
        if connection.useKey {
            let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
            Logger.log("SSH: Using private key at path: \(expandedKeyPath)", level: .info)
            
            if FileManager.default.fileExists(atPath: expandedKeyPath) {
                do {
                    let keyData = try Data(contentsOf: URL(fileURLWithPath: expandedKeyPath))
                    if var keyString = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        
                        // Legacy PEM conversion logic
                        if keyString.contains("BEGIN RSA PRIVATE KEY") || keyString.contains("BEGIN PRIVATE KEY") {
                            Logger.log("SSH: Legacy PEM detected, attempting conversion", level: .info)
                            if let converted = SSHKeyUtils.convertToOpenSSHFormat(at: expandedKeyPath) {
                                keyString = converted
                            }
                        }
                        
                                        let decryptionKey = connection.keyPassphrase.isEmpty ? nil : connection.keyPassphrase.data(using: .utf8)
                                        
                                        if let edKey = try? Curve25519.Signing.PrivateKey(sshEd25519: keyString, decryptionKey: decryptionKey) {
                                            Logger.log("SSH: Successfully parsed Ed25519 key", level: .info)
                                            authMethod = .ed25519(username: connection.username, privateKey: edKey)
                                        } else if let p256 = try? P256.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-256 key", level: .info)
                                            authMethod = .p256(username: connection.username, privateKey: p256)
                                        } else if let p384 = try? P384.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-384 key", level: .info)
                                            authMethod = .p384(username: connection.username, privateKey: p384)
                                        } else if let p521 = try? P521.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-521 key", level: .info)
                                            authMethod = .p521(username: connection.username, privateKey: p521)
                                        } else if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: keyString, decryptionKey: decryptionKey) {
                                            Logger.log("SSH: Successfully parsed RSA key", level: .info)
                                            authMethod = .rsa(username: connection.username, privateKey: rsaKey)
                                        } else {                            Logger.log("SSH: Failed to parse private key format", level: .error)
                        }
                    } else {
                        Logger.log("SSH: Private key file is not a valid UTF-8 string", level: .error)
                    }
                } catch {
                    Logger.log("SSH: Failed to read private key file: \(error)", level: .error)
                }
            } else {
                Logger.log("SSH: Private key file does not exist: \(expandedKeyPath)", level: .error)
            }
        }
        
        Logger.log("SSH: Connecting to \(connection.host):\(port) with user \(connection.username)", level: .info)
        return try await Citadel.SSHClient.connect(
            host: connection.host,
            port: port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(), // In a real app, should verify host keys
            reconnect: .never
        )
    }
    
    func removeClient(for connection: SSHConnection) {
        let port = Int(connection.port) ?? 22
        let key = ConnectionKey(host: connection.host, port: port, username: connection.username)
        
        // Cancel pending task
        if let task = connectionTasks[key] {
            task.cancel()
            connectionTasks.removeValue(forKey: key)
        }
        
        if let client = clients[key] {
            // Close in background
            Task { try? await client.close() }
            clients.removeValue(forKey: key)
        }
    }
    
    func disconnectAll() async {
        let allClients = Array(clients.values)
        clients.removeAll()
        connectionTasks.removeAll()
        
        for client in allClients {
            try? await client.close()
        }
    }
}