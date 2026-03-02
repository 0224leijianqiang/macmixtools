import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: ConnectionsStore
    @ObservedObject var tabManager: TabManager
    @ObservedObject var transferManager: TransferManager = .shared
    
    @Binding var selection: UUID?
    @Binding var editingConnectionID: IdentifiableUUID?
    
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // App Header & Global Actions
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.blue)
                        Text("SSHTools")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    
                    // Add Connection
                    SidebarAddMenu(store: store, onAdd: addConnection)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .background(DesignSystem.Colors.sidebarBackground)
            
            // Search Area
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search...".localized, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                SidebarActionButton(
                    icon: "square.and.arrow.up",
                    label: "Export Config".localized,
                    color: DesignSystem.Colors.blue,
                    action: exportConfig
                )
                SidebarActionButton(
                    icon: "square.and.arrow.down",
                    label: "Import Config".localized,
                    color: DesignSystem.Colors.green,
                    action: importConfig
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            Divider().background(DesignSystem.Colors.border)
            
            // Sidebar List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if searchText.isEmpty {
                        if !recentConnections.isEmpty {
                            sidebarSection(title: "Recent".localized) {
                                ForEach(recentConnections) { connection in
                                    ConnectionItemRow(connection: connection,
                                                     isSelected: selection == connection.id,
                                                     onSelect: { selection = connection.id },
                                                     editingConnectionID: $editingConnectionID,
                                                     tabManager: tabManager,
                                                     store: store,
                                                     onDelete: { store.deleteConnection(id: connection.id) })
                                }
                            }
                        }

                        if !favoriteConnections.isEmpty {
                            sidebarSection(title: "Favorites".localized) {
                                ForEach(favoriteConnections) { connection in
                                    ConnectionItemRow(connection: connection,
                                                     isSelected: selection == connection.id,
                                                     onSelect: { selection = connection.id },
                                                     editingConnectionID: $editingConnectionID,
                                                     tabManager: tabManager,
                                                     store: store,
                                                     onDelete: { store.deleteConnection(id: connection.id) })
                                }
                            }
                        }
                    }

                    sidebarSection(title: "SSH / SFTP".localized) {
                        ForEach(connections(of: [.ssh, .localTerminal])) { connection in
                            ConnectionItemRow(connection: connection,
                                             isSelected: selection == connection.id,
                                             onSelect: { selection = connection.id },
                                             editingConnectionID: $editingConnectionID,
                                             tabManager: tabManager,
                                             store: store,
                                             onDelete: { store.deleteConnection(id: connection.id) })
                        }
                    }

                    sidebarSection(title: "Redis".localized) {
                        ForEach(connections(of: [.redis])) { connection in
                            ConnectionItemRow(connection: connection,
                                             isSelected: selection == connection.id,
                                             onSelect: { selection = connection.id },
                                             editingConnectionID: $editingConnectionID,
                                             tabManager: tabManager,
                                             store: store,
                                             onDelete: { store.deleteConnection(id: connection.id) })
                        }
                    }

                    sidebarSection(title: "MySQL".localized) {
                        ForEach(connections(of: [.mysql, .clickhouse])) { connection in
                            ConnectionItemRow(connection: connection,
                                             isSelected: selection == connection.id,
                                             onSelect: { selection = connection.id },
                                             editingConnectionID: $editingConnectionID,
                                             tabManager: tabManager,
                                             store: store,
                                             onDelete: { store.deleteConnection(id: connection.id) })
                        }
                    }

                    sidebarSection(title: "HTTP".localized) {
                        SidebarToolRow(title: "HTTP Client".localized,
                                       icon: "network",
                                       color: DesignSystem.Colors.blue,
                                       id: AppConstants.FixedIDs.httpClient,
                                       isSelected: selection == AppConstants.FixedIDs.httpClient)
                            .onTapGesture { selection = AppConstants.FixedIDs.httpClient }
                    }

                    sidebarSection(title: "DevTools".localized) {
                        SidebarToolRow(title: "Dev Toolbox".localized,
                                       icon: "wrench.and.screwdriver.fill",
                                       color: DesignSystem.Colors.purple,
                                       id: AppConstants.FixedIDs.devToolbox,
                                       isSelected: selection == AppConstants.FixedIDs.devToolbox)
                            .onTapGesture { selection = AppConstants.FixedIDs.devToolbox }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(DesignSystem.Colors.sidebarBackground)
    }
    
    private var recentConnections: [SSHConnection] {
        let list = store.recentConnectionIds.compactMap { id in
            store.connections.first { $0.id == id }
        }
        return filterConnections(list)
    }

    private var favoriteConnections: [SSHConnection] {
        let list = store.favoriteConnectionIds.compactMap { id in
            store.connections.first { $0.id == id }
        }
        return filterConnections(list)
    }

    private func connections(of types: [ConnectionType]) -> [SSHConnection] {
        let list = store.connections.filter { types.contains($0.type) }
        return filterConnections(list)
    }

    private func filterConnections(_ list: [SSHConnection]) -> [SSHConnection] {
        guard !searchText.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.host.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            
            content()
        }
        .padding(.top, 8)
    }
    
    private func addConnection(type: ConnectionType) {
        var newConnection = SSHConnection(
            name: type == .ssh ? "New Server" :
                (type == .localTerminal ? "Local Terminal" :
                    (type == .redis ? "New Redis" :
                        (type == .clickhouse ? "New ClickHouse" : "New MySQL"))),
            host: "",
            username: ""
        )
        newConnection.type = type
        if type == .localTerminal {
            newConnection.port = ""
            newConnection.username = ""
        } else if type == .redis {
            newConnection.port = AppConstants.Ports.redis
            newConnection.username = "" 
        } else if type == .mysql {
            newConnection.port = AppConstants.Ports.mysql
        } else if type == .clickhouse {
            newConnection.port = AppConstants.Ports.clickhouse
        }
        store.connections.append(newConnection)
        selection = newConnection.id
        editingConnectionID = IdentifiableUUID(id: newConnection.id)
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sshtools-config.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ConfigIO.exportToURL(url, store: store)
                ToastManager.shared.show(message: "Config Exported".localized, type: .success)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let snapshot = try ConfigIO.importFromURL(url)
                ConfigIO.applySnapshot(snapshot, to: store)
                ToastManager.shared.show(message: "Config Imported".localized, type: .success)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }
}

// Sub-component for sidebar buttons
struct SidebarActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label.localized)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarToolRow: View {
    let title: String
    let icon: String
    let color: Color
    let id: UUID
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isSelected ? color : .secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}

private struct ConnectionItemRow: View {
    let connection: SSHConnection
    let isSelected: Bool
    let onSelect: () -> Void
    @Binding var editingConnectionID: IdentifiableUUID?
    @ObservedObject var tabManager: TabManager
    @ObservedObject var store: ConnectionsStore
    let onDelete: () -> Void
    @ObservedObject private var localPathStore = LocalTerminalPathStore.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.type.icon)
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if let subtitle = subtitleText, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: { store.toggleFavorite(id: connection.id) }) {
                Image(systemName: store.isFavorite(connection.id) ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(store.isFavorite(connection.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button(action: { store.toggleFavorite(id: connection.id) }) {
                Label(store.isFavorite(connection.id) ? "Unfavorite" : "Favorite", systemImage: "star")
            }
            Button(action: { editingConnectionID = IdentifiableUUID(id: connection.id) }) {
                Label("Settings", systemImage: "gear")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var subtitleText: String? {
        if connection.type == .localTerminal {
            return localPathStore.path(for: connection.id) ?? connection.host
        }
        return connection.host
    }
}

private struct SidebarAddMenu: View {
    @ObservedObject var store: ConnectionsStore
    let onAdd: (ConnectionType) -> Void
    
    var body: some View {
        Menu {
            Button(action: { store.addGroup(name: "New Group") }) {
                Label("Add Group", systemImage: "folder.badge.plus")
            }
            Divider()
            Button(action: { onAdd(.ssh) }) {
                Label("SSH Terminal".localized, systemImage: "terminal.fill")
            }
            Button(action: { onAdd(.localTerminal) }) {
                Label("Local Terminal".localized, systemImage: "terminal")
            }
            Button(action: { onAdd(.redis) }) {
                Label("Redis".localized, systemImage: "cylinder.split.1x2.fill")
            }
            Button(action: { onAdd(.mysql) }) {
                Label("MySQL Database".localized, systemImage: "server.rack")
            }
            Button(action: { onAdd(.clickhouse) }) {
                Label("ClickHouse Database".localized, systemImage: "server.rack")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.blue)
        }
        .buttonStyle(.plain)
    }
}
