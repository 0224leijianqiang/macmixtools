import Foundation

final class ClickHouseRunner {
    enum ClickHouseError: LocalizedError {
        case invalidURL
        case httpError(status: Int, body: String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid ClickHouse URL"
            case .httpError(let status, let body):
                return "ClickHouse HTTP \(status): \(body)"
            case .unexpectedResponse:
                return "Unexpected ClickHouse response"
            }
        }
    }

    func testConnection(connection: SSHConnection) async -> Bool {
        do {
            _ = try await executeRawQuery(connection: connection, database: connection.database, sql: "SELECT 1")
            return true
        } catch {
            return false
        }
    }

    func testConnectionOrThrow(connection: SSHConnection) async throws {
        _ = try await executeRawQuery(connection: connection, database: connection.database, sql: "SELECT 1")
    }

    func listDatabases(connection: SSHConnection) async throws -> [String] {
        let result = try await executeRawQuery(
            connection: connection,
            database: "",
            sql: "SELECT name FROM system.databases ORDER BY name"
        )
        return result.rows.compactMap { $0.first }
    }

    func listTables(connection: SSHConnection, database: String) async throws -> [String] {
        let safeDB = escapeStringLiteral(database)
        let result = try await executeRawQuery(
            connection: connection,
            database: database,
            sql: "SELECT name FROM system.tables WHERE database = '\(safeDB)' AND is_temporary = 0 ORDER BY name"
        )
        return result.rows.compactMap { $0.first }
    }

    func listAllColumns(connection: SSHConnection, database: String) async throws -> [String] {
        let safeDB = escapeStringLiteral(database)
        let result = try await executeRawQuery(
            connection: connection,
            database: database,
            sql: "SELECT DISTINCT name FROM system.columns WHERE database = '\(safeDB)' ORDER BY name"
        )
        return result.rows.compactMap { $0.first }
    }

    func executeRawQuery(connection: SSHConnection, database: String, sql: String) async throws -> QueryResult {
        let query = ensureJSONCompact(sql)
        let data = try await sendQuery(connection: connection, database: database, query: query)

        // ClickHouse may return plain text (e.g. "Ok.") for non-SELECT.
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("ok") {
                return QueryResult(headers: [], rows: [])
            }
            throw ClickHouseError.unexpectedResponse
        }

        let headers: [String] = (dict["meta"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let rows: [[String]] = (dict["data"] as? [[Any]])?.map { row in
            row.map { stringify($0) }
        } ?? []

        return QueryResult(headers: headers, rows: rows)
    }

    private func sendQuery(connection: SSHConnection, database: String, query: String) async throws -> Data {
        var endpoint = parseEndpoint(hostInput: connection.host, portInput: connection.port)
        if endpoint.scheme.isEmpty { endpoint.scheme = "http" }
        if endpoint.port == nil { endpoint.port = Int(AppConstants.Ports.clickhouse) ?? 8123 }
        if endpoint.host.isEmpty { throw ClickHouseError.invalidURL }

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/"

        var items: [URLQueryItem] = []
        if !database.isEmpty {
            items.append(URLQueryItem(name: "database", value: database))
        } else if !connection.database.isEmpty {
            items.append(URLQueryItem(name: "database", value: connection.database))
        }
        if !connection.effectiveUsername.isEmpty {
            items.append(URLQueryItem(name: "user", value: connection.effectiveUsername))
        }
        if !connection.effectivePassword.isEmpty {
            items.append(URLQueryItem(name: "password", value: connection.effectivePassword))
        }
        items.append(URLQueryItem(name: "query", value: query))
        components.queryItems = items

        guard let url = components.url else { throw ClickHouseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClickHouseError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClickHouseError.httpError(status: http.statusCode, body: body)
        }
        return data
    }

    private struct EndpointParts {
        var scheme: String
        var host: String
        var port: Int?
    }

    private func parseEndpoint(hostInput: String, portInput: String) -> EndpointParts {
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmedHost), components.host != nil {
            return EndpointParts(
                scheme: components.scheme ?? "",
                host: components.host ?? "",
                port: components.port
            )
        }

        // Support users pasting "http://host:8123" without a parsable URLComponents host (rare),
        // or pasting just "host:8123".
        if trimmedHost.contains("://") == false, trimmedHost.contains(":") {
            let parts = trimmedHost.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let p = Int(parts[1]) {
                return EndpointParts(scheme: "", host: parts[0], port: p)
            }
        }

        let port = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines))
        return EndpointParts(scheme: "", host: trimmedHost, port: port)
    }

    private func ensureJSONCompact(_ sql: String) -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "\\bformat\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        return "\(trimmed) FORMAT JSONCompact"
    }

    private func escapeStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "'", with: "\\\\'")
    }

    private func stringify(_ value: Any) -> String {
        if value is NSNull { return "NULL" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return String(describing: value)
    }
}
