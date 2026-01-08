import Foundation
import SwiftUI

enum TabContent: Identifiable, Equatable {
    case home
    case terminal(SSHConnection)
    case sftp(SSHConnection)
    case redis(SSHConnection)
    case mysql(SSHConnection)
    case clickhouse(SSHConnection)
    case httpClient
    case devToolbox
    
    var id: String {
        switch self {
        case .home: return "home"
        case .terminal(let conn): return "terminal_\(conn.id)"
        case .sftp(let conn): return "sftp_\(conn.id)"
        case .redis(let conn): return "redis_\(conn.id)"
        case .mysql(let conn): return "mysql_\(conn.id)"
        case .clickhouse(let conn): return "clickhouse_\(conn.id)"
        case .httpClient: return "http_client"
        case .devToolbox: return "dev_toolbox"
        }
    }
    
    var connectionID: UUID? {
        switch self {
        case .home, .httpClient, .devToolbox: return nil
        case .terminal(let conn): return conn.id
        case .sftp(let conn): return conn.id
        case .redis(let conn): return conn.id
        case .mysql(let conn): return conn.id
        case .clickhouse(let conn): return conn.id
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Home".localized
        case .terminal(let conn): return conn.name
        case .sftp(let conn): return "SFTP".localized + ": \(conn.name)"
        case .redis(let conn): return "Redis".localized + ": \(conn.name)"
        case .mysql(let conn): return "MySQL: \(conn.name)"
        case .clickhouse(let conn): return "ClickHouse: \(conn.name)"
        case .httpClient: return "HTTP Client".localized
        case .devToolbox: return "Dev Toolbox".localized
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .terminal: return "terminal"
        case .sftp(_): return "folder"
        case .redis: return "cylinder.split.1x2"
        case .mysql: return "server.rack"
        case .clickhouse: return "server.rack"
        case .httpClient: return "network"
        case .devToolbox: return "wrench.and.screwdriver.fill"
        }
    }
    
    static func == (lhs: TabContent, rhs: TabContent) -> Bool {
        return lhs.id == rhs.id
    }
}

struct TabItem: Identifiable, Equatable {
    let id: UUID
    let content: TabContent
    
    init(id: UUID = UUID(), content: TabContent) {
        self.id = id
        self.content = content
    }
    
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        return lhs.id == rhs.id
    }
}

enum TerminalAction {
    case toggleAI
    case diagnose
    case toggleMonitor
}

class TabManager: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedTabID: UUID?
    
    // For signaling terminal tabs from sidebar
    @Published var lastTerminalAction: (id: UUID, action: TerminalAction)?
    
    init() {
        // Always start with Home tab
        let homeTab = TabItem(content: .home)
        tabs.append(homeTab)
        selectedTabID = homeTab.id
    }
    
    func triggerActiveTerminalAction(_ action: TerminalAction) {
        guard let selectedID = selectedTabID else { return }
        lastTerminalAction = (selectedID, action)
    }
    
    func openTab(content: TabContent) {
        // Check if tab with same content exists
        if let existingIndex = tabs.firstIndex(where: { $0.content == content }) {
            selectedTabID = tabs[existingIndex].id
            return
        }
        
        let newTab = TabItem(content: content)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }
    
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        let tab = tabs[index]
        
        // Prevent closing Home tab
        if case .home = tab.content {
            return
        }
        
        // Resource Cleanup
        performCleanup(for: tab.content, excludingTabID: id)
        
        let removingID = tab.id
        tabs.remove(at: index)
        
        // If we closed the selected tab, select another one
        if selectedTabID == removingID {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
    }
    
    private func performCleanup(for content: TabContent, excludingTabID: UUID) {
        switch content {
        case .redis(let conn):
            // Check if any other tabs are using this connection
            let otherRedisTabs = tabs.filter { 
                if case .redis(let otherConn) = $0.content {
                    return otherConn.id == conn.id && $0.id != excludingTabID
                }
                return false
            }
            
            // If no other tabs are using this connection, we can safely remove it
            if otherRedisTabs.isEmpty {
                RedisViewModelManager.shared.removeViewModel(for: conn.id)
            }
            
        case .terminal(_):
            // Resources are primarily handled by deinit of TerminalViewModel
            break
            
        case .sftp(_):
            // Resources are primarily handled by deinit of SyncedSFTPViewModel or shared with Terminal
            break
            
        case .mysql(_):
            // Future optimization for MySQL
            break

        case .clickhouse(_):
            // Future optimization for ClickHouse
            break
            
        case .home, .httpClient, .devToolbox:
            // No specific cleanup needed for static tools
            break
        }
    }
    
    func updateConnectionInTabs(_ updatedConnection: SSHConnection) {
        // Update any tabs that hold this connection
        for (index, tab) in tabs.enumerated() {
            if tab.content.connectionID == updatedConnection.id {
                // Recreate tab content with updated connection struct
                var newContent: TabContent
                switch tab.content {
                case .home, .httpClient, .devToolbox:
                    continue // Should not happen given connectionID check
                case .terminal:
                    newContent = .terminal(updatedConnection)
                case .sftp:
                    newContent = .sftp(updatedConnection)
                case .redis:
                    newContent = .redis(updatedConnection)
                case .mysql:
                    newContent = .mysql(updatedConnection)
                case .clickhouse:
                    newContent = .clickhouse(updatedConnection)
                }
                
                let updatedTab = TabItem(id: tab.id, content: newContent)
                tabs[index] = updatedTab
            }
        }
    }
}
