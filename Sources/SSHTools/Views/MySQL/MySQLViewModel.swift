import SwiftUI

class MySQLViewModel: ObservableObject {
    let connection: SSHConnection
    private let runner = MySQLRunner()
    
    @Published var databases: [String] = []
    @Published var currentDatabase: String = "" {
        didSet {
            if !currentDatabase.isEmpty && oldValue != currentDatabase {
                loadTables()
            }
        }
    }
    
    @Published var tables: [String] = []
    @Published var currentTable: String? {
        didSet {
            if currentTable != nil && oldValue != currentTable {
                currentMode = .tableData // Automatically switch to data mode
                page = 1
                whereClause = ""
                orderBy = ""
                loadData()
            }
        }
    }
    
    @Published var headers: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnWidths: [CGFloat] = []
    @Published var isLoading = false
    @Published var errorMsg: String?
    
    // Pagination & Query
    @Published var page: Int = 1
    @Published var limit: Int = 10 {
        didSet {
            if oldValue != limit {
                page = 1 // Reset page on limit change
                loadData()
            }
        }
    }
    let limitOptions = [10, 20, 50, 100, 200, 500]
    
    @Published var whereClause: String = ""
    @Published var orderBy: String = ""
    
    // Console Support
    enum MySQLMode {
        case overview
        case tableData
        case console
    }
    @Published var currentMode: MySQLMode = .overview
    @Published var sqlEditorText: String = "SELECT * FROM "
    
    struct MySQLInfo {
        let version: String
        let uptime: String
        let threads: String
        let questions: String
        let slowQueries: String
        let openTables: String
    }
    @Published var serverInfo: MySQLInfo?
    
    init(connection: SSHConnection) {
        self.connection = connection
        self.currentDatabase = connection.database
    }
    
    func updateColumnWidth(index: Int, width: CGFloat) {
        if index < columnWidths.count {
            columnWidths[index] = width
        }
    }
    
    func connect() {
        isLoading = true
        Task {
            let success = await runner.testConnection(connection: connection)
            await MainActor.run {
                if success {
                    loadDatabases()
                    loadServerInfo()
                    ToastManager.shared.show(message: "MySQL Connected", type: .success)
                } else {
                    isLoading = false
                    ToastManager.shared.show(message: "MySQL Connection Failed", type: .error)
                }
            }
        }
    }
    
    func loadServerInfo() {
        Task {
            do {
                let statusResult = try await runner.executeRawQuery(connection: connection, database: "", sql: "SHOW GLOBAL STATUS")
                let versionResult = try await runner.executeRawQuery(connection: connection, database: "", sql: "SELECT VERSION()")
                
                await MainActor.run {
                    var statusDict: [String: String] = [:]
                    for row in statusResult.rows {
                        if row.count >= 2 {
                            statusDict[row[0]] = row[1]
                        }
                    }
                    
                    self.serverInfo = MySQLInfo(
                        version: versionResult.rows.first?.first ?? "Unknown",
                        uptime: statusDict["Uptime"] ?? "0",
                        threads: statusDict["Threads_connected"] ?? "0",
                        questions: statusDict["Questions"] ?? "0",
                        slowQueries: statusDict["Slow_queries"] ?? "0",
                        openTables: statusDict["Open_tables"] ?? "0"
                    )
                }
            } catch {
                Logger.log("Failed to load MySQL server info: \(error)", level: .warning)
            }
        }
    }
    
    func loadDatabases() {
        isLoading = true
        Task {
            do {
                let dbs = try await runner.listDatabases(connection: connection)
                await MainActor.run {
                    self.databases = dbs
                    self.isLoading = false
                    // Auto select
                    if !self.currentDatabase.isEmpty && self.databases.contains(self.currentDatabase) {
                        self.loadTables()
                    } else if let first = self.databases.first, self.currentDatabase.isEmpty {
                        self.currentDatabase = first // Will trigger didSet -> loadTables
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Failed to list databases: \(error.localizedDescription)", type: .error)
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadTables() {
        guard !currentDatabase.isEmpty else { return }
        // Ensure we don't trigger recursive loops or UI glitches
        Task {
            await MainActor.run { self.isLoading = true }
            do {
                let tbls = try await runner.listTables(connection: connection, database: currentDatabase)
                await MainActor.run {
                    self.tables = tbls
                    self.isLoading = false
                    self.currentTable = nil
                    self.headers = []
                    self.rows = []
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func executeRawSQL() {
        guard !currentDatabase.isEmpty else { return }
        let sql = sqlEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        
        Task {
            await MainActor.run { 
                self.isLoading = true 
                self.errorMsg = nil
            }
            do {
                let result = try await runner.executeRawQuery(connection: connection, database: currentDatabase, sql: sql)
                await MainActor.run {
                    self.headers = result.headers
                    self.columnWidths = Array(repeating: 150.0, count: self.headers.count)
                    self.rows = result.rows
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "SQL Error: \(error.localizedDescription)", type: .error)
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadData() {
        guard let table = currentTable, !currentDatabase.isEmpty else { return }
        let offset = (page - 1) * limit
        
        let query = "SELECT * FROM `\(table)`"
        var finalQuery = query
        
        if !whereClause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalQuery += " WHERE \(whereClause)"
        }
        
        if !orderBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalQuery += " ORDER BY \(orderBy)"
        }
        
        finalQuery += " LIMIT \(limit) OFFSET \(offset)"
        
        let sqlToExecute = finalQuery // Create a local immutable copy
        
        Task {
            await MainActor.run { 
                self.isLoading = true 
                self.errorMsg = nil
            }
            do {
                let result = try await runner.executeRawQuery(connection: connection, database: currentDatabase, sql: sqlToExecute)
                await MainActor.run {
                    self.headers = result.headers
                    // Reset column widths if headers changed
                    if self.columnWidths.count != self.headers.count {
                        self.columnWidths = Array(repeating: 150.0, count: self.headers.count)
                    }
                    self.rows = result.rows
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func nextPage() {
        page += 1
        loadData()
    }
    
    func prevPage() {
        if page > 1 {
            page -= 1
            loadData()
        }
    }
}
