import Foundation
import Combine

enum RedisValue {
    case string(String)
    case list([String])
    case set([String]) // Using Array for easier indexing in UI, though Set is unordered
    case zset([(member: String, score: Double)])
    case hash([String: String])
    case none
    case unsupported(String)
}

struct RedisDBStat: Identifiable {
    let id: String
    let name: String
    let keys: Int
    let expires: Int
    let avgTTL: Int
}

struct RedisOverview {
    let version: String?
    let os: String?
    let processId: Int?
    let uptimeDays: Int?
    let role: String?
    let usedMemoryHuman: String?
    let peakMemoryHuman: String?
    let usedMemoryRssHuman: String?
    let memFragmentationRatio: Double?
    let luaMemoryHuman: String?
    let connectedClients: Int?
    let totalConnections: Int?
    let totalCommands: Int?
    let instantaneousOpsPerSec: Int?
    let keyspaceHits: Int?
    let keyspaceMisses: Int?
    let keyspaceHitRate: Double?
    let dbStats: [RedisDBStat]
}

/// Redis 视图模型，管理 Redis 连接、键值操作和状态
class RedisViewModel: ObservableObject, Cleanable {
    @Published var keys: [String] = []
    @Published var selectedKey: String?
    @Published var redisValue: RedisValue = .none
    @Published var isLoading = false
    @Published var errorMsg: String?
    @Published var searchText: String = ""
    @Published var exactMatch: Bool = false // 精确搜索标记
    @Published var currentDB: Int = 0 // 当前数据库索引
    @Published var overview: RedisOverview?
    @Published var searchHistory: [String] = []
    
    let client = RedisClient()
    var connection: SSHConnection // 改为 var 以支持更新
    
    private var scanCursor = "0"
    /// 标记是否已成功连接过（用于判断是否需要重新连接）
    private var hasConnected = false
    
    init(connection: SSHConnection) {
        self.connection = connection
        self.currentDB = connection.redisDB
        // Load search history
        if let history = UserDefaults.standard.stringArray(forKey: "RedisSearchHistory_\(connection.id)") {
            self.searchHistory = history
        }
    }
    
    func addToHistory(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Deduplicate: Remove if exists
        searchHistory.removeAll { $0 == key }
        // Insert at top
        searchHistory.insert(key, at: 0)
        // Limit to 50
        if searchHistory.count > 50 {
            searchHistory.removeLast()
        }
        // Save
        UserDefaults.standard.set(searchHistory, forKey: "RedisSearchHistory_\(connection.id)")
    }
    
    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "RedisSearchHistory_\(connection.id)")
    }
    
    func updateConnection(_ newConnection: SSHConnection) {
        self.connection = newConnection
        self.currentDB = newConnection.redisDB
        // 如果已连接，需要重新连接
        if hasConnected {
            reconnect()
        }
    }
    
    /// 连接到 Redis 服务器
    /// 如果已经连接，则直接刷新键列表和统计信息
    func connect() {
        // 如果已经连接，直接加载keys和统计信息
        if hasConnected && client.isConnected {
            loadKeys()
            loadOverview()
            return
        }
        
        // 防止重复连接
        guard !isLoading else { return }
        
        isLoading = true
        
        client.connect(host: connection.host, port: connection.port, password: connection.password, db: connection.redisDB) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.hasConnected = true
                    self.loadKeys()
                    self.loadOverview()
                    ToastManager.shared.show(message: "Redis Connected", type: .success)
                } else {
                    ToastManager.shared.show(message: self.client.lastError ?? "Connection Failed", type: .error)
                }
            }
        }
    }
    
    /// 重新连接 Redis 服务器
    func reconnect() {
        hasConnected = false
        connect()
    }
    
    // MARK: - 概览信息
    
    /// 加载 Redis 服务器概览信息（INFO 命令）
    func loadOverview() {
        client.sendCommand(["INFO"]) { res, err in
            if let err = err {
                DispatchQueue.main.async {
                    // 概览失败不影响主流程，只记录错误
                    if self.errorMsg == nil {
                        self.errorMsg = err.localizedDescription
                    }
                }
                return
            }
            // 兼容不同返回格式，将结果尽量转成字符串
            var infoString: String?
            if let s = res as? String {
                infoString = s
            } else if let arr = res as? [Any] {
                let parts = arr.compactMap { $0 as? String }
                if !parts.isEmpty {
                    infoString = parts.joined(separator: "\n")
                }
            }
            guard let info = infoString else { return }
            let overview = self.parseOverview(from: info)
            DispatchQueue.main.async {
                self.overview = overview
            }
        }
    }
    
    private func parseOverview(from info: String) -> RedisOverview {
        var dict: [String: String] = [:]
        var dbStats: [RedisDBStat] = []
        
        // Normalize line endings
        let normalizedInfo = info.replacingOccurrences(of: "\r\n", with: "\n")
                                 .replacingOccurrences(of: "\r", with: "\n")
        
        let lines = normalizedInfo.split(separator: "\n")
        for lineSub in lines {
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("db") {
                // db0:keys=1,expires=0,avg_ttl=0
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let name = String(parts[0])
                let statsPart = parts[1]
                var keys = 0
                var expires = 0
                var avgTTL = 0
                for kv in statsPart.split(separator: ",") {
                    let pair = kv.split(separator: "=", maxSplits: 1)
                    guard pair.count == 2 else { continue }
                    let k = pair[0]
                    let v = pair[1]
                    switch k {
                    case "keys": keys = Int(v) ?? 0
                    case "expires": expires = Int(v) ?? 0
                    case "avg_ttl": avgTTL = Int(v) ?? 0
                    default: break
                    }
                }
                dbStats.append(RedisDBStat(id: name, name: name, keys: keys, expires: expires, avgTTL: avgTTL))
            } else if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                dict[key] = value
            }
        }
        
        dbStats.sort { $0.name < $1.name }
        
        func intValue(_ key: String) -> Int? {
            if let v = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return Int(v)
            }
            return nil
        }
        
        func doubleValue(_ key: String) -> Double? {
            if let v = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return Double(v)
            }
            return nil
        }
        
        let hits = intValue("keyspace_hits")
        let misses = intValue("keyspace_misses")
        var hitRate: Double? = nil
        if let h = hits, let m = misses, (h + m) > 0 {
            hitRate = Double(h) / Double(h + m)
        }
        
        return RedisOverview(
            version: dict["redis_version"],
            os: dict["os"],
            processId: intValue("process_id"),
            uptimeDays: intValue("uptime_in_days"),
            role: dict["role"],
            usedMemoryHuman: dict["used_memory_human"],
            peakMemoryHuman: dict["used_memory_peak_human"],
            usedMemoryRssHuman: dict["used_memory_rss_human"],
            memFragmentationRatio: doubleValue("mem_fragmentation_ratio"),
            luaMemoryHuman: dict["used_memory_lua_human"],
            connectedClients: intValue("connected_clients"),
            totalConnections: intValue("total_connections_received"),
            totalCommands: intValue("total_commands_processed"),
            instantaneousOpsPerSec: intValue("instantaneous_ops_per_sec"),
            keyspaceHits: hits,
            keyspaceMisses: misses,
            keyspaceHitRate: hitRate,
            dbStats: dbStats
        )
    }
    
    /// 加载键列表
    /// 根据搜索文本和精确匹配设置，执行不同的搜索策略
    func loadKeys() {
        // 防止重复加载
        guard !isLoading || keys.isEmpty else { return }
        
        isLoading = true
        errorMsg = nil
        
        if searchText.isEmpty {
            // 快速预览随机键
            client.sendCommand(["SCAN", "0", "COUNT", "\(AppConstants.Redis.scanCount)"]) { res, err in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let err = err {
                        self.errorMsg = err.localizedDescription
                        self.keys = []
                    } else if let array = res as? [Any], array.count == 2,
                       let keysArray = (array[1] as? [Any])?.compactMap({ $0 as? String }) {
                        self.keys = keysArray.sorted()
                    } else {
                        self.keys = []
                    }
                }
            }
        } else {
            // 搜索逻辑
            if exactMatch {
                // 精确搜索：只检查该键是否存在
                client.sendCommand(["TYPE", searchText]) { res, _ in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let type = res as? String, type != "none" {
                            self.keys = [self.searchText]
                            self.addToHistory(self.searchText) // Add to history only if a result is found
                        } else {
                            self.keys = []
                        }
                    }
                }
            } else {
                // 模糊搜索：使用SCAN + MATCH
                let group = DispatchGroup()
                var foundKeys: Set<String> = []
                var searchError: Error?
                
                // 1. 检查精确匹配
                group.enter()
                client.sendCommand(["TYPE", searchText]) { res, err in
                    if let err = err {
                        searchError = err
                    } else if let type = res as? String, type != "none" {
                        foundKeys.insert(self.searchText)
                    }
                    group.leave()
                }
                
                // 2. 前缀扫描
                group.enter()
                let pattern = searchText.contains("*") ? searchText : "\(searchText)*"
                
                client.sendCommand(["SCAN", "0", "MATCH", pattern, "COUNT", "\(AppConstants.Redis.maxScanCount)"]) { res, err in
                    if let err = err {
                        searchError = err
                    } else if let array = res as? [Any], array.count == 2,
                       let keysArray = (array[1] as? [Any])?.compactMap({ $0 as? String }) {
                        foundKeys.formUnion(keysArray)
                    }
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    self.isLoading = false
                    if let err = searchError {
                        self.errorMsg = err.localizedDescription
                        self.keys = []
                    } else {
                        self.keys = Array(foundKeys).sorted()
                        if !self.keys.isEmpty { // Add to history only if results are found
                            self.addToHistory(self.searchText)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 数据库切换
    
    /// 切换到指定的数据库
    /// - Parameter db: 数据库索引（0-15）
    func switchDatabase(to db: Int) {
        isLoading = true
        client.sendCommand(["SELECT", "\(db)"]) { res, err in
            DispatchQueue.main.async {
                if err == nil {
                    self.currentDB = db
                    self.selectedKey = nil
                    self.redisValue = .none
                    self.loadKeys()
                    self.loadOverview()
                } else {
                    self.isLoading = false
                    self.errorMsg = err?.localizedDescription ?? "切换数据库失败"
                }
            }
        }
    }
        
    /// 加载指定键的值
    /// 根据键的类型自动选择合适的 Redis 命令
    /// - Parameter key: 要加载的键名
    func loadValue(key: String) {
        DispatchQueue.main.async {
            self.redisValue = .none
        }
        Logger.log("Loading value for key: \(key)", level: .debug)
        
        client.sendCommand(["TYPE", key]) { res, err in
            // Handle error immediately
            if let err = err {
                Logger.log("TYPE command error: \(err.localizedDescription)", level: .error)
                DispatchQueue.main.async {
                    self.errorMsg = err.localizedDescription
                    self.redisValue = .unsupported("Error loading type")
                }
                return
            }
            
            guard let type = res as? String else {
                Logger.log("Unknown TYPE response", level: .warning)
                DispatchQueue.main.async {
                    self.redisValue = .unsupported("Unknown Response")
                }
                return
            }
            
            Logger.log("Key type is \(type)", level: .debug)
            
            switch type {
            case "string":
                self.client.sendCommand(["GET", key]) { val, err in
                    DispatchQueue.main.async {
                        if let err = err { self.errorMsg = err.localizedDescription }
                        self.redisValue = .string((val as? String) ?? "")
                    }
                }
            case "list":
                self.client.sendCommand(["LRANGE", key, "0", "-1"]) { val, err in
                    DispatchQueue.main.async {
                        if let err = err { self.errorMsg = err.localizedDescription }
                        if let list = (val as? [Any])?.compactMap({ $0 as? String }) {
                            self.redisValue = .list(list)
                        } else {
                            self.redisValue = .list([])
                        }
                    }
                }
            case "set":
                self.client.sendCommand(["SMEMBERS", key]) { val, err in
                    DispatchQueue.main.async {
                        if let err = err { self.errorMsg = err.localizedDescription }
                        if let list = (val as? [Any])?.compactMap({ $0 as? String }) {
                            self.redisValue = .set(list.sorted())
                        } else {
                            self.redisValue = .set([])
                        }
                    }
                }
            case "zset":
                self.client.sendCommand(["ZRANGE", key, "0", "-1", "WITHSCORES"]) { val, err in
                    DispatchQueue.main.async {
                        if let err = err { self.errorMsg = err.localizedDescription }
                        if let list = (val as? [Any])?.compactMap({ $0 as? String }) {
                            var zitems: [(String, Double)] = []
                            for i in stride(from: 0, to: list.count, by: 2) {
                                if i + 1 < list.count {
                                    let member = list[i]
                                    let score = Double(list[i+1]) ?? 0.0
                                    zitems.append((member, score))
                                }
                            }
                            self.redisValue = .zset(zitems)
                        } else {
                            self.redisValue = .zset([])
                        }
                    }
                }
            case "hash":
                Logger.log("Sending HGETALL", level: .debug)
                self.client.sendCommand(["HGETALL", key]) { val, err in
                    DispatchQueue.main.async {
                        if let err = err {
                            Logger.log("HGETALL error: \(err.localizedDescription)", level: .error)
                            self.errorMsg = err.localizedDescription
                            self.redisValue = .hash(["Error": "Failed to load hash: \(err.localizedDescription)"])
                            return
                        }
                        
                        Logger.log("HGETALL received response", level: .debug)
                        if let raw = val as? [Any] {
                            let list: [String] = raw.map { item in
                                if let str = item as? String { return str }
                                if item is NSNull { return "(nil)" }
                                return String(describing: item)
                            }
                            var dict: [String: String] = [:]
                            for i in stride(from: 0, to: list.count, by: 2) {
                                if i + 1 < list.count {
                                    dict[list[i]] = list[i+1]
                                } else {
                                    // Handle odd number items safely
                                    dict[list[i]] = "(missing value)"
                                }
                            }
                            self.redisValue = .hash(dict)
                        } else {
                            self.redisValue = .hash([:])
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    self.redisValue = .unsupported(type)
                }
            }
        }
    }
    
    // MARK: - 修改操作
    
    /// 更新字符串类型的值
    func updateString(key: String, value: String) {
        Logger.log("Redis: SET \(key) = \(value.prefix(20))...", level: .info)
        client.sendCommand(["SET", key, value]) { [weak self] res, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    self.errorMsg = "Update failed: \(err.localizedDescription)"
                } else {
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func updateHash(key: String, field: String, value: String) {
        Logger.log("Redis: HSET \(key) \(field)", level: .info)
        client.sendCommand(["HSET", key, field, value]) { [weak self] _, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    self.errorMsg = err.localizedDescription
                } else {
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func deleteHashField(key: String, field: String) {
        client.sendCommand(["HDEL", key, field]) { [weak self] _, _ in
            self?.loadValue(key: key)
        }
    }
    
    func updateList(key: String, index: Int, value: String) {
        client.sendCommand(["LSET", key, String(index), value]) { [weak self] _, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    self.errorMsg = err.localizedDescription
                } else {
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func addToList(key: String, value: String) {
        client.sendCommand(["RPUSH", key, value]) { [weak self] _, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    self.errorMsg = err.localizedDescription
                } else {
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func deleteFromList(key: String, index: Int) {
        client.sendCommand(["LINDEX", key, String(index)]) { [weak self] val, err in
            guard let self = self else { return }
            if let valueToRemove = val as? String {
                self.client.sendCommand(["LREM", key, "1", valueToRemove]) { _, _ in
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func updateSet(key: String, oldValue: String, newValue: String) {
        if oldValue == newValue { return }
        
        DispatchQueue.main.async { self.isLoading = true }
        // Remove then Add
        client.sendCommand(["SREM", key, oldValue]) { [weak self] _, err in
            guard let self = self else { return }
            if let err = err {
                DispatchQueue.main.async {
                    self.isLoading = false
                    ToastManager.shared.show(message: "SREM failed: \(err.localizedDescription)", type: .error)
                }
                return
            }
            
            self.client.sendCommand(["SADD", key, newValue]) { _, err in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let err = err {
                        ToastManager.shared.show(message: "SADD failed: \(err.localizedDescription)", type: .error)
                    } else {
                        ToastManager.shared.show(message: "Update Successful", type: .success)
                    }
                    self.loadValue(key: key)
                }
            }
        }
    }
    
    func addToSet(key: String, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log("Redis: SADD \(key) \(trimmedValue)", level: .info)
        
        DispatchQueue.main.async { self.isLoading = true }
        client.sendCommand(["SADD", key, trimmedValue]) { [weak self] _, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let err = err {
                    ToastManager.shared.show(message: "Failed to add to set: \(err.localizedDescription)", type: .error)
                } else {
                    ToastManager.shared.show(message: "Added Successfully", type: .success)
                }
                self.loadValue(key: key)
            }
        }
    }
    
    func deleteFromSet(key: String, value: String) {
        Logger.log("Redis: SREM \(key) \(value)", level: .info)
        DispatchQueue.main.async { self.isLoading = true }
        client.sendCommand(["SREM", key, value]) { [weak self] _, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let err = err {
                    self.errorMsg = "Failed to remove from set: \(err.localizedDescription)"
                }
                self.loadValue(key: key)
            }
        }
    }
    
    func updateZSet(key: String, member: String, score: Double) {
        client.sendCommand(["ZADD", key, String(score), member]) { [weak self] _, _ in
            self?.loadValue(key: key)
        }
    }
    
    func deleteFromZSet(key: String, member: String) {
        client.sendCommand(["ZREM", key, member]) { [weak self] _, _ in
            self?.loadValue(key: key)
        }
    }
    
    // MARK: - 键管理
    
    /// 删除指定的键
    /// - Parameter key: 要删除的键名
    func deleteKey(key: String) {
        client.sendCommand(["DEL", key]) { _, _ in
            DispatchQueue.main.async {
                if self.selectedKey == key {
                    self.selectedKey = nil
                    self.redisValue = .none
                }
                // Refresh list
                self.loadKeys()
            }
        }
    }
    
    /// 创建新键
    /// - Parameters:
    ///   - key: 键名
    ///   - type: 键类型（String, Hash, List, Set, Sorted Set）
    ///   - context: 初始值上下文
    ///     - String: ["value": "初始值"]
    ///     - Hash: ["field": "字段名", "value": "字段值"]
    ///     - List: ["value": "初始项"]
    ///     - Set: ["value": "初始成员"]
    ///     - Sorted Set: ["score": "分数", "member": "成员"]
    func createKey(key: String, type: String, context: [String: String]) {
        
        var command: [String] = []
        
        switch type {
        case "String":
            if let val = context["value"] {
                command = ["SET", key, val]
            }
        case "Hash":
            if let f = context["field"], let v = context["value"] {
                command = ["HSET", key, f, v]
            }
        case "List":
            if let v = context["value"] {
                command = ["RPUSH", key, v]
            }
        case "Set":
            if let v = context["value"] {
                command = ["SADD", key, v]
            }
        case "Sorted Set":
            if let s = context["score"], let m = context["member"] {
                command = ["ZADD", key, s, m]
            }
        default:
            break
        }
        
        if !command.isEmpty {
            client.sendCommand(command) { _, err in
                DispatchQueue.main.async {
                    if let err = err {
                        self.errorMsg = err.localizedDescription
                    } else {
                        self.searchText = key // Focus on new key
                        self.loadKeys()
                        self.selectedKey = key
                    }
                }
            }
        }
    }
    
    func importData(key: String, type: String, values: [String], hashData: [String: String], completion: @escaping (Bool) -> Void) {
        isLoading = true
        errorMsg = nil
        
        let group = DispatchGroup()
        var lastError: String?
        
        switch type {
        case "List":
            let chunks = values.chunked(into: 100)
            for chunk in chunks {
                group.enter()
                var cmd = ["RPUSH", key]
                cmd.append(contentsOf: chunk)
                client.sendCommand(cmd) { _, err in
                    if let err = err { lastError = err.localizedDescription }
                    group.leave()
                }
            }
        case "Set":
            let chunks = values.chunked(into: 100)
            for chunk in chunks {
                group.enter()
                var cmd = ["SADD", key]
                cmd.append(contentsOf: chunk)
                client.sendCommand(cmd) { _, err in
                    if let err = err { lastError = err.localizedDescription }
                    group.leave()
                }
            }
        case "Hash":
            let fields = Array(hashData.keys)
            let chunks = fields.chunked(into: 50)
            for chunk in chunks {
                group.enter()
                var cmd = ["HSET", key]
                for f in chunk {
                    cmd.append(f)
                    cmd.append(hashData[f] ?? "")
                }
                client.sendCommand(cmd) { _, err in
                    if let err = err { lastError = err.localizedDescription }
                    group.leave()
                }
            }
        default:
            break
        }
        
        group.notify(queue: .main) {
            self.isLoading = false
            if let err = lastError {
                ToastManager.shared.show(message: "Import error: \(err)", type: .error)
                completion(false)
            } else {
                ToastManager.shared.show(message: "Import Completed", type: .success)
                self.loadKeys()
                completion(true)
            }
        }
    }
    
    func cleanup() {
        Logger.log("Cleaning up RedisViewModel for \(connection.name)", level: .info)
        client.disconnect()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

/// Redis ViewModel 管理器
/// 用于维护每个连接的 ViewModel 实例，实现连接复用和生命周期管理
class RedisViewModelManager: ObservableObject {
    static let shared = RedisViewModelManager()
    
    private var viewModels: [UUID: RedisViewModel] = [:]
    
    private init() {}
    
    func getViewModel(for connection: SSHConnection) -> RedisViewModel {
        if let existing = viewModels[connection.id] {
            existing.updateConnection(connection)
            return existing
        }
        let newViewModel = RedisViewModel(connection: connection)
        viewModels[connection.id] = newViewModel
        return newViewModel
    }
    
    func removeViewModel(for connectionId: UUID) {
        if let viewModel = viewModels[connectionId] {
            viewModel.client.disconnect()
            viewModels.removeValue(forKey: connectionId)
        }
    }
}
