import Foundation

/// 应用常量定义
enum AppConstants {
    /// 默认端口
    enum Ports {
        static let ssh = "22"
        static let redis = "6379"
        static let mysql = "3306"
        static let clickhouse = "8123"
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
        static let maxDatabases = 50
        static let defaultDatabase = 0
        static let scanCount = 100
        static let maxScanCount = 10000
    }
    
    /// UI 相关
    enum UI {
        static let maxOpenTabs = 5
        /// 单个标签页下内容区域的最大分屏数
        static let maxContentSplits = 3
        static let cursorBlinkInterval = 0.6
        static let tableMaxWidth: CGFloat = 1200
        static let searchDebounceInterval: TimeInterval = 0.3
    }

    /// 更新相关
    enum Update {
        /// GitHub 仓库标识（owner/repo）
        static let repository = "liam798/PrismShell"
        /// GitHub Releases API 基础地址
        static let releasesAPIBase = "https://api.github.com/repos"
        /// GitHub raw 内容基础地址
        static let rawContentBase = "https://raw.githubusercontent.com"
        /// 描述文件所在分支
        static let descriptorBranch = "master"
        /// 版本描述文件相对路径（位于 default 分支根目录）
        static let descriptorPath = "version-config.json"
        /// 默认本地版本号（当 Info.plist 缺失时使用）
        static let fallbackVersion = "1.0.1"
        /// 自动检查的最小间隔（秒），设为 0 表示每次冷启动都检查
        static let minimumCheckInterval: TimeInterval = 0
    }
    
    /// 存储键
    struct StorageKeys {
        static let savedConnections = "saved_connections"
        static let defaultDownloadPath = "default_download_path"
        static let geminiApiKey = "gemini_api_key"
        static let terminalBackgroundImagePath = "terminal_background_image_path"
        static let lastUpdateCheck = "last_update_check_timestamp"
        static let lastNotifiedVersion = "last_notified_version"
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

extension Notification.Name {
    static let sshtoolsCurrentPathChanged = Notification.Name("sshtools.currentPath.changed")
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
