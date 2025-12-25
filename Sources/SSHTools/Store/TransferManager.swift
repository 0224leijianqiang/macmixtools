import Foundation
import SwiftUI

/// Centralized manager for file upload and download tasks
class TransferManager: ObservableObject {
    static let shared = TransferManager()
    
    @Published var tasks: [TransferTask] = []
    @Published var isShowingTasks = false
    
    private init() {}
    
    func addTask(_ task: TransferTask) {
        DispatchQueue.main.async {
            self.tasks.insert(task, at: 0)
            self.isShowingTasks = true
        }
    }
    
    func updateTask(id: UUID, progress: Double, transferredSize: Int64, status: DownloadStatus? = nil) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].progress = progress
                self.tasks[index].transferredSize = transferredSize
                if let status = status {
                    self.tasks[index].status = status
                } else if self.tasks[index].status == .queuing {
                    self.tasks[index].status = .transferring
                }
            }
        }
    }
    
    func completeTask(id: UUID) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .completed
                self.tasks[index].progress = 1.0
            }
        }
    }
    
    func failTask(id: UUID, message: String) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[index].status = .failed(message)
            }
        }
    }
    
    func clearCompleted() {
        tasks.removeAll { task in
            if case .completed = task.status { return true }
            if case .failed = task.status { return true }
            return false
        }
    }
}

struct TransferListView: View {
    @ObservedObject var manager = TransferManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfer Tasks".localized)
                    .font(.headline)
                Spacer()
                Button("Clear Finished".localized) {
                    manager.clearCompleted()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            if manager.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("No active tasks".localized)
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.tasks) { task in
                        TransferTaskRow(task: task)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 350, height: 450)
        .background(DesignSystem.Colors.background)
    }
}

struct TransferTaskRow: View {
    let task: TransferTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: task.type == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(task.type == .download ? .blue : .green)
                Text(task.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                statusIcon
            }
            
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .accentColor(progressColor)
            
            HStack {
                Text(sizeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(percentString)
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .transferring:
            ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
        default:
            EmptyView()
        }
    }
    
    private var progressColor: Color {
        switch task.status {
        case .failed: return .red
        case .completed: return .green
        default: return .blue
        }
    }
    
    private var sizeString: String {
        let current = ByteCountFormatter.string(fromByteCount: task.transferredSize, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: task.totalSize, countStyle: .file)
        return "\(current) / \(total)"
    }
    
    private var percentString: String {
        String(format: "%.0f%%", task.progress * 100)
    }
}
