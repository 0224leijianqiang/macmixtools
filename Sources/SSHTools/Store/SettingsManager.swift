import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var defaultDownloadPath: String {
        didSet {
            UserDefaults.standard.set(defaultDownloadPath, forKey: AppConstants.StorageKeys.defaultDownloadPath)
        }
    }
    
    @Published var geminiApiKey: String {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: AppConstants.StorageKeys.geminiApiKey)
        }
    }
    
    @Published var terminalBackgroundImagePath: String {
        didSet {
            UserDefaults.standard.set(terminalBackgroundImagePath, forKey: AppConstants.StorageKeys.terminalBackgroundImagePath)
        }
    }
    
    @Published var terminalBackgroundColor: String {
        didSet {
            UserDefaults.standard.set(terminalBackgroundColor, forKey: "terminal_background_color")
        }
    }
    
    @Published var terminalFontSize: Double {
        didSet {
            UserDefaults.standard.set(terminalFontSize, forKey: "terminal_font_size")
        }
    }
    
    @Published var terminalTheme: DesignSystem.TerminalTheme {
        didSet {
            UserDefaults.standard.set(terminalTheme.rawValue, forKey: "terminal_theme")
        }
    }
    
    @Published var userTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(userTheme.rawValue, forKey: "user_theme")
        }
    }
    
    init() {
        self.defaultDownloadPath = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.defaultDownloadPath) ?? ""
        self.geminiApiKey = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.geminiApiKey) ?? ""
        self.terminalBackgroundImagePath = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.terminalBackgroundImagePath) ?? ""
        self.terminalBackgroundColor = UserDefaults.standard.string(forKey: "terminal_background_color") ?? ""
        
        let savedFontSize = UserDefaults.standard.double(forKey: "terminal_font_size")
        self.terminalFontSize = savedFontSize == 0 ? 13.0 : savedFontSize
        
        let savedTerminalTheme = UserDefaults.standard.string(forKey: "terminal_theme") ?? DesignSystem.TerminalTheme.standard.rawValue
        self.terminalTheme = DesignSystem.TerminalTheme(rawValue: savedTerminalTheme) ?? .standard
        
        let savedTheme = UserDefaults.standard.string(forKey: "user_theme") ?? AppTheme.system.rawValue
        self.userTheme = AppTheme(rawValue: savedTheme) ?? .system
    }
    
    func selectDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Default Download Directory"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.defaultDownloadPath = url.path
            }
        }
    }
    
    func selectTerminalBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.title = "Select Terminal Background Image"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.terminalBackgroundImagePath = url.path
            }
        }
    }
    
    func clearTerminalBackgroundImage() {
        self.terminalBackgroundImagePath = ""
    }
}
