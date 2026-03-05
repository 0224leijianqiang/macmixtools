import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // Force the app to be a regular GUI app (shows in Dock, has menu bar)
        NSApp.setActivationPolicy(.regular)
        
        // Try to set app icon programmatically if bundled
        if let iconPath = Bundle.module.path(forResource: "AppIcon", ofType: "icns"),
           let iconImage = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImage
        }
        
        // Bring to front and focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Set window size to 90% of screen，并隐藏系统默认红绿灯按钮（使用自定义实现）
        if let window = NSApp.windows.first,
           let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth = screenFrame.width * 0.9
            let windowHeight = screenFrame.height * 0.9
            
            // Center the window
            let windowX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let windowY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
            
            let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
            window.setFrame(newFrame, display: true)
            
            // 隐藏系统自带的交通灯按钮，改用 SwiftUI 自定义按钮
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { type in
                window.standardWindowButton(type)?.isHidden = true
            }
            
            // Ensure the window can receive key events
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct SSHToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(
                    WindowConfigurator { window in
                        window.toolbar = nil
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.styleMask.insert(.fullSizeContentView)
                        window.isMovableByWindowBackground = true
                    }
                )
                .ignoresSafeArea(.container, edges: .top)
                .preferredColorScheme(settings.userTheme.colorScheme)
                .task {
                    await UpdateChecker.shared.checkForUpdates()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
