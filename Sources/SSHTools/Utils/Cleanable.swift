import Foundation

/// 表示拥有可清理资源的实体（如 ViewModel 或 Client）
protocol Cleanable: AnyObject {
    func cleanup()
}
