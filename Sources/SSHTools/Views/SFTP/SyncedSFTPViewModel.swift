import Foundation
import SwiftUI
import Combine
import Citadel
import NIO

class SyncedSFTPViewModel: ObservableObject {
    let runner: SSHRunner
    let onNavigate: (String) -> Void
    
    enum SortField {
        case name, size, date
    }
    
    @Published var path: String
    @Published var files: [RemoteFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sortField: SortField = .name
    @Published var sortAscending: Bool = true
    @Published var selectedFileIds = Set<UUID>()
    @Published var showHiddenFiles = false
    @Published var searchText = ""
    
    // Editor State
    @Published var activeEditorFile: RemoteFile?
    @Published var activeEditorContent: String = ""
    @Published var isEditorOpen: Bool = false
    
    // Rename State
    @Published var activeRenameFile: RemoteFile?
    @Published var isRenameOpen: Bool = false
    
    private var rawFiles: [RemoteFile] = []
    private var cancellables = Set<AnyCancellable>()
    
    init(runner: SSHRunner, path: String, onNavigate: @escaping (String) -> Void) {
        self.runner = runner
        self.path = path.isEmpty ? "/" : path
        self.onNavigate = onNavigate
        
        // Observe SFTP connection
        runner.$sftp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sftp in
                if sftp != nil {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
            
        // Observe current path changes from the runner (Terminal)
        runner.$currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPath in
                guard let self = self else { return }
                let cleanPath = newPath.isEmpty ? "/" : newPath
                if self.path != cleanPath {
                    Logger.log("SFTP: Syncing path from terminal: \(cleanPath)", level: .info)
                    self.path = cleanPath
                    self.refresh()
                }
            }
            .store(in: &cancellables)
            
        // Observe UI filters
        Publishers.CombineLatest($showHiddenFiles, $searchText)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFiltersAndSort()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        // We don't disconnect the runner here because it's shared with terminal in this context,
        // but if it were a standalone SFTP tab, we would.
        // However, we should release the reference count if it was incremented.
        // For now, TerminalView handles the primary runner lifecycle.
    }
    
    func toggleSort(field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
        applyFiltersAndSort()
    }
    
    private func applyFiltersAndSort() {
        var filtered = rawFiles
        
        // 1. Filter hidden files
        if !showHiddenFiles {
            filtered = filtered.filter { !$0.name.hasPrefix(".") }
        }
        
        // 2. Filter search text
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // 3. Sort
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            
            let result: Bool
            switch sortField {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                result = lhs.size.localizedStandardCompare(rhs.size) == .orderedAscending
            case .date:
                result = lhs.date.localizedStandardCompare(rhs.date) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
        
        self.files = sorted
    }
    
    func refresh() {
        guard let sftp = runner.sftp else {
            errorMessage = "SFTP not connected"
            return
        }
        
        isLoading = true
        errorMessage = nil
        selectedFileIds.removeAll()
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let mappedFiles = try await SFTPService.shared.listDirectory(sftp: sftp, at: self.path)
                await MainActor.run {
                    self.rawFiles = mappedFiles
                    self.applyFiltersAndSort()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to list files: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func deleteSelectedFiles() {
        guard let sftp = runner.sftp, !selectedFileIds.isEmpty else { return }
        
        let filesToDelete = rawFiles.filter { selectedFileIds.contains($0.id) }
        
        Task { [weak self] in
            guard let self = self else { return }
            var successCount = 0
            for file in filesToDelete {
                do {
                    let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
                    try await SFTPService.shared.deleteFile(sftp: sftp, at: remotePath, isDirectory: file.isDirectory)
                    successCount += 1
                } catch {
                    Logger.log("Failed to delete \(file.name): \(error)", level: .error)
                }
            }
            
            await MainActor.run {
                if successCount > 0 {
                    ToastManager.shared.show(message: "Deleted \(successCount) items", type: .success)
                    self.refresh()
                }
            }
        }
    }
    
    func downloadSelectedFiles() {
        guard let sftp = runner.sftp, !selectedFileIds.isEmpty else { return }
        
        let filesToDownload = rawFiles.filter { selectedFileIds.contains($0.id) && !$0.isDirectory }
        guard !filesToDownload.isEmpty else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Download Directory"
        
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task { [weak self] in
                guard let self = self else { return }
                for file in filesToDownload {
                    let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
                    let localURL = targetURL.appendingPathComponent(file.name)
                    try? await SFTPService.shared.download(sftp: sftp, remotePath: remotePath, fileName: file.name, to: localURL)
                }
                await MainActor.run {
                    ToastManager.shared.show(message: "Started downloading \(filesToDownload.count) files", type: .success)
                }
            }
        }
    }
    
    func download(file: RemoteFile) {
        guard let sftp = runner.sftp else { return }
        
        let defaultPath = SettingsManager.shared.defaultDownloadPath
        var localURL: URL? = nil
        
        if !defaultPath.isEmpty {
            localURL = URL(fileURLWithPath: defaultPath).appendingPathComponent(file.name)
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            if panel.runModal() == .OK {
                localURL = panel.url
            }
        }
        
        if let targetURL = localURL {
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
            Task {
                do {
                    try await SFTPService.shared.download(sftp: sftp, remotePath: remotePath, fileName: file.name, to: targetURL)
                } catch {
                    Logger.log("Download failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    func uploadFile(from localURL: URL) {
        guard let sftp = runner.sftp else { return }
        let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + localURL.lastPathComponent
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await SFTPService.shared.upload(sftp: sftp, localURL: localURL, remotePath: remotePath)
                await MainActor.run { self.refresh() }
            } catch {
                Logger.log("Upload failed: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    func editFile(_ file: RemoteFile) {
        if file.rawSize > 5 * 1024 * 1024 {
            ToastManager.shared.show(message: "File too large to edit (> 5MB)".localized, type: .error)
            return
        }
        
        guard let sftp = runner.sftp else { return }
        isLoading = true
        
        Task { [weak self] in
            guard let self = self else { return }
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
            do {
                let content = try await SFTPService.shared.readFile(sftp: sftp, at: remotePath)
                await MainActor.run {
                    self.activeEditorFile = file
                    self.activeEditorContent = content
                    self.isEditorOpen = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to read file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func saveFileContent(_ content: String) {
        guard let sftp = runner.sftp, let file = activeEditorFile else { return }
        
        Task { [weak self] in
            guard let self = self else { return }
            let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
            do {
                try await SFTPService.shared.writeFile(sftp: sftp, at: remotePath, content: content)
                await MainActor.run {
                    ToastManager.shared.show(message: "Saved \(file.name)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Failed to save: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    func renameFile(_ file: RemoteFile, to newName: String) {
        guard let sftp = runner.sftp else { return }
        let oldPath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
        let newPath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + newName
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await SFTPService.shared.rename(sftp: sftp, oldPath: oldPath, newPath: newPath)
                await MainActor.run {
                    ToastManager.shared.show(message: "Renamed to \(newName)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Rename failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    func deleteFile(_ file: RemoteFile) {
        guard let sftp = runner.sftp else { return }
        let remotePath = (self.path.hasSuffix("/") ? self.path : self.path + "/") + file.name
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await SFTPService.shared.deleteFile(sftp: sftp, at: remotePath, isDirectory: file.isDirectory)
                await MainActor.run {
                    ToastManager.shared.show(message: "Deleted \(file.name)", type: .success)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: "Delete failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
}
