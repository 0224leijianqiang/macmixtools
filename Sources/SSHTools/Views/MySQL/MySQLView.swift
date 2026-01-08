import SwiftUI
import AppKit
import UniformTypeIdentifiers

private extension View {
    @ViewBuilder
    func sshtools_disableFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}

struct MySQLView: View {
    @StateObject private var viewModel: MySQLViewModel

    @FocusState private var isDataGridFocused: Bool
    @State private var showFilterBuilder = false
    @State private var isExporting = false
	@State private var exportTitle = "Export"
	@State private var exportStatus = ""
	@State private var exportRowsExported: Int = 0
	@State private var exportTask: Task<Void, Never>? = nil
	@State private var editCellTarget: EditCellTarget? = nil
	@State private var isEstimatingMutation = false
    
    // AI SQL Helper State
    @State private var showAIHelper = false
    @State private var aiPrompt = ""
    @State private var isAIGenerating = false
    
	init(connection: SSHConnection) {
		_viewModel = StateObject(wrappedValue: MySQLViewModel(connection: connection))
	}

	private struct EditCellTarget: Identifiable {
		let id = UUID()
		let rowIndex: Int
		let columnIndex: Int
		let originalValue: String
	}

    private func copyToPasteboard(_ string: String, toast: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        ToastManager.shared.show(message: toast, type: .success)
    }

    private var selectedRowIndicesSorted: [Int] {
        viewModel.selectedRowIndices.sorted()
    }

    private func selectedRowsData() -> [[String]] {
        selectedRowIndicesSorted.compactMap { idx in
            guard viewModel.rows.indices.contains(idx) else { return nil }
            return viewModel.rows[idx]
        }
    }

    private func copySelectedCellIfAny() {
        let selected = selectedRowIndicesSorted
        guard selected.count == 1,
              let rowIndex = selected.first,
              viewModel.rows.indices.contains(rowIndex),
              let colIndex = viewModel.selectedColumnIndex,
              viewModel.rows[rowIndex].indices.contains(colIndex)
        else { return }
        copyToPasteboard(viewModel.rows[rowIndex][colIndex], toast: "Copied Cell")
    }

    private func copySelectedRowsTSV(includeHeaders: Bool) {
        let rows = selectedRowsData()
        guard !rows.isEmpty else { return }
        var lines: [String] = []
        if includeHeaders, !viewModel.headers.isEmpty {
            lines.append(viewModel.headers.joined(separator: "\t"))
        }
        lines.append(contentsOf: rows.map { $0.joined(separator: "\t") })
        copyToPasteboard(
            lines.joined(separator: "\n"),
            toast: rows.count == 1 ? (includeHeaders ? "Copied Row (TSV+Headers)" : "Copied Row (TSV)") : (includeHeaders ? "Copied Rows (TSV+Headers)" : "Copied Rows (TSV)")
        )
    }

    private func copySelectedRowsJSON() {
        let rows = selectedRowsData()
        guard !rows.isEmpty else { return }
        let count = viewModel.headers.count
        let jsonArray: [[String: String]] = rows.map { row in
            var dict: [String: String] = [:]
            let used = min(count, row.count)
            dict.reserveCapacity(used)
            for i in 0..<used {
                dict[viewModel.headers[i]] = row[i]
            }
            return dict
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            let text = String(data: data, encoding: .utf8) ?? "[]"
            copyToPasteboard(text, toast: rows.count == 1 ? "Copied Row (JSON)" : "Copied Rows (JSON)")
        } catch {
            ToastManager.shared.show(message: "JSON encode failed", type: .error)
        }
    }

    private func copyGridSelectionProviders() -> [NSItemProvider] {
        let selected = viewModel.selectedRowIndices.sorted()
        guard !selected.isEmpty else { return [] }

        if selected.count == 1,
           let rowIndex = selected.first,
           viewModel.rows.indices.contains(rowIndex),
           let colIndex = viewModel.selectedColumnIndex,
           viewModel.rows[rowIndex].indices.contains(colIndex) {
            ToastManager.shared.show(message: "Copied Cell", type: .success)
            return [NSItemProvider(object: viewModel.rows[rowIndex][colIndex] as NSString)]
        }

        let lines = selected.compactMap { idx -> String? in
            guard viewModel.rows.indices.contains(idx) else { return nil }
            return viewModel.rows[idx].joined(separator: "\t")
        }
        guard !lines.isEmpty else { return [] }

        ToastManager.shared.show(message: lines.count == 1 ? "Copied Row (TSV)" : "Copied Rows (TSV)", type: .success)
        return [NSItemProvider(object: lines.joined(separator: "\n") as NSString)]
    }

    private func pickExportDestination(defaultName: String, ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName + "." + ext
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: ext)].compactMap { $0 }
        } else {
            panel.allowedFileTypes = [ext]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func startExportCurrent(format: MySQLViewModel.ExportFormat) {
        guard let url = pickExportDestination(defaultName: "export_current", ext: format.fileExtension) else { return }
        do {
            try viewModel.exportCurrentResult(to: url, format: format)
            ToastManager.shared.show(message: "Exported", type: .success)
        } catch {
            ToastManager.shared.show(message: "Export failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func startExportAll(format: MySQLViewModel.ExportFormat) {
        guard viewModel.currentTable != nil else { return }
        guard let url = pickExportDestination(defaultName: "export_all", ext: format.fileExtension) else { return }

        exportTask?.cancel()
        exportRowsExported = 0
        exportTitle = "Export All"
        exportStatus = "Starting…"
        isExporting = true

        exportTask = Task {
            do {
                try await viewModel.exportAllTableData(to: url, format: format, pageSize: 1000) { rowsExported in
                    Task { @MainActor in
                        exportRowsExported = rowsExported
                        exportStatus = "Exported \(rowsExported) rows"
                    }
                }
                await MainActor.run {
                    exportStatus = "Done"
                    isExporting = false
                }
                ToastManager.shared.show(message: "Exported", type: .success)
            } catch is CancellationError {
                await MainActor.run {
                    exportStatus = "Cancelled"
                    isExporting = false
                }
                ToastManager.shared.show(message: "Export cancelled", type: .warning)
            } catch {
                await MainActor.run {
                    exportStatus = "Failed"
                    isExporting = false
                }
                ToastManager.shared.show(message: "Export failed: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // Sidebar: DB & Tables
            VStack(spacing: 0) {
                // DB Selector Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .foregroundColor(DesignSystem.Colors.blue)
                        Text(viewModel.connection.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Connection Status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isConnected ? DesignSystem.Colors.green : DesignSystem.Colors.pink)
                            .frame(width: 6, height: 6)
                        Text(viewModel.isConnected ? "Connected" : "Disconnected")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(DesignSystem.Radius.small)
                    
                    Picker("", selection: $viewModel.currentDatabase) {
                        ForEach(viewModel.databases, id: \.self) { db in
                            Text(db).tag(db)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .labelsHidden()
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .frame(height: 44)
                .background(DesignSystem.Colors.surface)

                if let error = viewModel.errorMsg, !error.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(DesignSystem.Colors.pink)
                        Text(error)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.pink)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                        Button("Retry") { viewModel.connect() }
                            .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.surfaceSecondary)
                }
                
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
                .frame(height: 44)
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
		.sheet(isPresented: $isExporting) {
			SheetScaffold(
                title: exportTitle,
                subtitle: exportStatus,
                minSize: NSSize(width: 520, height: 240),
                onClose: {
                    exportTask?.cancel()
                    exportTask = nil
                    isExporting = false
                }
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(exportStatus)
                            .font(DesignSystem.Typography.body)
                        Spacer()
                    }
                    Text("Rows: \(exportRowsExported)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.medium)
            } footer: {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        exportTask?.cancel()
                        exportTask = nil
                        isExporting = false
                    }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
			}
		}
			.sheet(item: $editCellTarget) { target in
				MySQLEditCellSheet(
					viewModel: viewModel,
					rowIndex: target.rowIndex,
					columnIndex: target.columnIndex,
					originalValue: target.originalValue,
					onClose: { editCellTarget = nil }
				)
			}
			.alert("Unsafe SQL", isPresented: $viewModel.showUnsafeMutationAlert) {
				Button("Cancel", role: .cancel) { viewModel.cancelPendingUnsafeMutation() }
				Button("Run Anyway", role: .destructive) { viewModel.runPendingUnsafeMutationAnyway() }
			} message: {
				Text(viewModel.unsafeMutationMessage)
			}
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
                        SQLTextField(text: $viewModel.whereClause, 
                                       placeholder: "id > 5 AND status = 'active'", 
                                       tables: viewModel.tables,
                                       columns: viewModel.allColumns,
                                       onSubmit: { viewModel.loadData() })
                                .frame(height: 32)
                                .padding(.horizontal, 8)
                                .background(DesignSystem.Colors.surfaceSecondary.opacity(0.5))
                                .cornerRadius(DesignSystem.Radius.small)

                        if !viewModel.filterPresets.isEmpty {
                            Menu {
                                ForEach(viewModel.filterPresets) { preset in
                                    Button(preset.name) { viewModel.applyFilterPreset(preset) }
                                }
                            } label: {
                                Image(systemName: "bookmark")
                            }
                            .menuStyle(.borderlessButton)
                            .help("Filter Presets")
                        }

                        Button(action: { showFilterBuilder = true }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                        .help("Filter Builder")
                        .popover(isPresented: $showFilterBuilder) {
                            MySQLFilterBuilderPopover(viewModel: viewModel, isPresented: $showFilterBuilder)
                        }
                    }
                    
                    HStack {
                        Text("ORDER BY")
                            .font(DesignSystem.Typography.caption.bold())
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            SQLTextField(text: $viewModel.orderBy, 
                                       placeholder: "created_at DESC", 
                                       tables: viewModel.tables,
                                       columns: viewModel.allColumns,
                                       onSubmit: { viewModel.loadData() })
                                .frame(height: 32)
                                .padding(.horizontal, 8)
                                .background(DesignSystem.Colors.surfaceSecondary.opacity(0.5))
                                .cornerRadius(DesignSystem.Radius.small)
                        }
                        
                        Button(action: { viewModel.loadData() }) {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(ModernButtonStyle(variant: .primary))

                        Menu {
                            Section("Current Result") {
                                Button("CSV") { startExportCurrent(format: .csv) }
                                Button("TSV") { startExportCurrent(format: .tsv) }
                                Button("JSON") { startExportCurrent(format: .json) }
                            }
                            Divider()
                            Section("All Rows") {
                                Button("CSV") { startExportAll(format: .csv) }
                                    .disabled(viewModel.currentTable == nil)
                                Button("TSV") { startExportAll(format: .tsv) }
                                    .disabled(viewModel.currentTable == nil)
                                Button("JSON") { startExportAll(format: .json) }
                                    .disabled(viewModel.currentTable == nil)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Export")
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
                                        DataRow(
                                            rowIndex: idx,
                                            rowData: viewModel.rows[idx],
                                            viewModel: viewModel,
                                            onEditCell: { rowIndex, colIndex in
                                                guard viewModel.rows.indices.contains(rowIndex),
                                                      viewModel.rows[rowIndex].indices.contains(colIndex) else { return }
                                                if viewModel.connection.type == .clickhouse {
                                                    ToastManager.shared.show(message: "ClickHouse does not support UPDATE", type: .warning)
                                                    return
                                                }
                                                if viewModel.primaryKeyColumns.isEmpty {
                                                    ToastManager.shared.show(message: "No primary key, editing disabled", type: .warning)
                                                    return
                                                }
                                                editCellTarget = EditCellTarget(
                                                    rowIndex: rowIndex,
                                                    columnIndex: colIndex,
                                                    originalValue: viewModel.rows[rowIndex][colIndex]
                                                )
                                            }
                                        )
                                    }
                                }
                                .id("scroll-top")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                        }
                        .focusable(true)
                        .focused($isDataGridFocused)
                        .sshtools_disableFocusRing()
                        .onTapGesture { isDataGridFocused = true }
                        .onCopyCommand { copyGridSelectionProviders() }
                        .onExitCommand { viewModel.clearSelection() }
                        .contextMenu {
                            Button("Copy Cell") { copySelectedCellIfAny() }
                                .disabled(!(selectedRowIndicesSorted.count == 1 && viewModel.selectedColumnIndex != nil))
                            Divider()
                            Button("Copy Selected Rows (TSV)") { copySelectedRowsTSV(includeHeaders: false) }
                                .disabled(selectedRowIndicesSorted.isEmpty)
                            Button("Copy Selected Rows (TSV with Headers)") { copySelectedRowsTSV(includeHeaders: true) }
                                .disabled(selectedRowIndicesSorted.isEmpty || viewModel.headers.isEmpty)
                            Button("Copy Selected Rows (JSON)") { copySelectedRowsJSON() }
                                .disabled(selectedRowIndicesSorted.isEmpty || viewModel.headers.isEmpty)
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
                              columns: viewModel.allColumns,
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
	                        
	                        if viewModel.canEstimateAffectedRows(sql: viewModel.sqlEditorText),
	                           viewModel.connection.type != .clickhouse {
	                            Button(action: {
	                                guard !isEstimatingMutation else { return }
	                                isEstimatingMutation = true
	                                let sql = viewModel.sqlEditorText
	                                Task {
	                                    do {
	                                        if let cnt = try await viewModel.estimateAffectedRows(sql: sql) {
	                                            ToastManager.shared.show(message: "Estimated affected rows: \(cnt)", type: .info)
	                                        } else {
	                                            ToastManager.shared.show(message: "Cannot estimate affected rows", type: .warning)
	                                        }
	                                    } catch {
	                                        ToastManager.shared.show(message: "Estimate failed: \(error.localizedDescription)", type: .error)
	                                    }
	                                    await MainActor.run { isEstimatingMutation = false }
	                                }
	                            }) {
	                                HStack {
	                                    Image(systemName: "magnifyingglass")
	                                    Text(isEstimatingMutation ? "Estimating…" : "Estimate")
	                                }
	                                .padding(.horizontal, 12)
	                                .padding(.vertical, 8)
	                                .background(DesignSystem.Colors.surfaceSecondary.opacity(0.8))
	                                .foregroundColor(DesignSystem.Colors.text)
	                                .cornerRadius(20)
	                                .shadow(radius: 2)
	                            }
	                            .buttonStyle(.plain)
	                        }

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
                                    DataRow(
                                        rowIndex: idx,
                                        rowData: viewModel.rows[idx],
                                        viewModel: viewModel,
                                        onEditCell: { rowIndex, colIndex in
                                            guard viewModel.rows.indices.contains(rowIndex),
                                                  viewModel.rows[rowIndex].indices.contains(colIndex) else { return }
                                            if viewModel.connection.type == .clickhouse {
                                                ToastManager.shared.show(message: "ClickHouse does not support UPDATE", type: .warning)
                                                return
                                            }
                                            if viewModel.primaryKeyColumns.isEmpty {
                                                ToastManager.shared.show(message: "No primary key, editing disabled", type: .warning)
                                                return
                                            }
                                            editCellTarget = EditCellTarget(
                                                rowIndex: rowIndex,
                                                columnIndex: colIndex,
                                                originalValue: viewModel.rows[rowIndex][colIndex]
                                            )
                                        }
                                    )
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                    .focusable(true)
                    .focused($isDataGridFocused)
                    .sshtools_disableFocusRing()
                    .onTapGesture { isDataGridFocused = true }
                    .onCopyCommand { copyGridSelectionProviders() }
                    .onExitCommand { viewModel.clearSelection() }
                    .contextMenu {
                        Button("Copy Cell") { copySelectedCellIfAny() }
                            .disabled(!(selectedRowIndicesSorted.count == 1 && viewModel.selectedColumnIndex != nil))
                        Divider()
                        Button("Copy Selected Rows (TSV)") { copySelectedRowsTSV(includeHeaders: false) }
                            .disabled(selectedRowIndicesSorted.isEmpty)
                        Button("Copy Selected Rows (TSV with Headers)") { copySelectedRowsTSV(includeHeaders: true) }
                            .disabled(selectedRowIndicesSorted.isEmpty || viewModel.headers.isEmpty)
                        Button("Copy Selected Rows (JSON)") { copySelectedRowsJSON() }
                            .disabled(selectedRowIndicesSorted.isEmpty || viewModel.headers.isEmpty)
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
                    },
                    sortDirection: viewModel.sortColumnName == header ? viewModel.sortDirection : nil,
                    onToggleSort: {
                        viewModel.toggleSort(columnName: header)
                    },
                    isSelectedColumn: viewModel.selectedColumnIndex == index,
                    onSelectColumn: {
                        viewModel.selectColumn(index: index)
                        isDataGridFocused = true
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
                    Text(viewModel.databaseProductName == "ClickHouse" ? "ClickHouse Dashboard".localized : "MySQL Dashboard".localized)
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
