import SwiftUI

struct ConnectionRowView: View {
    let connection: SSHConnection
    @Binding var editingConnectionID: IdentifiableUUID?
    @ObservedObject var tabManager: TabManager
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(connectionTypeColor(for: connection.type).opacity(0.1))
                    .frame(width: 22, height: 22)
                
                Image(systemName: connection.type.icon)
                    .foregroundColor(connectionTypeColor(for: connection.type))
                    .font(.system(size: 11))
            }
            .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !connection.host.isEmpty {
                    Text(connection.host)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                editingConnectionID = IdentifiableUUID(id: connection.id)
            }) {
                Text("Configure".localized)
            }
            
            if connection.type == .ssh {
                Button(action: {
                    tabManager.openTab(content: .sftp(connection))
                }) {
                    Text("Open SFTP".localized)
                }
            }
            
            Divider()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete".localized, systemImage: "trash")
            }
        }
    }
    
    private func connectionTypeColor(for type: ConnectionType) -> Color {
        switch type {
        case .ssh: return DesignSystem.Colors.green
        case .redis: return DesignSystem.Colors.orange
        case .mysql: return DesignSystem.Colors.blue
        }
    }
}
