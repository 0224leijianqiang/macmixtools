import SwiftUI
import AppKit

/// 自定义窗口左上角红黄绿按钮，替代系统默认交通灯
struct WindowTrafficLights: View {
    private struct TrafficLightButton: View {
        enum Kind {
            case close, minimize, zoom
        }
        
        let kind: Kind
        
        var body: some View {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
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
        
        private var color: Color {
            switch kind {
            case .close: return Color(red: 1.0, green: 0.27, blue: 0.23)
            case .minimize: return Color(red: 1.0, green: 0.80, blue: 0.21)
            case .zoom: return Color(red: 0.19, green: 0.82, blue: 0.32)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            TrafficLightButton(kind: .close)
            TrafficLightButton(kind: .minimize)
            TrafficLightButton(kind: .zoom)
        }
        .frame(height: 40, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .allowsHitTesting(true)
    }
}

