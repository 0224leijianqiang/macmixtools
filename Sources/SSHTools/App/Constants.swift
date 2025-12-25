import Foundation

/// 应用常量定义
enum AppConstants {
    /// 默认端口
    enum Ports {
        static let ssh = "22"
        static let redis = "6379"
        static let mysql = "3306"
    }
    
    /// 默认路径
    enum Paths {
        static let defaultSSHKey = "~/.ssh/id_rsa"
        static let homeDirectory = "~/"
        static let rootDirectory = "/"
    }
    
    /// 连接超时时间（秒）
    enum Timeouts {
        static let sshConnection = 10
        static let sshCommand = 5
    }
    
    /// Redis 相关
    enum Redis {
        static let maxDatabases = 16
        static let defaultDatabase = 0
        static let scanCount = 100
        static let maxScanCount = 10000
    }
    
    /// UI 相关
    enum UI {
        static let maxOpenTabs = 5
        static let cursorBlinkInterval = 0.6
        static let tableMaxWidth: CGFloat = 1200
        static let searchDebounceInterval: TimeInterval = 0.3
    }
    
    /// 存储键
    struct StorageKeys {
        static let savedConnections = "saved_connections"
        static let defaultDownloadPath = "default_download_path"
        static let geminiApiKey = "gemini_api_key"
        static let terminalBackgroundImagePath = "terminal_background_image_path"
    }
    
    /// 固定 ID 用于侧边栏和标签页匹配
    enum FixedIDs {
        static let httpClient = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        static let devToolbox = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    }
    
    /// Keychain 服务标识
    enum Keychain {
        static let service = "com.sshtools.connection.password"
    }
}

/// 日志工具（用于替换 print 语句）
struct Logger {
    enum Level {
        case debug
        case info
        case warning
        case error
    }
    
    #if DEBUG
    static func log(_ message: String, level: Level = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let prefix: String
        switch level {
        case .debug: prefix = "🔍 [DEBUG]"
        case .info: prefix = "ℹ️ [INFO]"
        case .warning: prefix = "⚠️ [WARN]"
        case .error: prefix = "❌ [ERROR]"
        }
        print("\(prefix) [\(fileName):\(line)] \(function) - \(message)")
    }
    #else
    static func log(_ message: String, level: Level = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        // 生产环境不输出日志
    }
    #endif
}

