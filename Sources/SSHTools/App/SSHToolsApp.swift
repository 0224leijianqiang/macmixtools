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
        
        // Set window size to 90% of screen
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
        }
        
        // Ensure the window can receive key events
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct SSHToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.userTheme.colorScheme)
        }
        .defaultSize(width: 1200, height: 800)
    }
}
