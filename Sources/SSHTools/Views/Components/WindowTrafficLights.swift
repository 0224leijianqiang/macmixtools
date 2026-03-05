import SwiftUI
import AppKit

/// 监听应用激活/失焦，用于模拟系统红绿灯的活跃与非活跃状态
final class WindowFocusObserver: ObservableObject {
    static let shared = WindowFocusObserver()
    
    @Published var isActive: Bool = NSApp.isActive
    
    private var observers: [NSObjectProtocol] = []
    
    private init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.isActive = true
            }
        )
        observers.append(
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.isActive = false
            }
        )
    }
    
    deinit {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
    }
}

/// 自定义窗口左上角红黄绿按钮，替代系统默认交通灯
struct WindowTrafficLights: View {
    @ObservedObject private var focus = WindowFocusObserver.shared
    @State private var isHoveringGroup = false
    
    private struct TrafficLightButton: View {
        enum Kind {
            case close, minimize, zoom
        }
        
        let kind: Kind
        let isActive: Bool
        let isGroupHovering: Bool
        
        var body: some View {
            ZStack {
                Circle()
                    .fill(baseColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(isActive ? 0.08 : 0.15), lineWidth: 0.5)
                    )
                
                if isActive && isGroupHovering {
                    Image(systemName: hoverSymbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.7))
                }
            }
            .opacity(isActive ? 1.0 : 0.55)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                switch kind {
                case .close:
                    window.performClose(nil)
                case .minimize:
                    window.miniaturize(nil)
                case .zoom:
                    window.performZoom(nil)
                }
            }
        }
        
        private var baseColor: Color {
            switch kind {
            case .close: return Color(red: 1.0, green: 0.27, blue: 0.23)
            case .minimize: return Color(red: 1.0, green: 0.80, blue: 0.21)
            case .zoom: return Color(red: 0.19, green: 0.82, blue: 0.32)
            }
        }
        
        private var hoverSymbol: String {
            switch kind {
            case .close: return "xmark"
            case .minimize: return "minus"
            // 近似原生的对角缩放图标
            case .zoom: return "arrow.up.left.and.arrow.down.right"
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
            Color.clear.frame(width: 1, height: 40)
            HStack(spacing: 6) {
                TrafficLightButton(kind: .close, isActive: focus.isActive, isGroupHovering: isHoveringGroup)
                TrafficLightButton(kind: .minimize, isActive: focus.isActive, isGroupHovering: isHoveringGroup)
                TrafficLightButton(kind: .zoom, isActive: focus.isActive, isGroupHovering: isHoveringGroup)
            }
            .padding(.leading, 10)
            .onHover { inside in
                isHoveringGroup = inside
            }
        }
        .frame(height: 40)
        .allowsHitTesting(true)
    }
}

