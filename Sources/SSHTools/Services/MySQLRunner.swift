import Foundation
import MySQLKit
import NIOPosix

class MySQLRunner: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var errorMsg: String?
    
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    // Persistent pool storage
    private var poolCache: [String: EventLoopGroupConnectionPool<MySQLConnectionSource>] = [:]
    private let lock = NSLock()
    
    init() {}
    
    deinit {
        shutdownAllPools()
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    private func shutdownAllPools() {
        lock.lock()
        defer { lock.unlock() }
        for pool in poolCache.values {
            pool.shutdown()
        }
        poolCache.removeAll()
    }
    
    private func getCachedPool(connection: SSHConnection, database: String? = nil) -> EventLoopGroupConnectionPool<MySQLConnectionSource> {
        let db = database ?? (connection.database.isEmpty ? nil : connection.database)
        let poolKey = "\(connection.host):\(connection.port):\(connection.effectiveUsername):\(db ?? "none")"
        
        lock.lock()
        defer { lock.unlock() }
        
        if let existingPool = poolCache[poolKey] {
            return existingPool
        }
        
        let port = Int(connection.port) ?? 3306
        let config = MySQLConfiguration(
            hostname: connection.host,
            port: port,
            username: connection.effectiveUsername,
            password: connection.effectivePassword,
            database: db,
            tlsConfiguration: .none
        )
        
        let source = MySQLConnectionSource(configuration: config)
        let newPool = EventLoopGroupConnectionPool(source: source, on: eventLoopGroup)
        poolCache[poolKey] = newPool
        return newPool
    }
    
    func testConnection(connection: SSHConnection) async -> Bool {
        // We don't use cache for "test" usually, or we use it to warm up
        let pool = getCachedPool(connection: connection)
        
        do {
            _ = try await pool.withConnection { conn in
                conn.simpleQuery("SELECT 1")
            }.get()
            
            await MainActor.run { self.isConnected = true }
            return true
        } catch {
            await MainActor.run {
                self.isConnected = false
                self.errorMsg = error.localizedDescription
            }
            return false
        }
    }
    
    func listDatabases(connection: SSHConnection) async throws -> [String] {
        let pool = getCachedPool(connection: connection)
        
        let rows = try await pool.withConnection { conn in
            conn.simpleQuery("SHOW DATABASES")
        }.get()
        
        return rows.compactMap { row in
            row.column("Database")?.string
        }
    }
    
    func listTables(connection: SSHConnection, database: String) async throws -> [String] {
        let pool = getCachedPool(connection: connection, database: database)
        
        let safeDB = database.replacingOccurrences(of: "'", with: "") 
        let query = "SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA = '\(safeDB)'"
        
        let rows = try await pool.withConnection { conn in
            conn.simpleQuery(query)
        }.get()
        
        return rows.compactMap { $0.column("TABLE_NAME")?.string }
    }
    
    func executeRawQuery(connection: SSHConnection, database: String, sql: String) async throws -> QueryResult {
        let pool = getCachedPool(connection: connection, database: database)
        
        let dataRows = try await pool.withConnection { conn in
            conn.simpleQuery(sql)
        }.get()
        
        guard !dataRows.isEmpty else {
            return QueryResult(headers: [], rows: [])
        }
        
        // 1. Dynamically extract headers from the first row
        let headers = dataRows.first?.columnNames ?? []
        
        // 2. Parse rows
        var resultRows: [[String]] = []
        for row in dataRows {
            var rowStrings: [String] = []
            for header in headers {
                if let val = row.column(header) {
                    if let str = val.string {
                        rowStrings.append(str)
                    } else if let int = val.int {
                        rowStrings.append(String(int))
                    } else if let double = val.double {
                        rowStrings.append(String(double))
                    } else if let bool = val.bool {
                        rowStrings.append(String(bool))
                    } else if val.buffer == nil {
                        rowStrings.append("NULL")
                    } else {
                        rowStrings.append("\(val)")
                    }
                } else {
                    rowStrings.append("NULL")
                }
            }
            resultRows.append(rowStrings)
        }
        
        return QueryResult(headers: headers, rows: resultRows)
    }
}

extension MySQLRow {
    var columnNames: [String] {
        // In MySQLNIO, column names are stored in columnDefinitions
        return self.columnDefinitions.map { $0.name }
    }
}

// Ensure QueryResult is available
struct QueryResult {
    let headers: [String]
    let rows: [[String]]
}