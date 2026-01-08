import Foundation

enum DownloadStatus: Equatable {
    case none
    case queuing
    case transferring
    case completed
    case failed(String)
    
    var title: String {
        switch self {
        case .none: return "Idle"
        case .queuing: return "Queuing"
        case .transferring: return "Transferring"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
    
    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.queuing, .queuing): return true
        case (.transferring, .transferring): return true
        case (.completed, .completed): return true
        case (.failed(let lhsError), .failed(let rhsError)): return lhsError == rhsError
        default: return false
        }
    }
}

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case ssh
    case redis
    case mysql
    case clickhouse
    
    var id: String { self.rawValue }
    var icon: String {
        switch self {
        case .ssh: return "terminal.fill"
        case .redis: return "cylinder.split.1x2.fill"
        case .mysql: return "server.rack"
        case .clickhouse: return "server.rack"
        }
    }
}

enum TransferType: String, Codable {
    case upload
    case download
}

struct TransferTask: Identifiable {
    let id = UUID()
    let fileName: String
    let remotePath: String
    let localPath: String
    let type: TransferType
    var progress: Double = 0.0
    var status: DownloadStatus = .queuing
    var totalSize: Int64 = 0
    var transferredSize: Int64 = 0
}

class RemoteFile: Identifiable, ObservableObject {
    var id = UUID()
    var name: String
    var permissions: String
    @Published var size: String
    var rawSize: Int64
    var date: String
    var owner: String
    var group: String
    var isDirectory: Bool
    
    @Published var downloadProgress: Double? = nil
    @Published var downloadStatus: DownloadStatus = .none
    
    init(id: UUID = UUID(), name: String, permissions: String, size: String, rawSize: Int64 = 0, date: String, owner: String = "", group: String = "", isDirectory: Bool) {
        self.id = id
        self.name = name
        self.permissions = permissions
        self.size = size
        self.rawSize = rawSize
        self.date = date
        self.owner = owner
        self.group = group
        self.isDirectory = isDirectory
    }
}

struct SSHAuthProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var alias: String
    var username: String
    var useKey: Bool = true
    var keyPath: String = ""
    var password: String = "" // In a real app, use Keychain. For this prototype, we follow existing pattern.
    var keyPassphrase: String = ""
}

struct SSHConnection: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: ConnectionType = .ssh
    var name: String
    var host: String
    var port: String = "22"
    var username: String
    var useKey: Bool = true
    var keyPath: String = ""
    var database: String = ""
    var redisDB: Int = 0
    
    // Auth Profile Reference
    var authProfileId: UUID? = nil
    
    // In-memory only, not persisted to UserDefaults
    var password: String = ""
    var keyPassphrase: String = ""

    var connectionString: String {
        return "\(username)@\(host)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, host, port, username, useKey, keyPath, database, redisDB, authProfileId, password, keyPassphrase
    }
}

extension SSHConnection {
    // Helper to get effective credentials (from profile or manual)
    var effectiveUsername: String {
        if let profileId = authProfileId, let profile = AuthProfileManager.shared.profiles.first(where: { $0.id == profileId }) {
            return profile.username
        }
        return username
    }
    
    var effectiveUseKey: Bool {
        if let profileId = authProfileId, let profile = AuthProfileManager.shared.profiles.first(where: { $0.id == profileId }) {
            return profile.useKey
        }
        return useKey
    }
    
    var effectiveKeyPath: String {
        if let profileId = authProfileId, let profile = AuthProfileManager.shared.profiles.first(where: { $0.id == profileId }) {
            return profile.keyPath
        }
        return keyPath
    }
    
    var effectivePassword: String {
        if let profileId = authProfileId, let profile = AuthProfileManager.shared.profiles.first(where: { $0.id == profileId }) {
            return profile.password
        }
        return password
    }
    
    var effectiveKeyPassphrase: String {
        if let profileId = authProfileId, let profile = AuthProfileManager.shared.profiles.first(where: { $0.id == profileId }) {
            return profile.keyPassphrase
        }
        return keyPassphrase
    }
}

struct ConnectionGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var connectionIds: [UUID] = []
}
