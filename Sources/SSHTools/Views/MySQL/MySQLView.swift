import SwiftUI

struct MySQLView: View {
    @StateObject private var viewModel: MySQLViewModel
    
    // AI SQL Helper State
    @State private var showAIHelper = false
    @State private var aiPrompt = ""
    @State private var isAIGenerating = false
    
    init(connection: SSHConnection) {
        _viewModel = StateObject(wrappedValue: MySQLViewModel(connection: connection))
    }
    
    var body: some View {
        HSplitView {
            // Sidebar: DB & Tables
            VStack(spacing: 0) {
                // DB Selector Header
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("Database".localized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Picker("", selection: $viewModel.currentDatabase) {
                        ForEach(viewModel.databases, id: \.self) { db in
                            Text(db).tag(db)
                        }
                    }
                    .labelsHidden()
                    .disabled(viewModel.isLoading)
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                
                Divider()
                
                // Tables List
                List(viewModel.tables, id: \.self, selection: $viewModel.currentTable) { table in
                    HStack {
                        Image(systemName: "tablecells")
                            .foregroundColor(DesignSystem.Colors.blue)
                        Text(table)
                            .font(DesignSystem.Typography.body)
                    }
                    .tag(table)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 200, maxWidth: 300)
            .background(DesignSystem.Colors.background)
            
            // Content: Data Grid
            VStack(spacing: 0) {
                // Top Bar: Mode Switcher
                HStack(spacing: 0) {
                    ModeButton(title: "Overview", icon: "chart.bar.fill", mode: .overview, currentMode: $viewModel.currentMode)
                    ModeButton(title: "Data Editor", icon: "tablecells", mode: .tableData, currentMode: $viewModel.currentMode)
                    ModeButton(title: "SQL Console", icon: "terminal.fill", mode: .console, currentMode: $viewModel.currentMode)
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView().scaleEffect(0.5).padding(.trailing)
                    }
                }
                .background(DesignSystem.Colors.surface)
                
                Divider()

                // Content switching based on mode
                switch viewModel.currentMode {
                case .overview:
                    MySQLOverviewView(viewModel: viewModel)
                case .tableData:
                    tableDataContent
                case .console:
                    consoleContent
                }
            }
            .background(DesignSystem.Colors.background)
        }
        .onAppear {
            viewModel.connect()
        }
    }
    
    @ViewBuilder
    private var tableDataContent: some View {
        VStack(spacing: 0) {
            // Query Controls (Filter & Sort)
            if viewModel.currentTable != nil {
                VStack(spacing: DesignSystem.Spacing.small) {
                    HStack(spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text("WHERE")
                                .font(DesignSystem.Typography.caption.bold())
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            TextField("id > 5 AND status = 'active'", text: $viewModel.whereClause)
                                .textFieldStyle(ModernTextFieldStyle())
                                .onSubmit { viewModel.loadData() }
                        }
                        
                        HStack {
                            Text("ORDER BY")
                                .font(DesignSystem.Typography.caption.bold())
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            TextField("created_at DESC", text: $viewModel.orderBy)
                                .textFieldStyle(ModernTextFieldStyle())
                                .onSubmit { viewModel.loadData() }
                        }
                        
                        Button(action: { viewModel.loadData() }) {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(ModernButtonStyle(variant: .primary))
                    }
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                Section(header: tableHeader) {
                                    ForEach(0..<viewModel.rows.count, id: \.self) { idx in
                                        DataRow(rowIndex: idx, rowData: viewModel.rows[idx], viewModel: viewModel)
                                    }
                                }
                                .id("scroll-top")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("scroll-top", anchor: .topLeading)
                            }
                        }
                        .onChange(of: viewModel.currentTable) { oldValue, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("scroll-top", anchor: .topLeading)
                            }
                        }
                    }
                }
                
                paginationBar
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "tablecells.fill")
                        .font(.system(size: 64))
                        .foregroundColor(DesignSystem.Colors.blue.opacity(0.2))
                    Text("Select a table to browse data".localized)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private var consoleContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                SQLCodeEditor(text: $viewModel.sqlEditorText, 
                              tables: viewModel.tables,
                              onExecute: { viewModel.executeRawSQL() })
                    .frame(minHeight: 150, maxHeight: 300)
                
                // Floating Action Buttons (Bottom Right)
                if !showAIHelper {
                    HStack(spacing: 12) {
                        // AI Button
                        Button(action: { withAnimation { showAIHelper = true } }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("AI SQL")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        
                        // Run Button
                        Button(action: { viewModel.executeRawSQL() }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Run".localized)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command) // Keep CMD+Enter working visually too
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
                
                // AI Helper Overlay (Bottom Center/Expanded)
                if showAIHelper {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        
                        TextField("Describe query...", text: $aiPrompt)
                            .textFieldStyle(.plain)
                            .foregroundColor(.black)
                            .onSubmit { generateSQL() }
                        
                        if isAIGenerating {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Button(action: generateSQL) {
                                Text("Generate")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }
                        
                        Button(action: { withAnimation { showAIHelper = false } }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(radius: 5)
                    .padding()
                    .onExitCommand {
                        withAnimation { showAIHelper = false }
                    }
                    .transition(.move(edge: .bottom))
                    // Ensure it stays at the bottom of the ZStack
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .background(DesignSystem.Colors.surface) // Editor background container
            
            HStack {
                Text("Hint: TAB for completions, CMD+Enter to run.")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            if !viewModel.headers.isEmpty {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header: tableHeader) {
                                ForEach(0..<viewModel.rows.count, id: \.self) { idx in
                                    DataRow(rowIndex: idx, rowData: viewModel.rows[idx], viewModel: viewModel)
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
            } else {
                VStack {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("Ready for queries".localized)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var paginationBar: some View {
        HStack {
            Picker("", selection: $viewModel.limit) {
                ForEach(viewModel.limitOptions, id: \.self) { opt in
                    Text("\(opt) / page").tag(opt)
                }
            }
            .frame(width: 100)
            
            Spacer()
            
            Button(action: { viewModel.prevPage() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ModernButtonStyle(variant: .secondary))
            .disabled(viewModel.page <= 1)
            
            Text("\("Page".localized) \(viewModel.page)")
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal)
            
            Button(action: { viewModel.nextPage() }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(ModernButtonStyle(variant: .secondary))
            .disabled(viewModel.rows.count < viewModel.limit)
            
            Spacer()
            
            Text("\(viewModel.rows.count) " + "Rows".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(DesignSystem.Colors.surface)
    }
    
    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Sequence Header
            Text("#")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.bold)
                .frame(width: 50, height: DesignSystem.Layout.headerHeight, alignment: .center)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle().stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
            
            ForEach(Array(viewModel.headers.enumerated()), id: \.offset) { index, header in
                HeaderCell(
                    title: header,
                    width: viewModel.columnWidths.indices.contains(index) ? viewModel.columnWidths[index] : 150,
                    onResize: { newWidth in
                        if viewModel.columnWidths.indices.contains(index) {
                            viewModel.updateColumnWidth(index: index, width: newWidth)
                        }
                    }
                )
            }
        }
    }
    
    private func generateSQL() {
        guard !aiPrompt.isEmpty else { return }
        isAIGenerating = true
        
        Task {
            do {
                let sql = try await GeminiService.shared.generateSQLCommand(prompt: aiPrompt)
                await MainActor.run {
                    self.viewModel.sqlEditorText = sql
                    self.isAIGenerating = false
                    self.showAIHelper = false
                    self.aiPrompt = ""
                    // Optional: auto execute? Maybe safer to let user review first.
                }
            } catch {
                Logger.log("AI Error: \(error)", level: .error)
            }
            isAIGenerating = false
        }
    }
}

// MARK: - Supporting Components

struct ModeButton: View {
    let title: String
    let icon: String
    let mode: MySQLViewModel.MySQLMode
    @Binding var currentMode: MySQLViewModel.MySQLMode
    
    var body: some View {
        Button(action: { currentMode = mode }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title.localized)
                    .font(.system(size: 13, weight: currentMode == mode ? .semibold : .regular))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(currentMode == mode ? Color.primary.opacity(0.05) : Color.clear)
            .foregroundColor(currentMode == mode ? .blue : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct MySQLOverviewView: View {
    @ObservedObject var viewModel: MySQLViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("MySQL Dashboard".localized)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    
                    if let info = viewModel.serverInfo {
                        Text("\("Version".localized): \(info.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)
                
                if let info = viewModel.serverInfo {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)
                    ], spacing: 20) {
                        ModernStatCard(title: "Active Threads".localized, 
                                     value: info.threads, 
                                     icon: "person.2.fill", 
                                     color: .blue)
                        
                        ModernStatCard(title: "Slow Queries".localized, 
                                     value: info.slowQueries, 
                                     icon: "tortoise.fill", 
                                     color: .orange)
                        
                        ModernStatCard(title: "Open Tables".localized, 
                                     value: info.openTables, 
                                     icon: "tablecells.fill", 
                                     color: .green)
                        
                        ModernStatCard(title: "Total Queries".localized, 
                                     value: info.questions, 
                                     icon: "questionmark.circle.fill", 
                                     color: .purple)
                    }
                } else {
                    HStack {
                        ProgressView().padding(.trailing, 8)
                        Text("Loading server statistics...".localized)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
                
                HStack(alignment: .top, spacing: 32) {
                    // Left: Databases
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Databases".localized, icon: "server.rack")
                        
                        CardView(padding: 0) {
                            List(viewModel.databases, id: \.self) { db in
                                HStack {
                                    Image(systemName: "database")
                                        .foregroundColor(.blue)
                                    Text(db)
                                        .font(.system(size: 13))
                                    Spacer()
                                    if db == viewModel.currentDatabase {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(height: 300)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right: Performance & Uptime
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Runtime Info".localized, icon: "cpu")
                        
                        CardView {
                            VStack(spacing: 16) {
                                if let info = viewModel.serverInfo {
                                    MySQLInfoRow(title: "Uptime", value: "\(Int(info.uptime) ?? 0) s")
                                    Divider()
                                    MySQLInfoRow(title: "Connections", value: viewModel.connection.host)
                                    MySQLInfoRow(title: "User", value: viewModel.connection.username)
                                }
                            }
                        }
                    }
                    .frame(width: 300)
                }
            }
            .padding(32)
        }
    }
}

struct MySQLInfoRow: View {
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