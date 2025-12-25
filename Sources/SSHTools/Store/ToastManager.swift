import SwiftUI
import Combine

enum ToastType {
    case success
    case error
    case info
    case warning
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let type: ToastType
    var duration: Double = 3.5
}

class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: Toast?
    private var timer: AnyCancellable?
    
    private init() {}
    
    func show(message: String, type: ToastType = .info) {
        DispatchQueue.main.async {
            // If there is already a toast, clear it first to trigger animation
            self.currentToast = nil
            
            withAnimation(.spring()) {
                self.currentToast = Toast(message: message, type: type)
            }
            
            // Auto hide
            self.timer?.cancel()
            self.timer = Just(())
                .delay(for: .seconds(self.currentToast?.duration ?? 3.0), scheduler: RunLoop.main)
                .sink { [weak self] in
                    self?.hide()
                }
        }
    }
    
    func hide() {
        withAnimation(.easeOut) {
            self.currentToast = nil
        }
    }
}

struct ToastContainerView: View {
    @ObservedObject var manager = ToastManager.shared
    
    var body: some View {
        ZStack {
            if let toast = manager.currentToast {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: toast.type.icon)
                            .foregroundColor(toast.type.color)
                            .font(.system(size: 16, weight: .bold))
                        
                        Text(toast.message)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                        
                        Button(action: { manager.hide() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(toast.type.color.opacity(0.15), lineWidth: 0.5)
                    )
                    .padding(.top, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .zIndex(9999)
                .allowsHitTesting(false) // Allow clicks to pass through except for the button if needed, but here we want non-blocking
            }
        }
    }
}
