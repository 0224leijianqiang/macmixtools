import Foundation
import Citadel
import Crypto
import NIO

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

    private func makeKey(host: String, port: Int, username: String) -> ConnectionKey {
        ConnectionKey(host: host, port: port, username: username)
    }

    private func trackDisconnect(for client: SSHClient, key: ConnectionKey) {
        let clientID = ObjectIdentifier(client)
        client.onDisconnect { [key, clientID] in
            Task {
                await SSHConnectionManager.shared.handleClientDisconnected(key: key, clientID: clientID)
            }
        }
    }

    private func handleClientDisconnected(key: ConnectionKey, clientID: ObjectIdentifier) {
        guard let current = clients[key], ObjectIdentifier(current) == clientID else { return }
        Logger.log("SSH: Cached client disconnected for \(key.host), removing from cache", level: .info)
        clients.removeValue(forKey: key)
    }
    
    func getClient(for connection: SSHConnection) async throws -> SSHClient {
        let port = Int(connection.port) ?? 22
        let key = makeKey(host: connection.host, port: port, username: connection.effectiveUsername)
        
        // Update reference count
        referenceCounts[key] = (referenceCounts[key] ?? 0) + 1
        Logger.log("SSH: Client requested for \(connection.host), ref count: \(referenceCounts[key]!)", level: .debug)
        
        // 1. Check existing active clients
        if let existing = clients[key] {
            if existing.isConnected {
                return existing
            }
            Logger.log("SSH: Cached client for \(connection.host) is not connected, recreating", level: .info)
            removeClient(key: key)
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
            trackDisconnect(for: client, key: key)
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
        let key = makeKey(host: connection.host, port: port, username: connection.effectiveUsername)
        
        let count = (referenceCounts[key] ?? 1) - 1
        referenceCounts[key] = max(0, count)
        
        Logger.log("SSH: Client released for \(connection.host), remaining ref count: \(referenceCounts[key]!)", level: .debug)
        
        if count <= 0 {
            Logger.log("SSH: No more references for \(connection.host), closing connection", level: .info)
            removeClient(host: connection.host, port: port, username: connection.effectiveUsername)
            referenceCounts.removeValue(forKey: key)
        }
    }

    /// Decrement reference count using an exact key (useful when auth profiles change after connecting).
    func releaseClient(host: String, port: Int, username: String) {
        let key = makeKey(host: host, port: port, username: username)
        let count = (referenceCounts[key] ?? 1) - 1
        referenceCounts[key] = max(0, count)

        Logger.log("SSH: Client released for \(host), remaining ref count: \(referenceCounts[key]!)", level: .debug)

        if count <= 0 {
            Logger.log("SSH: No more references for \(host), closing connection", level: .info)
            removeClient(host: host, port: port, username: username)
            referenceCounts.removeValue(forKey: key)
        }
    }
    
    private func createConnection(for connection: SSHConnection, port: Int) async throws -> SSHClient {
        var authMethod: SSHAuthenticationMethod = .passwordBased(username: connection.effectiveUsername, password: connection.effectivePassword)
        
        if connection.effectiveUseKey {
            let expandedKeyPath = NSString(string: connection.effectiveKeyPath).expandingTildeInPath
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
                        
                                        let decryptionKey = connection.effectiveKeyPassphrase.isEmpty ? nil : connection.effectiveKeyPassphrase.data(using: .utf8)
                                        
                                        if let edKey = try? Curve25519.Signing.PrivateKey(sshEd25519: keyString, decryptionKey: decryptionKey) {
                                            Logger.log("SSH: Successfully parsed Ed25519 key", level: .info)
                                            authMethod = .ed25519(username: connection.effectiveUsername, privateKey: edKey)
                                        } else if let p256 = try? P256.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-256 key", level: .info)
                                            authMethod = .p256(username: connection.effectiveUsername, privateKey: p256)
                                        } else if let p384 = try? P384.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-384 key", level: .info)
                                            authMethod = .p384(username: connection.effectiveUsername, privateKey: p384)
                                        } else if let p521 = try? P521.Signing.PrivateKey(pemRepresentation: keyString) {
                                            Logger.log("SSH: Successfully parsed P-521 key", level: .info)
                                            authMethod = .p521(username: connection.effectiveUsername, privateKey: p521)
                                        } else if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: keyString, decryptionKey: decryptionKey) {
                                            Logger.log("SSH: Successfully parsed RSA key", level: .info)
                                            authMethod = .rsa(username: connection.effectiveUsername, privateKey: rsaKey)
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
        
        // Proxy Handling
        if SettingsManager.shared.enableLocalProxy {
            let proxyHost = SettingsManager.shared.localProxyHost
            let proxyPort = Int(SettingsManager.shared.localProxyPort) ?? 7890
            
            Logger.log("SSH: Connecting via SOCKS5 proxy at \(proxyHost):\(proxyPort)", level: .info)
            
            do {
                // IMPORTANT:
                // Citadel's `connect(on: ...)` path uses `channel.pipeline.syncOperations` internally, which
                // requires being on the channel's EventLoop thread (otherwise it crashes with a precondition failure).
                //
                // To avoid that, we let Citadel create the channel to the proxy and install a SOCKS5 pre-handler.
                // The handler delays `channelActive` propagation until the SOCKS5 CONNECT tunnel is established,
                // so the SSH handshake starts only after the tunnel is ready.
                let socksHandler = SOCKS5ProxyHandler(targetHost: connection.host, targetPort: port)

                let client = try await Citadel.SSHClient.connect(
                    host: proxyHost,
                    port: proxyPort,
                    authenticationMethod: authMethod,
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never,
                    group: .singleton,
                    channelHandlers: [socksHandler],
                    connectTimeout: .seconds(10)
                )

                Logger.log("SSH: Proxy tunnel established to \(connection.host):\(port)", level: .info)
                return client
            } catch {
                Logger.log("SSH: Proxy connection failed - \(error.localizedDescription)", level: .error)
                throw error
            }
        }
        
        Logger.log("SSH: Connecting to \(connection.host):\(port) with user \(connection.effectiveUsername)", level: .info)
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
        let key = makeKey(host: connection.host, port: port, username: connection.effectiveUsername)
        removeClient(key: key)
    }

    func removeClient(host: String, port: Int, username: String) {
        let key = makeKey(host: host, port: port, username: username)
        removeClient(key: key)
    }

    private func removeClient(key: ConnectionKey) {
        
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
