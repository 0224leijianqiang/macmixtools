import SwiftUI
import AppKit

class MySQLViewModel: ObservableObject {
    let connection: SSHConnection
    private let mysqlRunner = MySQLRunner()
    private let clickHouseRunner = ClickHouseRunner()

    var databaseProductName: String {
        switch connection.type {
        case .clickhouse: return "ClickHouse"
        default: return "MySQL"
        }
    }
    
    @Published var databases: [String] = []
    @Published var currentDatabase: String = "" {
        didSet {
            if !currentDatabase.isEmpty && oldValue != currentDatabase {
                loadTables()
                loadAllColumns()
            }
        }
    }
    
    @Published var tables: [String] = []
    @Published var allColumns: [String] = []
	@Published var currentTable: String? {
		didSet {
			if currentTable != nil && oldValue != currentTable {
				currentMode = .tableData // Automatically switch to data mode
				page = 1
				whereClause = ""
				orderBy = ""
				loadFilterPresets()
				loadPrimaryKeys()
				loadData()
			}
		}
	}
    
    @Published var headers: [String] = []
    @Published var rows: [[String]] = []
    @Published var columnWidths: [CGFloat] = []
	@Published var selectedRowIndex: Int? = nil
	@Published var selectedRowIndices: Set<Int> = []
	@Published var selectionAnchorRowIndex: Int? = nil
	@Published var selectedColumnIndex: Int? = nil
	@Published var primaryKeyColumns: [String] = []
	@Published var isLoading = false
    @Published var isConnected = false
    @Published var errorMsg: String?

    @Published var showUnsafeMutationAlert: Bool = false
    @Published var unsafeMutationMessage: String = ""
    private var pendingUnsafeSQLToRun: String? = nil
    
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
    @Published var orderBy: String = "" {
        didSet {
            if oldValue != orderBy && !isUpdatingOrderByFromSort {
                sortColumnName = nil
                sortDirection = nil
            }
        }
    }

    struct FilterPreset: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var whereClause: String
        var createdAt: Date = Date()
    }
    @Published var filterPresets: [FilterPreset] = []

    enum SortDirection {
        case asc
        case desc
    }
    @Published var sortColumnName: String? = nil
    @Published var sortDirection: SortDirection? = nil
    private var isUpdatingOrderByFromSort = false
    
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

    private func filterPresetsStorageKey(database: String, table: String) -> String {
        "mysql.filterPresets.\(connection.id.uuidString).\(database).\(table)"
    }

    func loadFilterPresets() {
        guard let table = currentTable, !currentDatabase.isEmpty else {
            filterPresets = []
            return
        }
        let key = filterPresetsStorageKey(database: currentDatabase, table: table)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FilterPreset].self, from: data) {
            filterPresets = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            filterPresets = []
        }
    }

    func saveFilterPreset(name: String, whereClause: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhere = whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedWhere.isEmpty else { return }
        guard let table = currentTable, !currentDatabase.isEmpty else { return }

        var presets = filterPresets
        presets.removeAll { $0.name == trimmedName }
        presets.insert(FilterPreset(name: trimmedName, whereClause: trimmedWhere), at: 0)
        filterPresets = presets

        let key = filterPresetsStorageKey(database: currentDatabase, table: table)
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        ToastManager.shared.show(message: "Saved Filter Preset", type: .success)
    }

    func deleteFilterPreset(id: UUID) {
        guard let table = currentTable, !currentDatabase.isEmpty else { return }
        filterPresets.removeAll { $0.id == id }
        let key = filterPresetsStorageKey(database: currentDatabase, table: table)
        if let encoded = try? JSONEncoder().encode(filterPresets) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        ToastManager.shared.show(message: "Deleted Filter Preset", type: .success)
    }

    func applyFilterPreset(_ preset: FilterPreset) {
        whereClause = preset.whereClause
        page = 1
        loadData()
    }

    func toggleSort(columnName: String) {
        if sortColumnName != columnName {
            sortColumnName = columnName
            sortDirection = .asc
        } else {
            switch sortDirection {
            case .asc:
                sortDirection = .desc
            case .desc:
                sortColumnName = nil
                sortDirection = nil
            case nil:
                sortDirection = .asc
            }
        }

        isUpdatingOrderByFromSort = true
        defer { isUpdatingOrderByFromSort = false }

        if let col = sortColumnName, let dir = sortDirection {
            let quoted = "`" + col.replacingOccurrences(of: "`", with: "``") + "`"
            switch dir {
            case .asc:
                orderBy = "\(quoted) ASC"
            case .desc:
                orderBy = "\(quoted) DESC"
            }
        } else {
            orderBy = ""
        }

        page = 1
        loadData()
    }
    
    func updateColumnWidth(index: Int, width: CGFloat) {
        if index < columnWidths.count {
            columnWidths[index] = width
        }
    }

	func clearSelection() {
		selectedRowIndex = nil
		selectedRowIndices = []
		selectionAnchorRowIndex = nil
		selectedColumnIndex = nil
		dragSelectionAnchorRowIndex = nil
	}

	private var dragSelectionAnchorRowIndex: Int? = nil

	func beginDragSelection(anchorRowIndex: Int) {
		dragSelectionAnchorRowIndex = anchorRowIndex
		selectedRowIndices = [anchorRowIndex]
		selectedRowIndex = anchorRowIndex
		selectionAnchorRowIndex = anchorRowIndex
		selectedColumnIndex = nil
	}

	func updateDragSelection(targetRowIndex: Int) {
		guard let anchor = dragSelectionAnchorRowIndex else {
			beginDragSelection(anchorRowIndex: targetRowIndex)
			return
		}
		let lower = min(anchor, targetRowIndex)
		let upper = max(anchor, targetRowIndex)
		selectedRowIndices = Set(lower...upper)
		selectedRowIndex = targetRowIndex
		selectionAnchorRowIndex = anchor
		selectedColumnIndex = nil
	}

	func endDragSelection() {
		dragSelectionAnchorRowIndex = nil
	}

	func loadPrimaryKeys() {
		guard connection.type != .clickhouse else {
			primaryKeyColumns = []
			return
		}
		guard let table = currentTable, !currentDatabase.isEmpty else {
			primaryKeyColumns = []
			return
		}

		Task {
			do {
				let safeDB = currentDatabase.replacingOccurrences(of: "'", with: "''")
				let safeTable = table.replacingOccurrences(of: "'", with: "''")
				let sql = """
				SELECT k.COLUMN_NAME
				FROM information_schema.table_constraints t
				JOIN information_schema.key_column_usage k
				  ON t.constraint_name = k.constraint_name
				 AND t.table_schema = k.table_schema
				 AND t.table_name = k.table_name
				WHERE t.constraint_type = 'PRIMARY KEY'
				  AND t.table_schema = '\(safeDB)'
				  AND t.table_name = '\(safeTable)'
				ORDER BY k.ORDINAL_POSITION
				"""
				let result = try await executeRawQuery(database: currentDatabase, sql: sql)
				let cols = result.rows.compactMap { $0.first }.filter { !$0.isEmpty }
				await MainActor.run {
					self.primaryKeyColumns = cols
				}
			} catch {
				await MainActor.run {
					self.primaryKeyColumns = []
				}
			}
		}
	}

	private func sqlIdentifier(_ name: String) -> String {
		"`" + name.replacingOccurrences(of: "`", with: "``") + "`"
	}

	private func sqlLiteral(_ value: String, quoteAsString: Bool) -> String {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.uppercased() == "NULL" { return "NULL" }
		if quoteAsString {
			return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
		}
		return value
	}

	private func buildPrimaryKeyWhereClause(for row: [String]) -> String? {
		guard !primaryKeyColumns.isEmpty else { return nil }
		var parts: [String] = []
		parts.reserveCapacity(primaryKeyColumns.count)
		for pk in primaryKeyColumns {
			guard let idx = headers.firstIndex(of: pk), row.indices.contains(idx) else { return nil }
			let raw = row[idx]
			if raw == "NULL" {
				parts.append("\(sqlIdentifier(pk)) IS NULL")
			} else {
				parts.append("\(sqlIdentifier(pk)) = \(sqlLiteral(raw, quoteAsString: true))")
			}
		}
		return parts.joined(separator: " AND ")
	}

	func updateCell(rowIndex: Int, columnIndex: Int, newValue: String, setNull: Bool, quoteAsString: Bool) async throws {
		guard connection.type != .clickhouse else {
			throw NSError(domain: "SSHTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "ClickHouse does not support UPDATE in this UI"])
		}
		guard let table = currentTable, !currentDatabase.isEmpty else { return }
		guard rows.indices.contains(rowIndex), headers.indices.contains(columnIndex) else { return }
		let row = rows[rowIndex]
		guard let whereClause = buildPrimaryKeyWhereClause(for: row) else {
			throw NSError(domain: "SSHTools", code: 2, userInfo: [NSLocalizedDescriptionKey: "No primary key found for this table"])
		}

		let columnName = headers[columnIndex]
		let qualified = sqlIdentifier(currentDatabase) + "." + sqlIdentifier(table)
		let setValue = setNull ? "NULL" : sqlLiteral(newValue, quoteAsString: quoteAsString)
		let sql = "UPDATE \(qualified) SET \(sqlIdentifier(columnName)) = \(setValue) WHERE \(whereClause) LIMIT 1"

		_ = try await executeRawQuery(database: currentDatabase, sql: sql)
	}

    func selectColumn(index: Int?) {
        selectedColumnIndex = index
        selectedRowIndex = nil
        selectedRowIndices = []
        selectionAnchorRowIndex = nil
    }

	func selectRow(rowIndex: Int, columnIndex: Int?) {
		selectRow(rowIndex: rowIndex, columnIndex: columnIndex, modifierFlags: NSEvent.modifierFlags)
	}

	func selectRow(rowIndex: Int, columnIndex: Int?, modifierFlags: NSEvent.ModifierFlags) {
		let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
		let isCommand = flags.contains(.command)
		let isShift = flags.contains(.shift)

		if isShift {
			let anchor = selectionAnchorRowIndex ?? selectedRowIndex ?? selectedRowIndices.sorted().last ?? rowIndex
			let lower = min(anchor, rowIndex)
			let upper = max(anchor, rowIndex)
			let rangeSet = Set(lower...upper)
			if isCommand {
				selectedRowIndices.formUnion(rangeSet)
			} else {
				selectedRowIndices = rangeSet
			}
			selectionAnchorRowIndex = anchor
		} else if isCommand {
			if selectedRowIndices.contains(rowIndex) {
				selectedRowIndices.remove(rowIndex)
			} else {
				selectedRowIndices.insert(rowIndex)
				selectionAnchorRowIndex = rowIndex
			}
		} else {
			selectedRowIndices = [rowIndex]
			selectionAnchorRowIndex = rowIndex
		}

		if selectedRowIndices.contains(rowIndex) {
			selectedRowIndex = rowIndex
		} else {
			selectedRowIndex = selectedRowIndices.sorted().last
		}
		if selectedRowIndices.isEmpty {
			selectionAnchorRowIndex = nil
		} else if selectionAnchorRowIndex == nil {
			selectionAnchorRowIndex = selectedRowIndex
		}
		selectedColumnIndex = columnIndex
	}
    
    func connect() {
        isLoading = true
        Task {
            let (success, errorMessage) = await testConnectionWithError()
            await MainActor.run {
                self.isConnected = success
                if success {
                    loadDatabases()
                    loadAllColumns()
                    loadServerInfo()
                    ToastManager.shared.show(message: "\(self.databaseProductName) Connected", type: .success)
                } else {
                    isLoading = false
                    self.errorMsg = errorMessage
                    ToastManager.shared.show(
                        message: "\(self.databaseProductName) Connection Failed" + (errorMessage != nil ? ": \(errorMessage!)" : ""),
                        type: .error
                    )
                }
            }
        }
    }

    func loadServerInfo() {
        Task {
            do {
                switch connection.type {
                case .clickhouse:
                    let versionResult = try await executeRawQuery(database: "", sql: "SELECT version()")
                    let uptimeResult = try await executeRawQuery(database: "", sql: "SELECT uptime()")
                    await MainActor.run {
                        self.serverInfo = MySQLInfo(
                            version: versionResult.rows.first?.first ?? "Unknown",
                            uptime: uptimeResult.rows.first?.first ?? "0",
                            threads: "-",
                            questions: "-",
                            slowQueries: "-",
                            openTables: "-"
                        )
                    }
                default:
                    let statusResult = try await executeRawQuery(database: "", sql: "SHOW GLOBAL STATUS")
                    let versionResult = try await executeRawQuery(database: "", sql: "SELECT VERSION()")

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
                }
            } catch {
                Logger.log("Failed to load DB server info: \(error)", level: .warning)
            }
        }
    }
    
    func loadDatabases() {
        isLoading = true
        Task {
            do {
                let dbs = try await listDatabases()
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
    
    func loadAllColumns() {
        guard !currentDatabase.isEmpty else { return }
        Task {
            do {
                let cols = try await listAllColumns(database: currentDatabase)
                await MainActor.run {
                    self.allColumns = cols
                }
            } catch {
                Logger.log("Failed to load columns: \(error)", level: .warning)
            }
        }
    }

    func loadTables() {
        guard !currentDatabase.isEmpty else { return }
        // Ensure we don't trigger recursive loops or UI glitches
        Task {
            await MainActor.run { self.isLoading = true }
            do {
                let tbls = try await listTables(database: currentDatabase)
                await MainActor.run {
                    self.tables = tbls
                    self.isLoading = false
                    self.currentTable = nil
					self.headers = []
					self.rows = []
					self.filterPresets = []
					self.primaryKeyColumns = []
					self.clearSelection()
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

        if shouldConfirmUnsafeMutation(sql: sql) {
            pendingUnsafeSQLToRun = sql
            unsafeMutationMessage = "UPDATE/DELETE without WHERE can affect all rows. Continue?"
            showUnsafeMutationAlert = true
            return
        }

        executeRawSQLInternal(sql: sql)
    }

    func runPendingUnsafeMutationAnyway() {
        guard let sql = pendingUnsafeSQLToRun else { return }
        pendingUnsafeSQLToRun = nil
        showUnsafeMutationAlert = false
        executeRawSQLInternal(sql: sql)
    }

    func cancelPendingUnsafeMutation() {
        pendingUnsafeSQLToRun = nil
        showUnsafeMutationAlert = false
    }

    private func executeRawSQLInternal(sql: String) {
        
        Task {
            await MainActor.run { 
                self.isLoading = true 
                self.errorMsg = nil
                self.clearSelection()
            }
            do {
                let result = try await executeRawQuery(database: currentDatabase, sql: sql)
                await MainActor.run {
                    self.headers = result.headers
                    self.columnWidths = Array(repeating: 150.0, count: self.headers.count)
                    self.rows = result.rows
                    self.clearSelection()
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

    private enum MutationKind {
        case update
        case delete
        case other
    }

    private func mutationKind(of sql: String) -> MutationKind {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("update ") { return .update }
        if lower.hasPrefix("delete ") { return .delete }
        return .other
    }

    private func hasWhereClause(sql: String) -> Bool {
        let lower = sql.lowercased()
        return lower.contains(" where ")
    }

    func shouldConfirmUnsafeMutation(sql: String) -> Bool {
        guard connection.type != .clickhouse else { return false }
        let kind = mutationKind(of: sql)
        guard kind == .update || kind == .delete else { return false }
        return !hasWhereClause(sql: sql)
    }

    func canEstimateAffectedRows(sql: String) -> Bool {
        guard connection.type != .clickhouse else { return false }
        let kind = mutationKind(of: sql)
        guard kind == .update || kind == .delete else { return false }
        return hasWhereClause(sql: sql)
    }

    func estimateAffectedRows(sql: String) async throws -> Int? {
        guard canEstimateAffectedRows(sql: sql) else { return nil }
        guard !currentDatabase.isEmpty else { return nil }

        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns: [MutationKind: String] = [
            .update: #"(?is)^\s*update\s+([`"\w\.\-]+)\s+set\b.*?\bwhere\b(.*)$"#,
            .delete: #"(?is)^\s*delete\s+from\s+([`"\w\.\-]+)\b.*?\bwhere\b(.*)$"#
        ]

        let kind = mutationKind(of: trimmed)
        guard let pattern = patterns[kind] else { return nil }

        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 3,
              let tableRange = Range(match.range(at: 1), in: trimmed),
              let whereRange = Range(match.range(at: 2), in: trimmed)
        else { return nil }

        let table = String(trimmed[tableRange])
        var wherePart = String(trimmed[whereRange])
        wherePart = wherePart.trimmingCharacters(in: .whitespacesAndNewlines)
        wherePart = wherePart.replacingOccurrences(of: #";\s*$"#, with: "", options: .regularExpression)
        wherePart = wherePart.replacingOccurrences(of: #"(?is)\s+(order\s+by|limit)\b.*$"#, with: "", options: .regularExpression)

        if wherePart.isEmpty { return nil }

        let countSQL = "SELECT COUNT(*) AS cnt FROM \(table) WHERE \(wherePart)"
        let result = try await executeRawQuery(database: currentDatabase, sql: countSQL)
        guard let first = result.rows.first?.first else { return nil }
        return Int(first.trimmingCharacters(in: .whitespacesAndNewlines))
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
                self.clearSelection()
            }
            do {
                let result = try await executeRawQuery(database: currentDatabase, sql: sqlToExecute)
                await MainActor.run {
                    self.headers = result.headers
                    // Reset column widths if headers changed
                    if self.columnWidths.count != self.headers.count {
                        self.columnWidths = Array(repeating: 150.0, count: self.headers.count)
                    }
                    self.rows = result.rows
                    self.clearSelection()
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

    enum ExportFormat: String {
        case csv
        case tsv
        case json

        var fileExtension: String { rawValue }
    }

    private func makeSelectSQL(limit: Int, offset: Int) -> String? {
        guard let table = currentTable, !currentDatabase.isEmpty else { return nil }

        let query = "SELECT * FROM `\(table)`"
        var finalQuery = query

        if !whereClause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalQuery += " WHERE \(whereClause)"
        }

        if !orderBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalQuery += " ORDER BY \(orderBy)"
        }

        finalQuery += " LIMIT \(limit) OFFSET \(offset)"
        return finalQuery
    }

    private func csvEscape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    private func tsvEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func write(_ string: String, to handle: FileHandle) throws {
        if let data = string.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    func exportCurrentResult(to url: URL, format: ExportFormat) throws {
        try exportRows(headers: headers, rows: rows, to: url, format: format)
    }

    func exportRows(headers: [String], rows: [[String]], to url: URL, format: ExportFormat) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        switch format {
        case .csv:
            try write(headers.map(csvEscape).joined(separator: ",") + "\n", to: handle)
            for row in rows {
                let line = row.map(csvEscape).joined(separator: ",")
                try write(line + "\n", to: handle)
            }
        case .tsv:
            try write(headers.map(tsvEscape).joined(separator: "\t") + "\n", to: handle)
            for row in rows {
                let line = row.map(tsvEscape).joined(separator: "\t")
                try write(line + "\n", to: handle)
            }
        case .json:
            try write("[\n", to: handle)
            for (idx, row) in rows.enumerated() {
                let count = min(headers.count, row.count)
                var dict: [String: String] = [:]
                dict.reserveCapacity(count)
                for i in 0..<count {
                    dict[headers[i]] = row[i]
                }
                let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
                let jsonLine = String(data: data, encoding: .utf8) ?? "{}"
                let suffix = (idx == rows.count - 1) ? "\n" : ",\n"
                try write("  " + jsonLine + suffix, to: handle)
            }
            try write("]\n", to: handle)
        }
    }

    func exportAllTableData(
        to url: URL,
        format: ExportFormat,
        pageSize: Int = 1000,
        onProgress: @escaping (_ rowsExported: Int) -> Void
    ) async throws {
        guard !headers.isEmpty || currentTable != nil else { return }
        guard let _ = currentTable else { return }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var totalRows = 0
        var offset = 0
        var wroteJSONPrefix = false
        var wroteHeader = false
        var firstJSONItem = true

        while true {
            if Task.isCancelled { throw CancellationError() }
            guard let sql = makeSelectSQL(limit: pageSize, offset: offset) else { break }

            let result = try await executeRawQuery(database: currentDatabase, sql: sql)
            if result.headers.isEmpty { break }
            if result.rows.isEmpty { break }

            if !wroteHeader {
                switch format {
                case .csv:
                    try write(result.headers.map(csvEscape).joined(separator: ",") + "\n", to: handle)
                case .tsv:
                    try write(result.headers.map(tsvEscape).joined(separator: "\t") + "\n", to: handle)
                case .json:
                    break
                }
                wroteHeader = true
            }

            switch format {
            case .csv:
                for row in result.rows {
                    if Task.isCancelled { throw CancellationError() }
                    try write(row.map(csvEscape).joined(separator: ",") + "\n", to: handle)
                }
            case .tsv:
                for row in result.rows {
                    if Task.isCancelled { throw CancellationError() }
                    try write(row.map(tsvEscape).joined(separator: "\t") + "\n", to: handle)
                }
            case .json:
                if !wroteJSONPrefix {
                    try write("[\n", to: handle)
                    wroteJSONPrefix = true
                }
                for row in result.rows {
                    if Task.isCancelled { throw CancellationError() }
                    let count = min(result.headers.count, row.count)
                    var dict: [String: String] = [:]
                    dict.reserveCapacity(count)
                    for i in 0..<count {
                        dict[result.headers[i]] = row[i]
                    }
                    let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
                    let jsonLine = String(data: data, encoding: .utf8) ?? "{}"
                    if firstJSONItem {
                        firstJSONItem = false
                        try write("  " + jsonLine, to: handle)
                    } else {
                        try write(",\n  " + jsonLine, to: handle)
                    }
                }
            }

            totalRows += result.rows.count
            onProgress(totalRows)
            offset += result.rows.count

            if result.rows.count < pageSize { break }
        }

        if format == .json {
            if wroteJSONPrefix {
                try write("\n]\n", to: handle)
            } else {
                try write("[]\n", to: handle)
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

    private func testConnectionWithError() async -> (Bool, String?) {
        switch connection.type {
        case .clickhouse:
            do {
                if Int(connection.port) == 9000 {
                    return (false, "ClickHouse HTTP interface is usually on port 8123 (current is 9000)")
                }
                try await clickHouseRunner.testConnectionOrThrow(connection: connection)
                return (true, nil)
            } catch {
                return (false, error.localizedDescription)
            }
        default:
            let ok = await mysqlRunner.testConnection(connection: connection)
            if ok { return (true, nil) }
            return (false, mysqlRunner.errorMsg)
        }
    }

    private func listDatabases() async throws -> [String] {
        switch connection.type {
        case .clickhouse:
            return try await clickHouseRunner.listDatabases(connection: connection)
        default:
            return try await mysqlRunner.listDatabases(connection: connection)
        }
    }

    private func listTables(database: String) async throws -> [String] {
        switch connection.type {
        case .clickhouse:
            return try await clickHouseRunner.listTables(connection: connection, database: database)
        default:
            return try await mysqlRunner.listTables(connection: connection, database: database)
        }
    }

    private func listAllColumns(database: String) async throws -> [String] {
        switch connection.type {
        case .clickhouse:
            return try await clickHouseRunner.listAllColumns(connection: connection, database: database)
        default:
            let sql = "SELECT DISTINCT COLUMN_NAME FROM information_schema.columns WHERE table_schema = '\(database)'"
            let result = try await mysqlRunner.executeRawQuery(connection: connection, database: database, sql: sql)
            return result.rows.compactMap { $0.first }
        }
    }

    private func executeRawQuery(database: String, sql: String) async throws -> QueryResult {
        switch connection.type {
        case .clickhouse:
            return try await clickHouseRunner.executeRawQuery(connection: connection, database: database, sql: sql)
        default:
            return try await mysqlRunner.executeRawQuery(connection: connection, database: database, sql: sql)
        }
    }
}
