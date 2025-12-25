import SwiftUI
import SwiftTerm
import AppKit
import Combine

// Alias to avoid conflict with our SwiftUI TerminalView
typealias MacTerminalView = SwiftTerm.TerminalView

/// A customized TerminalView that handles its own context menu and selection
class AppTerminalView: MacTerminalView {
    override func updateLayer() {
        super.updateLayer()
        // Ensure no background color is set on the layer to allow transparency
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // Prevent clearing selection on new data (crucial for tail -f)
    override func linefeed(source: Terminal) {
        // Essential: call super to ensure cursor moves correctly and scrolling works
        super.linefeed(source: source)
    }
    
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        if action == #selector(copy(_:)) {
            return self.selectionActive
        }
        if action == #selector(paste(_:)) {
            return NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        }
        
        // Enable background setting actions
        if action == #selector(selectBackgroundImage(_:)) ||
           action == #selector(selectBackgroundColor(_:)) ||
           action == #selector(resetBackground(_:)) {
            return true
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    @objc override func copy(_ sender: Any) {
        if let selectedText = self.getSelection(), !selectedText.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
            ToastManager.shared.show(message: "Copied to clipboard", type: .success)
        } else {
            super.copy(sender)
        }
    }
    
    @objc override func paste(_ sender: Any) {
        super.paste(sender)
    }
    
    @objc func selectBackgroundImage(_ sender: Any) {
        SettingsManager.shared.selectTerminalBackgroundImage()
    }
    
    @objc func selectBackgroundColor(_ sender: Any) {
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorDidChange(_:)))
        colorPanel.makeKeyAndOrderFront(self)
    }
    
    @objc func colorDidChange(_ sender: NSColorPanel) {
        let color = sender.color
        if let hex = color.toHexString() {
            SettingsManager.shared.terminalBackgroundColor = hex
            // When setting color, usually clear the image
            SettingsManager.shared.terminalBackgroundImagePath = ""
        }
    }
    
    @objc func resetBackground(_ sender: Any) {
        SettingsManager.shared.clearTerminalBackgroundImage()
        SettingsManager.shared.terminalBackgroundColor = ""
    }
}

/// A stable container to isolate SwiftTerm from SwiftUI's layout engine
class TerminalContainer: NSView {
    let terminalView: AppTerminalView
    private let backgroundImageView = NSImageView()
    private let overlayView = NSView()
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init(terminalView: AppTerminalView) {
        self.terminalView = terminalView
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        
        setupViews()
        setupEventMonitor()
        setupSettingsObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
        
        // 1. Background Image
        backgroundImageView.imageScaling = .scaleProportionallyUpOrDown
        backgroundImageView.frame = self.bounds
        backgroundImageView.autoresizingMask = [.height, .width]
        self.addSubview(backgroundImageView)
        
        // 2. Dark Overlay to ensure text readability
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        overlayView.frame = self.bounds
        overlayView.autoresizingMask = [.height, .width]
        self.addSubview(overlayView)
        
        // 3. Terminal View
        terminalView.frame = self.bounds
        terminalView.autoresizingMask = [.height, .width]
        
        self.addSubview(terminalView)
    }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self.terminalView)
        super.mouseDown(with: event)
    }
    
    private func setupEventMonitor() {
        // Intercept Command+C before it reaches terminalView and clears selection
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.firstResponder == self.terminalView else { return event }
            
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
                self.terminalView.copy(self)
                return nil // Swallow the event
            }
            return event
        }
    }
    
    private func setupSettingsObservation() {
        Publishers.CombineLatest3(SettingsManager.shared.$terminalBackgroundImagePath,
                                SettingsManager.shared.$terminalBackgroundColor,
                                SettingsManager.shared.$terminalTheme)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (imagePath, hexColor, theme) in
                self?.updateBackground(path: imagePath, hex: hexColor, theme: theme)
            }
            .store(in: &cancellables)
    }
    
    private func updateBackground(path: String, hex: String, theme: DesignSystem.TerminalTheme) {
        // Handle Image
        if !path.isEmpty, let image = NSImage(contentsOfFile: path) {
            backgroundImageView.image = image
            overlayView.isHidden = false
            self.layer?.backgroundColor = NSColor.black.cgColor
            terminalView.nativeForegroundColor = .white
            return
        }
        
        // Handle custom Color hex if provided
        backgroundImageView.image = nil
        overlayView.isHidden = true
        
        if !hex.isEmpty, let color = NSColor(hex: hex) {
            self.layer?.backgroundColor = color.cgColor
            terminalView.nativeForegroundColor = .white
        } else {
            // Apply Theme
            let themeColors = theme.themeColors
            if let bgColor = NSColor(hex: themeColors.bg) {
                self.layer?.backgroundColor = bgColor.cgColor
            }
            if let fgColor = NSColor(hex: themeColors.fg) {
                terminalView.nativeForegroundColor = fgColor
            }
            if let cursorColor = NSColor(hex: themeColors.cursor) {
                terminalView.caretColor = cursorColor
            }
        }
    }
    
    @objc func setTheme(_ sender: NSMenuItem) {
        if let theme = sender.representedObject as? DesignSystem.TerminalTheme {
            SettingsManager.shared.terminalTheme = theme
            // Clear custom background when theme is selected
            SettingsManager.shared.terminalBackgroundImagePath = ""
            SettingsManager.shared.terminalBackgroundColor = ""
        }
    }
    
    override func layout() {
        super.layout()
        backgroundImageView.frame = self.bounds
        overlayView.frame = self.bounds
        terminalView.frame = self.bounds
    }
}

struct SwiftTermView: NSViewRepresentable {
    @ObservedObject var runner: SSHRunner
    
    func makeNSView(context: Context) -> TerminalContainer {
        let terminalView = AppTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        
        // 1. Appearance
        terminalView.appearance = NSAppearance(named: .darkAqua)
        
        // 2. Background & Layer
        terminalView.wantsLayer = true
        if let bgColor = NSColor(hex: SettingsManager.shared.terminalTheme.themeColors.bg) {
            terminalView.layer?.backgroundColor = bgColor.cgColor
        }
        terminalView.layer?.isOpaque = true
        
        // 3. Font
        let fontSize = SettingsManager.shared.terminalFontSize
        let baseFont = NSFont(name: "Menlo", size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        terminalView.font = baseFont
        
        // 4. Critical: nativeBackgroundColor must be clear for CJK shadow fix
        terminalView.nativeBackgroundColor = .clear
        terminalView.nativeForegroundColor = .white
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 5. Cursor & Options
        DispatchQueue.main.async {
            var options = terminalView.terminal.options
            options.cursorStyle = .steadyBar
            // Explicitly disable any potential guide lines
            // SwiftTerm doesn't have a direct 'columnGuide' bool in some versions, 
            // but we can ensure standard behavior.
            terminalView.terminal.options = options
        }
        
        terminalView.terminalDelegate = context.coordinator
        
        // Ensure no extra padding inside SwiftTerm
        // Some versions use terminal.margin
        
        // Context Menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy".localized, action: #selector(AppTerminalView.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste".localized, action: #selector(AppTerminalView.paste(_:)), keyEquivalent: "v")
        
        menu.addItem(NSMenuItem.separator())
        
        let bgMenu = NSMenuItem(title: "Appearance".localized, action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        bgMenu.submenu = subMenu
        
        subMenu.addItem(withTitle: "Set Background Image...".localized, action: #selector(AppTerminalView.selectBackgroundImage(_:)), keyEquivalent: "")
        subMenu.addItem(withTitle: "Set Background Color...".localized, action: #selector(AppTerminalView.selectBackgroundColor(_:)), keyEquivalent: "")
        
        subMenu.addItem(NSMenuItem.separator())
        
        let themeMenu = NSMenu()
        let themeItem = NSMenuItem(title: "Themes".localized, action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        
        // Create container first
        let container = TerminalContainer(terminalView: terminalView)
        
        for theme in DesignSystem.TerminalTheme.allCases {
            let item = NSMenuItem(title: theme.rawValue.localized, action: #selector(TerminalContainer.setTheme(_:)), keyEquivalent: "")
            item.target = container
            item.representedObject = theme
            if SettingsManager.shared.terminalTheme == theme {
                item.state = .on
            }
            themeMenu.addItem(item)
        }
        subMenu.addItem(themeItem)
        
        subMenu.addItem(NSMenuItem.separator())
        subMenu.addItem(withTitle: "Reset Appearance".localized, action: #selector(AppTerminalView.resetBackground(_:)), keyEquivalent: "")
        
        menu.addItem(bgMenu)
        
        terminalView.menu = menu
        
        DispatchQueue.main.async {
            runner.terminalView = terminalView
        }
        
        return container
    }
    
    func updateNSView(_ nsView: TerminalContainer, context: Context) {
        let fontSize = SettingsManager.shared.terminalFontSize
        if nsView.terminalView.font.pointSize != CGFloat(fontSize) {
            let newFont = NSFont(name: "Menlo", size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
            nsView.terminalView.font = newFont
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(runner: runner)
    }
    
    class Coordinator: NSObject, TerminalViewDelegate {
        var runner: SSHRunner
        init(runner: SSHRunner) { self.runner = runner }
        func sizeChanged(source: MacTerminalView, newCols: Int, newRows: Int) { runner.resize(cols: newCols, rows: newRows) }
        func setTerminalTitle(source: MacTerminalView, title: String) { }
        func send(source: MacTerminalView, data: ArraySlice<UInt8>) { runner.send(data: Data(data)) }
        func scrolled(source: MacTerminalView, position: Double) { }
        func hostCurrentDirectoryUpdate(source: MacTerminalView, directory: String?) {
            guard var dir = directory else { return }
            Logger.log("Terminal: Received directory update: \(dir)", level: .debug)
            
            if dir.hasPrefix("file://") {
                // Format: file://hostname/path/to/dir
                let components = dir.components(separatedBy: "://")
                if components.count > 1 {
                    let pathWithHost = components[1]
                    if let firstSlashIndex = pathWithHost.firstIndex(of: "/") {
                        dir = String(pathWithHost[firstSlashIndex...])
                    } else {
                        // If no slash after host, it might be just the host or malformed
                        dir = "/"
                    }
                }
            }
            
            // Handle URL encoding if present
            if let decoded = dir.removingPercentEncoding {
                dir = decoded
            }
            
            let cleanDir = dir
            Logger.log("Terminal: Cleaned directory path: \(cleanDir)", level: .info)
            DispatchQueue.main.async {
                if self.runner.currentPath != cleanDir {
                    self.runner.currentPath = cleanDir
                }
            }
        }
        func clipboardCopy(source: MacTerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(str, forType: .string)
                ToastManager.shared.show(message: "Copied to clipboard", type: .success)
            }
        }
        
        func rangeChanged(source: MacTerminalView, startY: Int, endY: Int) { }
    }
}

extension NSColor {
    convenience init?(hex: String) {
                var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if hexSanitized.hasPrefix("#") {
                    hexSanitized.remove(at: hexSanitized.startIndex)
                }
                
                var rgb: UInt64 = 0
                guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
                
                let r, g, b, a: CGFloat
                if hexSanitized.count == 6 {
                    r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
                    g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
                    b = CGFloat(rgb & 0x0000FF) / 255.0
                    a = 1.0
                } else if hexSanitized.count == 8 {
                    r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
                    g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
                    b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
                    a = CGFloat(rgb & 0x000000FF) / 255.0
                } else {
                    return nil
                }
                
                self.init(red: r, green: g, blue: b, alpha: a)
            }
            
            func toHexString() -> String? {
                guard let rgbColor = self.usingColorSpace(.deviceRGB) else { return nil }
                let r = Int(round(rgbColor.redComponent * 255))
                let g = Int(round(rgbColor.greenComponent * 255))
                let b = Int(round(rgbColor.blueComponent * 255))
                return String(format: "#%02X%02X%02X", r, g, b)
            }
        }
        