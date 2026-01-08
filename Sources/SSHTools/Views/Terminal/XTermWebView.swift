import SwiftUI
import WebKit
import AppKit

struct XTermWebView: NSViewRepresentable {
    @ObservedObject var runner: SSHRunner

    private static func locateTerminalHTML() -> (bundle: Bundle, htmlURL: URL)? {
        // 1) SwiftPM resource bundle (works when run via `swift run` or when the generated resource bundle is present).
        let spmBundle = Bundle.module
        if let url = spmBundle.url(forResource: "terminal", withExtension: "html") {
            return (spmBundle, url)
        }

        // 2) When packaged as a .app, SwiftPM resources are often copied as a nested bundle in `Contents/Resources`.
        //    build_app.sh copies `SSHTools_SSHTools.bundle`, so look for that in Bundle.main.
        if let nestedBundleURL = Bundle.main.url(forResource: "SSHTools_SSHTools", withExtension: "bundle"),
           let nestedBundle = Bundle(url: nestedBundleURL),
           let url = nestedBundle.url(forResource: "terminal", withExtension: "html")
        {
            return (nestedBundle, url)
        }

        // 3) Fallback: scan for any `*_SSHTools.bundle` in the app resources (debug/release names can vary).
        if let resourcesURL = Bundle.main.resourceURL,
           let candidates = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil),
           let match = candidates.first(where: { $0.pathExtension == "bundle" && $0.lastPathComponent.hasSuffix("_SSHTools.bundle") }),
           let nestedBundle = Bundle(url: match),
           let url = nestedBundle.url(forResource: "terminal", withExtension: "html")
        {
            return (nestedBundle, url)
        }

        return nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(runner: runner)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "sshTerm")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Keep background controlled by the HTML/CSS; avoid AppKit default white.
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false

        context.coordinator.attach(webView: webView)
        runner.terminalOutput = context.coordinator

        if let located = Self.locateTerminalHTML(),
           let resourceRoot = located.bundle.resourceURL
        {
            Logger.log("Terminal: loading terminal.html from bundle=\(located.bundle.bundlePath)", level: .info)
            Logger.log("Terminal: terminal.html url=\(located.htmlURL.path)", level: .info)
            webView.loadFileURL(located.htmlURL, allowingReadAccessTo: resourceRoot)
        } else {
            Logger.log("Terminal: failed to locate terminal.html in Bundle.module or app resources", level: .error)
            let fallbackHTML = """
            <!doctype html><html><body style="background:#000;color:#9ef;font:12px Menlo,monospace;padding:12px;">
            Failed to locate terminal resources.
            <br/><br/>
            Expected to find either:
            <br/>- SwiftPM Bundle.module resources, or
            <br/>- Contents/Resources/SSHTools_SSHTools.bundle/terminal/terminal.html
            </body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        runner.terminalOutput = context.coordinator
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, TerminalOutputSink {
        private weak var runner: SSHRunner?
        private weak var webView: WKWebView?
        private var isLoaded = false
        private var pendingWritesB64: [String] = []
        private var flushScheduled = false

        init(runner: SSHRunner) {
            self.runner = runner
        }

        func attach(webView: WKWebView) {
            self.webView = webView
        }

        func detach() {
            isLoaded = false
            pendingWritesB64.removeAll()
            flushScheduled = false
            runner?.terminalOutput = nil
        }

        func writeToTerminal(_ data: Data) {
            let b64 = data.base64EncodedString()
            pendingWritesB64.append(b64)
            scheduleFlush()
        }

        private func scheduleFlush() {
            guard !flushScheduled else { return }
            flushScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushScheduled = false
                self?.flushIfReady()
            }
        }

        private func flushIfReady() {
            guard isLoaded, let webView else { return }
            guard !pendingWritesB64.isEmpty else { return }

            let batch = pendingWritesB64
            pendingWritesB64.removeAll()

            for b64 in batch {
                webView.evaluateJavaScript("window.sshToolsWriteBase64('\(b64)')", completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            flushIfReady()
            webView.evaluateJavaScript("window.sshToolsFocus && window.sshToolsFocus()", completionHandler: nil)
            webView.evaluateJavaScript("typeof window.Terminal") { result, error in
                if let error {
                    Logger.log("Terminal: JS probe failed: \(error.localizedDescription)", level: .error)
                    return
                }
                Logger.log("Terminal: JS probe typeof Terminal = \(result ?? "nil")", level: .info)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Logger.log("Terminal: webview didCommit", level: .debug)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Logger.log("Terminal: webview didStartProvisionalNavigation", level: .debug)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Logger.log("Terminal: web content process terminated", level: .error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            Logger.log("Terminal: webview provisional navigation failed: \(error.localizedDescription)", level: .error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            Logger.log("Terminal: webview navigation failed: \(error.localizedDescription)", level: .error)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "sshTerm" else { return }
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String
            else { return }

            switch type {
            case "input":
                guard let b64 = dict["b64"] as? String,
                      let data = Data(base64Encoded: b64)
                else { return }
                runner?.send(data: data)

            case "resize":
                let cols = dict["cols"] as? Int ?? 80
                let rows = dict["rows"] as? Int ?? 24
                runner?.resize(cols: cols, rows: rows)

            case "copy":
                guard let text = dict["text"] as? String, !text.isEmpty else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)

            case "pasteRequest":
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                guard !text.isEmpty else { return }
                if let data = text.data(using: .utf8) {
                    runner?.send(data: data)
                }

            case "cwd":
                guard let raw = dict["data"] as? String else { return }
                let cleaned = Self.cleanDirectoryFromOSC7(raw)
                guard !cleaned.isEmpty else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let runner = self?.runner else { return }
                    if runner.currentPath != cleaned {
                        runner.currentPath = cleaned
                    }
                }

            case "ready":
                Logger.log("Terminal: xterm.js ready", level: .info)
                DispatchQueue.main.async { [weak self] in
                    self?.runner?.notifyTerminalReady()
                }

            case "jsError":
                if let msg = dict["message"] as? String {
                    Logger.log("Terminal: xterm.js error: \(msg)", level: .error)
                } else {
                    Logger.log("Terminal: xterm.js error", level: .error)
                }

            default:
                break
            }
        }

        private static func cleanDirectoryFromOSC7(_ raw: String) -> String {
            var dir = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if dir.isEmpty { return "" }

            if dir.hasPrefix("file://") {
                let components = dir.components(separatedBy: "://")
                if components.count > 1 {
                    let pathWithHost = components[1]
                    if let firstSlashIndex = pathWithHost.firstIndex(of: "/") {
                        dir = String(pathWithHost[firstSlashIndex...])
                    } else {
                        dir = "/"
                    }
                }
            }

            if let decoded = dir.removingPercentEncoding {
                dir = decoded
            }

            if dir.isEmpty { return "/" }
            return dir
        }
    }
}
