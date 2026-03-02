import SwiftUI
import Combine

/// 连接存储管理器
/// 负责加载、保存和管理 SSH/Redis 连接配置
final class ConnectionsStore: ObservableObject {
    @Published var connections: [SSHConnection] = [] {
        didSet { scheduleSave() }
    }
    @Published var groups: [ConnectionGroup] = [] {
        didSet { scheduleSave() }
    }
    @Published var favoriteConnectionIds: [UUID] = [] {
        didSet { scheduleSave() }
    }
    @Published var recentConnectionIds: [UUID] = [] {
        didSet { scheduleSave() }
    }
    
    private let connectionsKey = AppConstants.StorageKeys.savedConnections
    private let groupsKey = "saved_groups"
    private let favoritesKey = "favorite_connections"
    private let recentKey = "recent_connections"
    private let recentMaxCount = 12
    private var isInitialLoading = false
    
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let saveQueue = DispatchQueue(label: "com.sshtools.storage", qos: .background)

    init() {
        setupSaveSubscription()
        loadAll()
    }

    private func setupSaveSubscription() {
        saveSubject
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.performSave()
            }
            .store(in: &cancellables)
    }

    private func scheduleSave() {
        guard !isInitialLoading else { return }
        saveSubject.send()
    }

    private func loadAll() {
        isInitialLoading = true
        defer { isInitialLoading = false }

        // Load Connections
        if let data = UserDefaults.standard.data(forKey: connectionsKey),
           let decoded = try? JSONDecoder().decode([SSHConnection].self, from: data) {
            self.connections = decoded
        }

        // Load Groups
        if let data = UserDefaults.standard.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([ConnectionGroup].self, from: data) {
            self.groups = decoded
        }

        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            self.favoriteConnectionIds = decoded
        }

        if let data = UserDefaults.standard.data(forKey: recentKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            self.recentConnectionIds = decoded
        }

        let localPaths = LocalTerminalPathStore.shared
        for connection in connections where connection.type == .localTerminal {
            localPaths.loadPersistedPath(for: connection.id)
        }
    }

    private func performSave() {
        let connectionsToSave = self.connections
        let groupsToSave = self.groups
        
        saveQueue.async {
            if let encoded = try? JSONEncoder().encode(connectionsToSave) {
                UserDefaults.standard.set(encoded, forKey: self.connectionsKey)
            }
            if let encoded = try? JSONEncoder().encode(groupsToSave) {
                UserDefaults.standard.set(encoded, forKey: self.groupsKey)
            }
            if let encoded = try? JSONEncoder().encode(self.favoriteConnectionIds) {
                UserDefaults.standard.set(encoded, forKey: self.favoritesKey)
            }
            if let encoded = try? JSONEncoder().encode(self.recentConnectionIds) {
                UserDefaults.standard.set(encoded, forKey: self.recentKey)
            }
        }
    }
    
    func addGroup(name: String) {
        groups.append(ConnectionGroup(name: name))
    }

    func isFavorite(_ id: UUID) -> Bool {
        favoriteConnectionIds.contains(id)
    }

    func toggleFavorite(id: UUID) {
        if favoriteConnectionIds.contains(id) {
            favoriteConnectionIds.removeAll { $0 == id }
        } else {
            favoriteConnectionIds.insert(id, at: 0)
        }
    }

    func recordRecent(id: UUID) {
        recentConnectionIds.removeAll { $0 == id }
        recentConnectionIds.insert(id, at: 0)
        if recentConnectionIds.count > recentMaxCount {
            recentConnectionIds = Array(recentConnectionIds.prefix(recentMaxCount))
        }
    }

    func deleteConnection(id: UUID) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            let deleted = connections[index]
            connections.remove(at: index)
            for i in groups.indices {
                groups[i].connectionIds.removeAll { $0 == id }
            }
            favoriteConnectionIds.removeAll { $0 == id }
            recentConnectionIds.removeAll { $0 == id }
            if deleted.type == .localTerminal {
                LocalTerminalPathStore.shared.removePath(for: id)
            }
        }
    }
}
