import SwiftUI

// MARK: - 左侧树形目录
private struct SFTPTreeSidebar: View {
    @ObservedObject var viewModel: SyncedSFTPViewModel
    let currentPath: String
    let onNavigate: (String) -> Void
    
    @State private var expandedPaths: Set<String> = ["/"]
    @State private var loadedChildren: [String: [String]] = [:]
    @State private var loadingPath: String?
    
    private let minWidth: CGFloat = 160
    private let maxWidth: CGFloat = 320
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                treeRow(path: "/", name: "/", depth: 0)
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth)
        .background(DesignSystem.Colors.surface.opacity(0.6))
        .onAppear {
            if loadedChildren["/"] == nil {
                loadChildren(path: "/")
            }
        }
    }
    
    private func treeRow(path: String, name: String, depth: Int) -> AnyView {
        let children = loadedChildren[path] ?? []
        let isExpanded = expandedPaths.contains(path)
        let isLoading = loadingPath == path
        let isSelected = normalizedCurrentPath == path || (path != "/" && normalizedCurrentPath.hasPrefix(path + "/"))
        
        return AnyView(
            Group {
                Button {
                    onNavigate(path)
                } label: {
                    HStack(spacing: 4) {
                        ForEach(0..<depth, id: \.self) { _ in
                            Color.clear.frame(width: 12, height: 1)
                        }
                        if children.isEmpty && !isLoading {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.blue)
                                .frame(width: 16, height: 16)
                        } else {
                            Button {
                                toggleExpand(path: path)
                            } label: {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.blue)
                                .frame(width: 16, height: 16)
                        }
                        if isLoading {
                            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        }
                        Text(name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? DesignSystem.Colors.blue : DesignSystem.Colors.text)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? DesignSystem.Colors.itemSelected : Color.clear)
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    ForEach(children, id: \.self) { childName in
                        let childPath = path == "/" ? "/" + childName : path + "/" + childName
                        treeRow(path: childPath, name: childName, depth: depth + 1)
                    }
                }
            }
        )
    }
    
    private var normalizedCurrentPath: String {
        let p = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "/" }
        return p.hasSuffix("/") ? String(p.dropLast()) : p
    }
    
    private func toggleExpand(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            if loadedChildren[path] == nil {
                loadChildren(path: path)
            }
        }
    }
    
    private func loadChildren(path: String) {
        loadingPath = path
        Task {
            let names = await viewModel.listSubdirectories(at: path)
            await MainActor.run {
                loadedChildren[path] = names
                loadingPath = nil
            }
        }
    }
}

private struct SFTPTreeResizer: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var dragStartWidth: CGFloat = 0
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.8))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartWidth == 0 { dragStartWidth = width }
                            let proposed = dragStartWidth + value.translation.width
                            width = min(max(proposed, minWidth), maxWidth)
                        }
                        .onEnded { _ in
                            dragStartWidth = 0
                        }
                )
        }
    }
}

struct SyncedSFTPView: View {
    let runner: SSHRunner
    let connectionID: UUID
    @Binding var path: String
    @Binding var isExpanded: Bool // New binding for expansion state
    let onNavigate: (String) -> Void
    
    @StateObject private var viewModel: SyncedSFTPViewModel
    @State private var editedPath: String = ""
    @State private var isShowingTasks = false // Use local state for popover
    @State private var isShowingSavedTasks = false
    @State private var treeWidth: CGFloat = 200
    @ObservedObject private var transferManager = TransferManager.shared
    
    init(runner: SSHRunner, connectionID: UUID, path: Binding<String>, isExpanded: Binding<Bool>, onNavigate: @escaping (String) -> Void) {
        self.runner = runner
        self.connectionID = connectionID
        self._path = path
        self._isExpanded = isExpanded
        self.onNavigate = onNavigate
        let initialPath = {
            let val = path.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty { return val }
            let key = "sshtools.sftp.lastPath.\(connectionID.uuidString)"
            if let stored = UserDefaults.standard.string(forKey: key),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "/"
        }()
        _viewModel = StateObject(wrappedValue: SyncedSFTPViewModelStore.shared.viewModel(
            runner: runner,
            initialPath: initialPath,
            onNavigate: onNavigate
        ))
        _editedPath = State(initialValue: initialPath)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Path and Control Bar
            HStack(spacing: 8) {
                TextField("Path".localized, text: $editedPath, onCommit: {
                    viewModel.navigate(to: editedPath)
                })
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.monospace)
                .foregroundColor(DesignSystem.Colors.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(6)
                .frame(maxWidth: .infinity)
                
                HStack(spacing: 10) {
                    // Search/Filter
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Filter".localized, text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 80)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(6)
                    
                    // Transfer Tasks Button
                    Button(action: { isShowingTasks.toggle() }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 13))
                                .foregroundColor(transferManager.tasks.isEmpty ? .secondary : .blue)
                            
                            if !transferManager.tasks.isEmpty {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $isShowingTasks) {
                        TransferListView()
                    }
                    .help("Transfer Tasks".localized)

                    Button(action: { isShowingSavedTasks.toggle() }) {
                        Image(systemName: "pin.circle")
                            .font(.system(size: 13))
                            .foregroundColor(transferManager.savedTasks(for: connectionID).isEmpty ? .secondary : .blue)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $isShowingSavedTasks) {
                        SavedUploadTasksView(connectionID: connectionID, runner: runner)
                    }
                    .help("Saved Uploads".localized)
                    
                    // Show Hidden Toggle
                    Button(action: { viewModel.showHiddenFiles.toggle() }) {
                        Image(systemName: viewModel.showHiddenFiles ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.showHiddenFiles ? .blue : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Show Hidden Files".localized)

                    if viewModel.isLoading {
                        ProgressView().scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    }
                    
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    
                    // Collapse/Expand Button
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Collapse".localized : "Expand".localized)
                }
                .frame(height: 26)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: 40)
            .background(DesignSystem.Colors.surface)
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                Spacer()
            } else {
                HStack(spacing: 0) {
                    SFTPTreeSidebar(viewModel: viewModel, currentPath: viewModel.path, onNavigate: { viewModel.navigate(to: $0) })
                        .frame(width: treeWidth)
                    
                    SFTPTreeResizer(width: $treeWidth, minWidth: 160, maxWidth: 320)
                    
                    SFTPTableView(viewModel: viewModel, onNavigate: onNavigate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $viewModel.isEditorOpen) {
            if let file = viewModel.activeEditorFile {
                FileEditorSheet(
                    fileName: file.name,
                    content: viewModel.activeEditorContent,
                    onSave: { newContent in
                        viewModel.saveFileContent(newContent)
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.isRenameOpen) {
            if let file = viewModel.activeRenameFile {
                RenameSheet(
                    currentName: file.name,
                    onRename: { newName in
                        viewModel.renameFile(file, to: newName)
                    }
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // Handle file drops
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            viewModel.uploadFile(from: url)
                        }
                    }
                }
            }
            return true
        }
        .onChange(of: viewModel.path) { oldValue, newPath in
            if self.path != newPath {
                self.path = newPath
            }
            if self.editedPath != newPath {
                self.editedPath = newPath
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        .onReceive(transferManager.$isShowingTasks) { newValue in
            if newValue {
                isShowingTasks = true
                // Reset it in manager so subsequent tasks can trigger it again
                transferManager.isShowingTasks = false
            }
        }
    }
}

/// A standalone wrapper for SyncedSFTPView to be used in its own tab
struct StandaloneSFTPView: View {
    let connection: SSHConnection
    @StateObject private var runner = SSHRunner()
    @State private var path: String = ""
    @State private var isExpanded = true
    
    var body: some View {
        SyncedSFTPView(
            runner: runner,
            connectionID: connection.id,
            path: $path,
            isExpanded: $isExpanded,
            onNavigate: { newPath in
                path = newPath
            }
        )
        .onAppear {
            runner.connect(connection: connection)
        }
        .background(DesignSystem.Colors.background)
    }
}

struct FileRowView: View {
    @ObservedObject var file: RemoteFile
    let path: String
    let isSelected: Bool
    let selectionCount: Int
    let onDownload: () -> Void
    let onEdit: (String) -> Void
    let onNavigate: (String) -> Void
    let onRename: (String) -> Void
    let onShowRename: () -> Void
    let onDownloadSelected: () -> Void
    let onDeleteSelected: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(file.isDirectory ? DesignSystem.Colors.blue : (isSelected ? .white : DesignSystem.Colors.text))
                .frame(width: 16)
            
            Text(file.name)
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isSelected ? .white : .primary)
            
            Group {
                Text(file.permissions)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 85, alignment: .leading)
                
                Text("\(file.owner):\(file.group)")
                    .font(.system(size: 11))
                    .frame(width: 80, alignment: .leading)
                
                Text(file.size)
                    .font(.system(size: 11))
                    .frame(width: 70, alignment: .trailing)
                
                Text(file.date)
                    .font(.system(size: 11))
                    .frame(width: 120, alignment: .trailing)
            }
            .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            
            HStack(spacing: 8) {
                // Status Indicators only
                switch file.downloadStatus {
                case .transferring:
                    if let progress = file.downloadProgress {
                        DownloadIndicator(progress: progress)
                    }
                case .queuing:
                    ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
                case .paused:
                    Image(systemName: "pause.circle.fill").foregroundColor(.orange)
                case .cancelled:
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                case .failed(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                        .help(msg)
                case .completed:
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                case .none:
                    EmptyView()
                }
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let fullPath = path.hasSuffix("/") ? path + file.name : path + "/" + file.name
            if file.isDirectory {
                onNavigate(fullPath)
            }
            // Double-click to edit removed as per user request
        }
        .contextMenu {
            if selectionCount > 1 {
                Button(action: onDownloadSelected) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                
                Button(role: .destructive, action: onDeleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(action: onShowRename) {
                    Label("Rename", systemImage: "pencil.and.outline")
                }
                
                Button(action: {
                    let fullPath = path.hasSuffix("/") ? path + file.name : path + "/" + file.name
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(fullPath, forType: .string)
                    ToastManager.shared.show(message: "Path copied".localized, type: .success)
                }) {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                
                if !file.isDirectory {
                    Button(action: { onEdit(path.hasSuffix("/") ? path + file.name : path + "/" + file.name) }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }
}

struct DownloadIndicator: View {
    let progress: Double
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 60)
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .frame(height: 10)
    }
}

struct SortIndicator: View {
    let field: SyncedSFTPViewModel.SortField
    let currentField: SyncedSFTPViewModel.SortField
    let ascending: Bool
    
    var body: some View {
        if field == currentField {
            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.blue)
        } else {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.3))
        }
    }
}
