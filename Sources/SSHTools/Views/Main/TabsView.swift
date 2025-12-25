import SwiftUI

struct TabsView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var connections: [SSHConnection] // We need write access to update connections from Settings
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabManager.tabs) { tab in
                        TabButton(tab: tab, 
                                  isSelected: tabManager.selectedTabID == tab.id,
                                  onSelect: { tabManager.selectedTabID = tab.id },
                                  onClose: { tabManager.closeTab(id: tab.id) })
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 44)
            .background(DesignSystem.Colors.background)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(DesignSystem.Colors.border),
                alignment: .bottom
            )
            
            // Content Area
            ZStack {
                if tabManager.tabs.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                        Text("No Open Tabs".localized)
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                } else if let selectedID = tabManager.selectedTabID,
                          let selectedTab = tabManager.tabs.first(where: { $0.id == selectedID }) {
                    TabContentView(tab: selectedTab, connections: $connections, tabManager: tabManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct TabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.content.icon)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? DesignSystem.Colors.blue : DesignSystem.Colors.textSecondary)
            
            Text(tab.content.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? DesignSystem.Colors.text : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
            
            if tab.content != .home {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(4)
                        .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? DesignSystem.Colors.surface : (isHovering ? Color.white.opacity(0.05) : Color.clear))
        )
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}

struct TabContentView: View {
    let tab: TabItem
    @Binding var connections: [SSHConnection]
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        switch tab.content {
        case .home:
            HomeView()
        case .terminal(let connection):
            TerminalView(connection: connection)
        case .sftp(let connection):
            StandaloneSFTPView(connection: connection)
        case .redis(let connection):
            // RedisView updates connection settings internally, but usually we just use it
            RedisView(connection: connection) { updated in
                if let index = connections.firstIndex(where: { $0.id == updated.id }) {
                    connections[index] = updated
                }
            }
        case .mysql(let connection):
            MySQLView(connection: connection)
        case .httpClient:
            HTTPToolView()
        case .devToolbox:
            DevToolboxView()
        }
    }
}
