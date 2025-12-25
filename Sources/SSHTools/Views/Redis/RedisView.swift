import SwiftUI




// MARK: - Redis视图
struct RedisView: View {
    let connection: SSHConnection
    var onUpdateConnection: ((SSHConnection) -> Void)?
    @StateObject private var viewModel: RedisViewModel
    @State private var showNewKeySheet = false
    @State private var showImportSheet = false
    @State private var showSettings = false
    @State private var openTabs: [String] = [] // 打开的标签页
    @State private var selectedTab: String? // 当前选中的标签
    
    // Deletion Confirmation
    @State private var keyToDelete: String?
    @State private var showDeleteConfirmation = false
    
    private var currentDBKeyCount: Int {
        if let stat = viewModel.overview?.dbStats.first(where: { $0.name == "db\(viewModel.currentDB)" }) {
            return stat.keys
        }
        return viewModel.keys.count
    }
    
    private var matchingHistory: [String] {
        if viewModel.searchText.isEmpty { return [] }
        return viewModel.searchHistory.filter {
            $0.localizedCaseInsensitiveContains(viewModel.searchText) && $0 != viewModel.searchText
        }
    }
    
    init(connection: SSHConnection, onUpdateConnection: ((SSHConnection) -> Void)? = nil) {
        self.connection = connection
        self.onUpdateConnection = onUpdateConnection
        // 使用共享的ViewModel管理器获取或创建ViewModel
        let manager = RedisViewModelManager.shared
        _viewModel = StateObject(wrappedValue: manager.getViewModel(for: connection))
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .sheet(isPresented: $showSettings) {
            RedisSettingsView(connection: connection) { updatedConnection in
                // 更新 ViewModel 的连接信息
                viewModel.updateConnection(updatedConnection)
                // 通知父视图更新（持久化）
                onUpdateConnection?(updatedConnection)
            }
        }
        .onAppear {
            viewModel.connect()
        }
        .onChange(of: viewModel.selectedKey) { oldValue, newKey in
            guard let newKey else { return }
            openKeyInNewTab(newKey)
            viewModel.loadValue(key: newKey)
        }
        .sheet(isPresented: $showNewKeySheet) {
            NewKeySheet { key, type, ctx in
                viewModel.createKey(key: key, type: type, context: ctx)
                showNewKeySheet = false
            }
        }
        .sheet(isPresented: $showImportSheet) {
            RedisImportSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Are you sure you want to delete the key \"\(keyToDelete ?? "")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let key = keyToDelete {
                    viewModel.deleteKey(key: key)
                    closeTab(key)
                }
                keyToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                keyToDelete = nil
            }
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // 数据库切换和新增key
            HStack(spacing: DesignSystem.Spacing.small) {
                HStack(spacing: 6) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundColor(DesignSystem.Colors.blue)
                        .font(.system(size: 14))
                    
                    Picker("", selection: Binding(
                        get: { viewModel.currentDB },
                        set: { newDB in
                            if newDB != viewModel.currentDB {
                                viewModel.switchDatabase(to: newDB)
                            }
                        }
                    )) {
                        ForEach(0..<16, id: \.self) { db in
                            Text("DB \(db)").tag(db)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .labelsHidden()
                }
                .padding(4)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(DesignSystem.Radius.small)
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.small) {
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                    .help("Import Data")
                    
                    Button(action: { showNewKeySheet = true }) {
                        Label("New Key", systemImage: "plus")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            // 搜索框区域
            VStack(spacing: DesignSystem.Spacing.medium) {
                ZStack(alignment: .top) {
                    HStack(spacing: DesignSystem.Spacing.tiny) {
                        Menu {
                            if viewModel.searchHistory.isEmpty {
                                Text("No History")
                            } else {
                                Text("Search History")
                                Divider()
                                ForEach(viewModel.searchHistory, id: \.self) { historyItem in
                                    Button(historyItem) {
                                        viewModel.searchText = historyItem
                                        viewModel.loadKeys()
                                    }
                                }
                                Divider()
                                Button("Clear History") {
                                    viewModel.clearHistory()
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        
                        TextField("Search keys...", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                viewModel.loadKeys()
                            }
                        
                        if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
                                viewModel.loadKeys()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: {
                            viewModel.loadKeys()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(DesignSystem.Colors.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.background)
                    .cornerRadius(DesignSystem.Radius.small)
                    .zIndex(1)
                    
                    if !matchingHistory.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(matchingHistory.prefix(5), id: \.self) { item in
                                Button(action: {
                                    viewModel.searchText = item
                                    viewModel.loadKeys()
                                }) {
                                    HStack {
                                        Text(item)
                                            .font(DesignSystem.Typography.body)
                                            .foregroundColor(DesignSystem.Colors.text)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.Radius.small)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .padding(.top, 40)
                        .zIndex(2)
                    }
                }
                .zIndex(10)
                
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                        Text("\(currentDBKeyCount)")
                            .font(DesignSystem.Typography.caption.weight(.medium))
                        if viewModel.isLoading {
                            ProgressView().scaleEffect(0.4)
                        }
                    }
                    .foregroundColor(DesignSystem.Colors.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.blue.opacity(0.1))
                    .cornerRadius(DesignSystem.Radius.small)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            // 键列表
            List(viewModel.keys, id: \.self, selection: $viewModel.selectedKey) { key in
                HStack {
                    Text(key)
                        .font(DesignSystem.Typography.monospace)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .contextMenu {
                    Button {
                        openKeyInNewTab(key)
                    } label: {
                        Label("Open in New Tab", systemImage: "plus.square")
                    }
                }
                .onTapGesture {
                    openKeyInNewTab(key)
                }
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
        }
        .navigationTitle(connection.name)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showSettings = true }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.client.isConnected ? DesignSystem.Colors.green : DesignSystem.Colors.pink)
                            .frame(width: 8, height: 8)
                        
                        Text(viewModel.client.isConnected ? "Connected" : "Disconnected")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(DesignSystem.Radius.small)
                }
                .buttonStyle(.plain)
                
                if !viewModel.client.isConnected {
                    Button(action: viewModel.reconnect) {
                        Text("Reconnect")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                }
            }
        }
    }
    
    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            // 标签页栏
            if !openTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(openTabs, id: \.self) { key in
                            Button(action: {
                                selectedTab = key
                            }) {
                                HStack(spacing: 8) {
                                    Text(key)
                                        .font(DesignSystem.Typography.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: 120)
                                    
                                    Button(action: {
                                        closeTab(key)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedTab == key ? DesignSystem.Colors.background : DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.Radius.small)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                        .stroke(selectedTab == key ? DesignSystem.Colors.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, 6)
                }
                .background(DesignSystem.Colors.surface)
                
                Divider()
            }
            
            // 标签页内容
            if let currentKey = selectedTab, openTabs.contains(currentKey) {
                KeyDetailContentView(
                    key: currentKey,
                    viewModel: viewModel,
                    typeString: typeString,
                    copyRedisCommand: copyRedisCommand,
                    contentView: contentView,
                    keyToDelete: $keyToDelete,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            } else if openTabs.isEmpty {
                if let overview = viewModel.overview {
                    RedisOverviewView(overview: overview)
                } else {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        ProgressView()
                        Text("Loading Statistics...")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    var typeString: String {
        switch viewModel.redisValue {
        case .string: return "String"
        case .list: return "List"
        case .set: return "Set"
        case .zset: return "Sorted Set"
        case .hash: return "Hash"
        case .none: return "Loading..."
        case .unsupported(let t): return "Unsupported (\(t))"
        }
    }
    
    // 复制Redis命令到剪贴板
    func copyRedisCommand(key: String) {
        var command = ""
        
        switch viewModel.redisValue {
        case .string:
            command = "GET \"\(key)\""
        case .hash:
            command = "HGETALL \"\(key)\""
        case .list:
            command = "LRANGE \"\(key)\" 0 -1"
        case .set:
            command = "SMEMBERS \"\(key)\""
        case .zset:
            command = "ZRANGE \"\(key)\" 0 -1 WITHSCORES"
        case .none, .unsupported:
            command = "TYPE \"\(key)\""
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }
    
    // 打开新标签页
    private func openKeyInNewTab(_ key: String) {
        if !openTabs.contains(key) {
            // 如果超过最大标签数，删除最早的
            if openTabs.count >= AppConstants.UI.maxOpenTabs {
                let removedKey = openTabs.removeFirst()
                // 如果删除的是当前选中的，切换到新的
                if selectedTab == removedKey {
                    selectedTab = nil
                }
            }
            openTabs.append(key)
        }
        selectedTab = key
    }
    
    // 关闭标签页
    private func closeTab(_ key: String) {
        if let index = openTabs.firstIndex(of: key) {
            openTabs.remove(at: index)
            // 如果关闭的是当前标签，切换到上一个
            if selectedTab == key {
                selectedTab = openTabs.last
            }
        }
    }
    
    func contentView(key: String) -> AnyView {
        switch viewModel.redisValue {
        case .string(let val):
            return AnyView(
                StringEditor(value: val) { newValue in
                    viewModel.updateString(key: key, value: newValue)
                }
            )
        case .hash(let dict):
            return AnyView(
                HashEditor(data: dict, onUpdate: { field, val in
                    viewModel.updateHash(key: key, field: field, value: val)
                }, onDelete: { field in
                    viewModel.deleteHashField(key: key, field: field)
                })
            )
        case .list(let list):
            return AnyView(
                ListEditor(list: list, 
                          onUpdate: { idx, val in
                              viewModel.updateList(key: key, index: idx, value: val)
                          },
                          onAdd: { val in
                              viewModel.addToList(key: key, value: val)
                          },
                          onDelete: { idx in
                              viewModel.deleteFromList(key: key, index: idx)
                          })
            )
        case .set(let set):
            return AnyView(
                SetEditor(items: set, onUpdate: { old, new in
                    viewModel.updateSet(key: key, oldValue: old, newValue: new)
                }, onAdd: { new in
                    viewModel.addToSet(key: key, value: new)
                }, onDelete: { val in
                    viewModel.deleteFromSet(key: key, value: val)
                })
            )
        case .zset(let zitems):
            return AnyView(
                ZSetEditor(items: zitems, onUpdate: { member, score in
                    viewModel.updateZSet(key: key, member: member, score: score)
                }, onDelete: { member in
                    viewModel.deleteFromZSet(key: key, member: member)
                })
            )
        case .unsupported(let type):
            return AnyView(
                VStack(spacing: DesignSystem.Spacing.large) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.orange)
                    Text("Unsupported Type: \(type)")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        case .none:
            // 加载中显示占位，避免“无渲染”的误解
            return AnyView(
                VStack(spacing: DesignSystem.Spacing.medium) {
                    ProgressView()
                    Text("Loading...")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
    }
}

// Structs removed: HashEditor, ListEditor (they are in RedisComponents.swift)


struct AlertItem: Identifiable {
    var id = UUID()
    var message: String
}

// MARK: - Key详情内容视图
struct KeyDetailContentView: View {
    let key: String
    @ObservedObject var viewModel: RedisViewModel
    let typeString: String
    let copyRedisCommand: (String) -> Void
    let contentView: (String) -> AnyView
    
    @Binding var keyToDelete: String?
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack(spacing: RedisDesignSystem.spacingMedium) {
                VStack(alignment: .leading, spacing: RedisDesignSystem.spacingTiny) {
                    Text("Key")
                        .font(.system(size: RedisDesignSystem.fontSizeMicro, weight: .medium))
                        .foregroundColor(RedisDesignSystem.secondaryText)
                    Text(key)
                        .font(.system(size: RedisDesignSystem.fontSizeMedium, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(typeString)
                    .font(.system(size: RedisDesignSystem.fontSizeTiny, weight: .medium))
                    .foregroundColor(RedisDesignSystem.primaryBlue)
                    .padding(.horizontal, RedisDesignSystem.spacingSmall)
                    .padding(.vertical, RedisDesignSystem.spacingTiny)
                    .background(RedisDesignSystem.primaryBlue.opacity(0.1))
                    .cornerRadius(RedisDesignSystem.cornerRadiusSmall)
                
                Spacer().frame(width: RedisDesignSystem.spacingMedium)
                
                // 功能按钮组
                HStack(spacing: RedisDesignSystem.spacingSmall) {
                    Button(action: { copyRedisCommand(key) }) {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .iconButton()
                    .buttonStyle(.plain)
                    .help("复制Redis命令")
                    
                    Button(action: { viewModel.loadValue(key: key) }) {
                        Image(systemName: "arrow.clockwise")
                            .fontWeight(.semibold)
                    }
                    .iconButton(color: RedisDesignSystem.primaryGreen)
                    .buttonStyle(.plain)
                    .help("刷新")
                    
                    Button(action: { 
                        keyToDelete = key
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash.fill")
                    }
                    .iconButton(color: RedisDesignSystem.primaryRed)
                    .buttonStyle(.plain)
                    .help("删除键")
                }
            }
            .padding(.horizontal, RedisDesignSystem.spacingLarge)
            .padding(.vertical, RedisDesignSystem.spacingTiny)
            .background(RedisDesignSystem.background)
            
            Divider()
            
            contentView(key)
        }
        .task(id: key) {
            viewModel.loadValue(key: key)
        }
    }
}

// MARK: - 概览视图
struct RedisOverviewView: View {
    let overview: RedisOverview
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // MARK: - Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Redis Dashboard".localized)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    
                    if let version = overview.version {
                        Text("\("Version".localized): \(version) • \(overview.os ?? "Unknown OS")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)
                
                // MARK: - Key Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
                    ModernStatCard(title: "Memory Used".localized, 
                                 value: overview.usedMemoryHuman ?? "N/A", 
                                 icon: "memorychip", 
                                 color: .blue)
                    
                    ModernStatCard(title: "Clients".localized, 
                                 value: "\(overview.connectedClients ?? 0)", 
                                 icon: "person.2.fill", 
                                 color: .green)
                    
                    ModernStatCard(title: "Hit Rate".localized, 
                                 value: String(format: "%.1f%%", (overview.keyspaceHitRate ?? 0) * 100), 
                                 icon: "target", 
                                 color: .orange)
                    
                    ModernStatCard(title: "Ops/sec".localized, 
                                 value: "\(overview.instantaneousOpsPerSec ?? 0)", 
                                 icon: "bolt.fill", 
                                 color: .purple)
                }
                
                HStack(alignment: .top, spacing: 32) {
                    // MARK: - Left: DB Statistics
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Database Keys".localized, icon: "cylinder.split.1x2.fill")
                        
                        CardView(padding: 0) {
                            Table(overview.dbStats) {
                                TableColumn("Database".localized) { stat in
                                    Text(stat.name).font(.system(size: 13, weight: .medium))
                                }
                                TableColumn("Keys".localized) { stat in
                                    Text("\(stat.keys)").monospacedDigit()
                                }
                                TableColumn("Expires".localized) { stat in
                                    Text("\(stat.expires)").foregroundColor(.secondary)
                                }
                                TableColumn("Avg TTL".localized) { stat in
                                    Text(stat.avgTTL == 0 ? "-" : "\(stat.avgTTL)s").foregroundColor(.secondary)
                                }
                            }
                            .frame(height: 300)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // MARK: - Right: Server Info
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Server Info".localized, icon: "info.circle.fill")
                        
                        CardView {
                            VStack(spacing: 16) {
                                InfoRow(title: "Process ID", value: "\(overview.processId ?? 0)")
                                InfoRow(title: "Uptime", value: "\(overview.uptimeDays ?? 0) days")
                                InfoRow(title: "Role", value: overview.role?.capitalized ?? "Master")
                                Divider()
                                InfoRow(title: "Peak Memory", value: overview.peakMemoryHuman ?? "N/A")
                                InfoRow(title: "Fragmentation", value: String(format: "%.2f", overview.memFragmentationRatio ?? 0))
                            }
                        }
                    }
                    .frame(width: 300)
                }
            }
            .padding(32)
        }
        .background(DesignSystem.Colors.background)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title.localized)
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
        }
    }
}

// MARK: - Redis设置视图
struct RedisSettingsView: View {
    let connection: SSHConnection
    let onSave: (SSHConnection) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var password: String
    @State private var database: Int
    
    init(connection: SSHConnection, onSave: @escaping (SSHConnection) -> Void = { _ in }) {
        self.connection = connection
        self.onSave = onSave
        _name = State(initialValue: connection.name)
        _host = State(initialValue: connection.host)
        _port = State(initialValue: connection.port)
        _password = State(initialValue: connection.password)
        _database = State(initialValue: connection.redisDB)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("Redis 连接设置")
                    .font(DesignSystem.fontTitle)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(DesignSystem.secondaryColor)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DesignSystem.surfaceColor)
            
            Divider()
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingLarge) {
                    
                    // 基本信息
                    VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                        Label("基本信息", systemImage: "info.circle")
                            .font(DesignSystem.fontHeadline)
                            .foregroundColor(DesignSystem.primaryColor)
                        
                        TextField("别名", text: $name)
                            .textFieldStyle(ModernTextFieldStyle(icon: "tag"))
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(DesignSystem.cornerRadiusMedium)
                    
                    // 服务器信息
                    VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                        Label("服务器信息", systemImage: "server.rack")
                            .font(DesignSystem.fontHeadline)
                            .foregroundColor(DesignSystem.primaryColor)
                        
                        TextField("主机", text: $host)
                            .textFieldStyle(ModernTextFieldStyle(icon: "network"))
                        
                        HStack(spacing: DesignSystem.spacingSmall) {
                            TextField("端口", text: $port)
                                .textFieldStyle(ModernTextFieldStyle(icon: "number"))
                            
                            TextField("数据库索引", value: $database, format: .number)
                                .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(DesignSystem.cornerRadiusMedium)
                    
                    // 认证
                    VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                        Label("认证", systemImage: "lock.shield")
                            .font(DesignSystem.fontHeadline)
                            .foregroundColor(DesignSystem.primaryColor)
                        
                        SecureField("密码 (可选)", text: $password)
                            .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(DesignSystem.cornerRadiusMedium)
                }
                .padding()
            }
            
            Divider()
            
            // 按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary))
                
                Spacer()
                
                Button("保存") {
                    saveSettings()
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
            }
            .padding()
            .background(DesignSystem.surfaceColor)
        }
        .frame(width: 480, height: 550)
        .background(DesignSystem.backgroundColor)
    }
    
    private func saveSettings() {
        // 创建更新后的连接信息
        var updatedConnection = connection
        updatedConnection.name = name
        updatedConnection.host = host
        updatedConnection.port = port.isEmpty ? AppConstants.Ports.redis : port
        updatedConnection.password = password
        updatedConnection.redisDB = database
        
        // 通过回调更新连接信息
        onSave(updatedConnection)
    }
}

// MARK: - 已删除未使用的 KeyDetailTabView（已由 KeyDetailContentView 替代）
