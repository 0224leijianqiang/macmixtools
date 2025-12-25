import SwiftUI

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
            
            Divider().background(DesignSystem.Colors.border)
            
            // Sidebar List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if searchText.isEmpty {
                        sidebarSection(title: "Tools".localized) {
                            SidebarToolRow(title: "HTTP Client".localized, 
                                           icon: "network", 
                                           color: DesignSystem.Colors.blue, 
                                           id: AppConstants.FixedIDs.httpClient,
                                           isSelected: selection == AppConstants.FixedIDs.httpClient)
                                .onTapGesture { selection = AppConstants.FixedIDs.httpClient }
                            
                            SidebarToolRow(title: "Dev Toolbox".localized, 
                                           icon: "wrench.and.screwdriver.fill", 
                                           color: DesignSystem.Colors.purple, 
                                           id: AppConstants.FixedIDs.devToolbox,
                                           isSelected: selection == AppConstants.FixedIDs.devToolbox)
                                .onTapGesture { selection = AppConstants.FixedIDs.devToolbox }
                        }
                    }
                    
                    // Grouped Connections
                    ForEach(store.groups) { group in
                        let filteredConnections = store.connections.filter { 
                            group.connectionIds.contains($0.id) && 
                            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.host.localizedCaseInsensitiveContains(searchText))
                        }
                        
                        if !filteredConnections.isEmpty {
                            sidebarSection(title: group.name) {
                                ForEach(filteredConnections) { connection in
                                    ConnectionItemRow(connection: connection, 
                                                     isSelected: selection == connection.id,
                                                     onSelect: { selection = connection.id },
                                                     editingConnectionID: $editingConnectionID,
                                                     tabManager: tabManager,
                                                     onDelete: { store.deleteConnection(id: connection.id) })
                                }
                            }
                        }
                    }
                    
                    // Orphan Connections
                    let orphanConnections = store.connections.filter { conn in
                        !store.groups.contains(where: { $0.connectionIds.contains(conn.id) }) &&
                        (searchText.isEmpty || conn.name.localizedCaseInsensitiveContains(searchText) || conn.host.localizedCaseInsensitiveContains(searchText))
                    }
                    
                    if !orphanConnections.isEmpty {
                        sidebarSection(title: "Servers".localized) {
                            ForEach(orphanConnections) { connection in
                                ConnectionItemRow(connection: connection, 
                                                 isSelected: selection == connection.id,
                                                 onSelect: { selection = connection.id },
                                                 editingConnectionID: $editingConnectionID,
                                                 tabManager: tabManager,
                                                 onDelete: { store.deleteConnection(id: connection.id) })
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(DesignSystem.Colors.sidebarBackground)
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
        var newConnection = SSHConnection(name: type == .ssh ? "New Server" : (type == .redis ? "New Redis" : "New MySQL"), host: "", username: "")
        newConnection.type = type
        if type == .redis {
            newConnection.port = AppConstants.Ports.redis
            newConnection.username = "" 
        } else if type == .mysql {
            newConnection.port = AppConstants.Ports.mysql
        }
        store.connections.append(newConnection)
        selection = newConnection.id
        editingConnectionID = IdentifiableUUID(id: newConnection.id)
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
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.type.icon)
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(connection.host)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button(action: { editingConnectionID = IdentifiableUUID(id: connection.id) }) {
                Label("Settings", systemImage: "gear")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
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
            Button(action: { onAdd(.redis) }) {
                Label("Redis".localized, systemImage: "cylinder.split.1x2.fill")
            }
            Button(action: { onAdd(.mysql) }) {
                Label("MySQL Database".localized, systemImage: "server.rack")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.blue)
        }
        .buttonStyle(.plain)
    }
}