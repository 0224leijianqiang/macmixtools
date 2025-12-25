import Foundation
import RediStack
import NIO
import Logging

/// Redis Error Types
enum RedisError: Error {
    case connectionFailed
    case sendFailed
    case receiveFailed
    case errorResponse(String)
}

class RedisClient: ObservableObject {
    private var connection: RedisConnection?
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    @Published var isConnected = false
    @Published var lastError: String?
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    func connect(host: String, port: String, password: String, db: Int, completion: @escaping (Bool) -> Void) {
        let portInt = Int(port) ?? 6379
        
        do {
            let config = try RedisConnection.Configuration(
                hostname: host,
                port: portInt,
                password: password.isEmpty ? nil : password,
                initialDatabase: db
            )
            
            // Connect
            RedisConnection.make(
                configuration: config,
                boundEventLoop: eventLoopGroup.next()
            ).whenComplete { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let conn):
                    self.connection = conn
                    
                    // Handle unexpected closures (e.g. network lost)
                    conn.onUnexpectedClosure = { [weak self] in
                        DispatchQueue.main.async {
                            self?.isConnected = false
                            self?.lastError = "Connection closed unexpectedly"
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.isConnected = true
                        completion(true)
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        self.isConnected = false
                        completion(false)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "Configuration error: \(error.localizedDescription)"
                completion(false)
            }
        }
    }
    
    func disconnect() {
        if let conn = connection {
            conn.close().whenComplete { _ in
                // Connection closed gracefully
            }
        }
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    // Map raw command args to RediStack
    func sendCommand(_ args: [String], completion: @escaping (Any?, Error?) -> Void) {
        guard let connection = connection else {
            completion(nil, RedisError.connectionFailed)
            return
        }
        
        guard !args.isEmpty else { return }
        
        // Convert [String] to RESPValue
        let command = args[0]
        let arguments = args.dropFirst().map { RESPValue(from: $0) }
        
        // Send arbitrary command
        connection.send(command: command, with: arguments)
            .whenComplete { result in
                switch result {
                case .success(let respValue):
                    // Convert RESPValue to Any? (String, Int, Array, etc) for UI
                    let mapped = self.mapRESPValue(respValue)
                    completion(mapped, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
    }
    
    // Helper to map RediStack.RESPValue to the format your UI expects
    private func mapRESPValue(_ value: RESPValue) -> Any? {
        switch value {
        case .simpleString(let buffer):
            return String(buffer: buffer)
        case .bulkString(let buffer):
            return buffer.map { String(buffer: $0) } ?? nil // Null bulk string
        case .integer(let int):
            return int
        case .array(let values):
            return values.map { mapRESPValue($0) }
        case .error(let err):
            // RediStack wraps error responses in .error
            return err.message
        case .null:
            return nil
        }
    }
}