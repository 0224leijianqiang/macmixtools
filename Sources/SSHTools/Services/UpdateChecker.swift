import Foundation
import AppKit

/// GitHub Releases 检查更新服务
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private struct VersionDescriptor: Decodable {
        let latestVersion: String
        let downloadURL: String?
        let releaseNotes: String?
        let releasePage: String?
    }

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// 外部调用入口
    /// - Parameter force: 是否忽略间隔限制强制检查
    func checkForUpdates(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let now = Date()

        if !force {
            if let lastCheck = defaults.object(forKey: AppConstants.StorageKeys.lastUpdateCheck) as? Date,
               now.timeIntervalSince(lastCheck) < AppConstants.Update.minimumCheckInterval {
                return
            }
        }

        defaults.set(now, forKey: AppConstants.StorageKeys.lastUpdateCheck)

        guard let request = buildDescriptorRequest() else {
            Logger.log("无法构建版本描述文件请求", level: .error)
            return
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.log("版本描述文件请求失败", level: .warning)
                return
            }

            let descriptor = try JSONDecoder().decode(VersionDescriptor.self, from: data)
            let latestVersion = sanitizeVersion(descriptor.latestVersion)
            guard isRemoteVersionNewer(latest: latestVersion) else {
                return
            }

            if !force {
                let lastNotified = defaults.string(forKey: AppConstants.StorageKeys.lastNotifiedVersion)
                if lastNotified == latestVersion {
                    return
                }
            }

            defaults.set(latestVersion, forKey: AppConstants.StorageKeys.lastNotifiedVersion)

            let fallbackReleaseURL = "https://github.com/\(AppConstants.Update.repository)/releases/latest"
            let releaseURL = descriptor.releasePage ?? fallbackReleaseURL
            let downloadURL = descriptor.downloadURL ?? releaseURL
            notifyUser(latestVersion: latestVersion, releaseURL: releaseURL, downloadURL: downloadURL, releaseNotes: descriptor.releaseNotes)
        } catch {
            Logger.log("检查更新失败: \(error.localizedDescription)", level: .warning)
        }
    }

    private func buildDescriptorRequest() -> URLRequest? {
        let path = "\(AppConstants.Update.rawContentBase)/\(AppConstants.Update.repository)/\(AppConstants.Update.descriptorBranch)/\(AppConstants.Update.descriptorPath)"
        guard let url = URL(string: path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("SSHTools/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func currentVersion() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return AppConstants.Update.fallbackVersion
    }

    private func sanitizeVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func isRemoteVersionNewer(latest: String) -> Bool {
        let current = sanitizeVersion(currentVersion())
        return compareVersion(latest, isGreaterThan: current)
    }

    private func compareVersion(_ lhs: String, isGreaterThan rhs: String) -> Bool {
        let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func notifyUser(latestVersion: String, releaseURL: String, downloadURL: String, releaseNotes: String?) {
        let message = "发现新版本 \(latestVersion)，点击“下载”前往获取最新安装包。"
        ToastManager.shared.show(message: message, type: .info)

        let alert = NSAlert()
        alert.messageText = "检测到新版本 \(latestVersion)"
        if let notes = releaseNotes, !notes.isEmpty {
            alert.informativeText = notes
        } else {
            alert.informativeText = "是否打开浏览器下载最新版本？"
        }
        alert.addButton(withTitle: "下载")
        alert.addButton(withTitle: "查看发布页")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: downloadURL) ?? URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
}
