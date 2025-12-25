import Foundation
import AppKit
import SwiftUI

/// 统一错误处理工具
struct ErrorHandler {
    /// 显示错误提示
    static func showError(_ message: String, informativeText: String? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = informativeText ?? ""
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    /// 显示成功提示
    static func showSuccess(_ message: String, informativeText: String? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = informativeText ?? ""
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    /// 显示确认对话框
    static func showConfirmation(_ message: String, informativeText: String? = nil, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = informativeText ?? ""
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }
}

/// 错误类型枚举
enum AppError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case invalidConfiguration(String)
    case operationFailed(String)
    case fileOperationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "连接失败: \(message)"
        case .authenticationFailed(let message):
            return "认证失败: \(message)"
        case .invalidConfiguration(let message):
            return "配置无效: \(message)"
        case .operationFailed(let message):
            return "操作失败: \(message)"
        case .fileOperationFailed(let message):
            return "文件操作失败: \(message)"
        }
    }
}

