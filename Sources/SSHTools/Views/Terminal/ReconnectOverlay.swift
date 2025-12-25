import SwiftUI

struct ReconnectOverlay: View {
    let isConnected: Bool
    let isConnecting: Bool
    let error: String?
    let onReconnect: () -> Void
    
    var body: some View {
        if !isConnected && !isConnecting {
            ZStack {
                DesignSystem.Colors.background.opacity(0.9)
                
                VStack(spacing: 16) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text(error != nil ? "Connection Error".localized : "Disconnected".localized)
                        .font(.headline)
                    
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button(action: onReconnect) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect Now".localized)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(DesignSystem.Colors.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .transition(.opacity)
        }
    }
}
