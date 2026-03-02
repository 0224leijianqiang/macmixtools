import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConnectionsStore()
    @StateObject private var tabManager = TabManager()
    
    @State private var sidebarSelection: UUID?
    @State private var editingConnectionID: IdentifiableUUID?
    @State private var sidebarWidth: CGFloat = 220
    @State private var isDraggingSidebar = false
    @State private var dragStartWidth: CGFloat = 220
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        let minSidebarWidth: CGFloat = 150
        let maxSidebarWidth: CGFloat = 500
        let splitterWidth: CGFloat = DesignSystem.Layout.sidebarSplitterWidth

        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
            // 1. Sidebar (Solid background, zero margin)
            SidebarView(store: store, 
                        tabManager: tabManager, 
                        selection: $sidebarSelection, 
                        editingConnectionID: $editingConnectionID)
                .frame(width: sidebarWidth, alignment: .leading)
                .transaction { $0.animation = nil }
            
            // 2. Draggable Divider
            VerticalDraggableSplitter(isDragging: $isDraggingSidebar)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingSidebar {
                                isDraggingSidebar = true
                                dragStartWidth = sidebarWidth
                            }
                            let proposed = value.translation.width
                            let clamped = min(max(dragStartWidth + proposed, minSidebarWidth), maxSidebarWidth)
                            dragOffset = clamped - dragStartWidth
                        }
                        .onEnded { _ in
                            isDraggingSidebar = false
                            let finalWidth = min(max(dragStartWidth + dragOffset, minSidebarWidth), maxSidebarWidth)
                            withTransaction(Transaction(animation: nil)) {
                                sidebarWidth = finalWidth
                            }
                            dragOffset = 0
                        }
                )
            
            // 3. Detail Area
            TabsView(tabManager: tabManager, connections: $store.connections)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { $0.animation = nil }
            }
            
            if isDraggingSidebar {
                Rectangle()
                    .fill(DesignSystem.Colors.blue.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: sidebarWidth + dragOffset + (splitterWidth / 2 - 1))
                    .allowsHitTesting(false)
            }
        }
        .background(DesignSystem.Colors.background)
        .onChange(of: sidebarSelection) { oldValue, newValue in
            handleSelectionChange(newValue)
        }
        .sheet(item: $editingConnectionID) { identifiableUUID in
            ConnectionSettingsPresenter(store: store, 
                                      id: identifiableUUID.id, 
                                      onClose: { editingConnectionID = nil },
                                      onConnect: { id in
                editingConnectionID = nil
                if let connection = store.connections.first(where: { $0.id == id }) {
                    openConnection(connection)
                }
            })
        }
        .overlay {
            ToastContainerView()
        }
    }
    
    private func handleSelectionChange(_ id: UUID?) {
        guard let id = id else { return }
        
        if id == AppConstants.FixedIDs.httpClient {
            tabManager.openTab(content: .httpClient)
            return
        }
        
        if id == AppConstants.FixedIDs.devToolbox {
            tabManager.openTab(content: .devToolbox)
            return
        }
        
        guard let connection = store.connections.first(where: { $0.id == id }) else { return }

        store.recordRecent(id: connection.id)
        
        if isConnectionValid(connection) {
            openConnection(connection)
        } else {
            editingConnectionID = IdentifiableUUID(id: id)
        }
    }
    
    private func openConnection(_ connection: SSHConnection) {
        switch connection.type {
        case .redis:
            tabManager.openTab(content: .redis(connection))
        case .mysql:
            tabManager.openTab(content: .mysql(connection))
        case .clickhouse:
            tabManager.openTab(content: .clickhouse(connection))
        case .ssh:
            tabManager.openTab(content: .terminal(connection))
        case .localTerminal:
            tabManager.openTab(content: .localTerminal(connection))
        }
    }
    
    private func isConnectionValid(_ connection: SSHConnection) -> Bool {
        if connection.type == .localTerminal { return true }
        if connection.host.isEmpty { return false }
        if (connection.type == .ssh || connection.type == .mysql) && connection.username.isEmpty { return false }
        return true
    }
}

struct ConnectionSettingsPresenter: View {
    @ObservedObject var store: ConnectionsStore
    let id: UUID
    let onClose: () -> Void
    let onConnect: (UUID) -> Void
    
    var body: some View {
        if let index = store.connections.firstIndex(where: { $0.id == id }) {
            ConnectionSettingsSheet(connection: $store.connections[index],
                                    onClose: onClose,
                                    onConnect: { onConnect(id) })
        } else {
            Text("Error".localized)
        }
    }
}
