import SwiftUI
import AppKit

struct HomeView: View {
    @StateObject private var todoManager = TodoManager()
    @ObservedObject private var transferManager = TransferManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var newTodoText = ""
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // MARK: - Welcome Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dashboard".localized)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.blue, DesignSystem.Colors.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Welcome back! Control your infrastructure from here.".localized)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(currentTime, style: .date)
                            .font(.headline)
                        Text(currentTime.formatted(.dateTime.hour().minute().second()))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)
                .onReceive(timer) { input in
                    currentTime = input
                }
                
                // MARK: - Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
                    ModernStatCard(title: "Active Tasks".localized, 
                                 value: "\(transferManager.tasks.filter { $0.status == .transferring }.count)", 
                                 icon: "arrow.up.arrow.down.circle.fill", 
                                 color: .blue)
                    
                    ModernStatCard(title: "Pending Todos".localized, 
                                 value: "\(todoManager.todos.filter { !$0.isCompleted }.count)", 
                                 icon: "checklist", 
                                 color: .orange)
                    
                    ModernStatCard(title: "Completed".localized, 
                                 value: "\(todoManager.todos.filter { $0.isCompleted }.count)", 
                                 icon: "checkmark.seal.fill", 
                                 color: .green)
                    
                    ModernStatCard(title: "Bandwidth".localized, 
                                 value: "N/A", 
                                 icon: "gauge", 
                                 color: .purple)
                }
                
                HStack(alignment: .top, spacing: 32) {
                    // MARK: - Main Content: Todo List
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Todo List".localized, icon: "list.bullet.rectangle.fill")
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .foregroundColor(.secondary)
                                
                                TextField("Quick add a task...".localized, text: $newTodoText)
                                    .textFieldStyle(.plain)
                                    .onSubmit { addTodo() }
                                
                                if !newTodoText.isEmpty {
                                    Button("Add".localized, action: addTodo)
                                        .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(16)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(12, corners: [.topLeft, .topRight])
                            
                            Divider()
                            
                            VStack(spacing: 0) {
                                if todoManager.todos.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "tray")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text("All caught up!".localized)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 60)
                                } else {
                                    ForEach(todoManager.todos.prefix(8)) { item in
                                        TodoRow(item: item, 
                                                onToggle: { todoManager.toggleCompletion(for: item) },
                                                onDelete: { todoManager.deleteTodo(item) },
                                                onUpdate: { updatedItem in todoManager.updateTodo(updatedItem) })
                                        
                                        if item.id != todoManager.todos.prefix(8).last?.id {
                                            Divider().padding(.leading, 52)
                                        }
                                    }
                                }
                            }
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                        }
                        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Settings".localized, icon: "gearshape.fill")
                            
                            VStack(spacing: 20) {
                                // Theme Setting
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("App Theme".localized, systemImage: "paintbrush.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    
                                    Picker("", selection: $settings.userTheme) {
                                        ForEach(AppTheme.allCases) { theme in
                                            Text(theme.rawValue.localized).tag(theme)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                
                                Divider()

                                // Download Path Setting
                                ModernSettingRow(
                                    title: "Download Path".localized,
                                    subtitle: settings.defaultDownloadPath.isEmpty ? "Not set".localized : settings.defaultDownloadPath,
                                    icon: "folder.badge.gearshape",
                                    action: { settings.selectDownloadDirectory() }
                                )
                                
                                // Terminal Background Setting
                                ModernSettingRow(
                                    title: "Terminal Background".localized,
                                    subtitle: settings.terminalBackgroundImagePath.isEmpty ? "Default".localized : (settings.terminalBackgroundImagePath as NSString).lastPathComponent,
                                    icon: "photo.fill",
                                    action: { settings.selectTerminalBackgroundImage() }
                                )
                                .contextMenu {
                                    if !settings.terminalBackgroundImagePath.isEmpty {
                                        Button("Clear Background".localized) {
                                            settings.clearTerminalBackgroundImage()
                                        }
                                    }
                                }
                                
                                // Proxy Settings
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: $settings.enableLocalProxy) {
                                        Label("Use Local Proxy".localized, systemImage: "network")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                    }
                                    .toggleStyle(.switch)
                                    
                                    if settings.enableLocalProxy {
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Host".localized)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                TextField("127.0.0.1", text: $settings.localProxyHost)
                                                    .textFieldStyle(ModernTextFieldStyle(icon: "server.rack"))
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Port".localized)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                TextField("7890", text: $settings.localProxyPort)
                                                    .textFieldStyle(ModernTextFieldStyle(icon: "number"))
                                                    .frame(width: 100)
                                            }
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                
                                // Gemini Key Setting
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Gemini API Key".localized, systemImage: "sparkles")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    
                                    SecureField("Enter API Key".localized, text: $settings.geminiApiKey)
                                        .textFieldStyle(ModernTextFieldStyle(icon: "key.fill"))
                                }
                            }
                            .padding(20)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
                        }
                    }
                    .frame(width: 320)
                }
                
                if !transferManager.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Live Transfers".localized, icon: "arrow.up.arrow.down.square.fill")
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(transferManager.tasks.prefix(5)) { task in
                                    CompactTransferCard(task: task)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 60)
        }
        .background(DesignSystem.Colors.background)
    }
    
    private func addTodo() {
        guard !newTodoText.isEmpty else { return }
        withAnimation {
            todoManager.addTodo(title: newTodoText, reminder: nil)
            newTodoText = ""
        }
    }
}

// MARK: - Supporting Components

struct ModernSettingRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

struct ModernQuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.1))
                    .cornerRadius(8)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
                
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(12)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct CompactTransferCard: View {
    let task: TransferTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: task.type == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(task.type == .upload ? .orange : .blue)
                Text(task.fileName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .tint(task.type == .upload ? .orange : .blue)
            
            HStack {
                Text(task.status.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(task.progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}


