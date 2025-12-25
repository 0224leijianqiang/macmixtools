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
    
    private let connectionsKey = AppConstants.StorageKeys.savedConnections
    private let groupsKey = "saved_groups"
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
        }
    }
    
    func addGroup(name: String) {
        groups.append(ConnectionGroup(name: name))
    }
    
    func deleteConnection(id: UUID) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections.remove(at: index)
            for i in groups.indices {
                groups[i].connectionIds.removeAll { $0 == id }
            }
        }
    }
}
