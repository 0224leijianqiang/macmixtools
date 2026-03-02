import Foundation
import Citadel
import NIO
import SwiftUI

/// Shared service for SFTP operations to avoid duplication between ViewModels
class SFTPService {
    static let shared = SFTPService()
    private init() {}
    
    /// Safely list directory, handling common SFTP EOF behavior
    func listDirectory(sftp: SFTPClient, at path: String) async throws -> [RemoteFile] {
        let messages: [SFTPMessage.Name]
        do {
            messages = try await sftp.listDirectory(atPath: path)
        } catch let status as SFTPMessage.Status {
            if status.errorCode == .eof || status.errorCode == .ok {
                messages = []
            } else {
                throw status
            }
        } catch {
            let nsError = error as NSError
            if nsError.code == 1 {
                messages = []
            } else {
                throw error
            }
        }
        
        let items = messages.flatMap { $0.components }
        return items.compactMap { item -> RemoteFile? in
            guard item.filename != "." && item.filename != ".." else { return nil }
            
            let perms = item.attributes.permissions ?? 0
            let isDir = perms & 0x4000 != 0
            let rawSize = item.attributes.size ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(rawSize), countStyle: .file)
            
            let permsString = formatPermissions(perms)
            
            let dateString: String
            if let date = item.attributes.accessModificationTime?.modificationTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                dateString = formatter.string(from: date)
            } else {
                dateString = ""
            }
            
            let owner = item.attributes.uidgid?.userId != nil ? "\(item.attributes.uidgid!.userId)" : ""
            let group = item.attributes.uidgid?.groupId != nil ? "\(item.attributes.uidgid!.groupId)" : ""
            
            return RemoteFile(name: item.filename,
                              permissions: permsString,
                              size: sizeStr,
                              rawSize: Int64(rawSize),
                              date: dateString,
                              owner: owner,
                              group: group,
                              isDirectory: isDir)
        }
    }
    
    func readFile(sftp: SFTPClient, at remotePath: String) async throws -> String {
        let handle = try await sftp.openFile(filePath: remotePath, flags: .read)
        let buffer = try await handle.readAll()
        try await handle.close()
        
        let data = Data(buffer: buffer)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func writeFile(sftp: SFTPClient, at remotePath: String, content: String) async throws {
        let handle = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        var buffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        buffer.writeString(content)
        try await handle.write(buffer)
        try await handle.close()
    }
    
    func download(sftp: SFTPClient, remotePath: String, fileName: String, to targetURL: URL) async throws {
        // 1. Get Attributes
        let attr = try await sftp.getAttributes(at: remotePath)
        let totalSize = Int64(attr.size ?? 0)
        
        // 2. Initialize Task
        let task = TransferTask(fileName: fileName, 
                                remotePath: remotePath, 
                                localPath: targetURL.path, 
                                type: .download,
                                totalSize: totalSize)
        let taskID = task.id
        let control = TransferControl()
        TransferManager.shared.addTask(task)
        TransferManager.shared.registerControl(id: taskID, control: control)
        TransferManager.shared.registerRetryHandler(id: taskID) { [weak sftp] in
            guard let sftp else { return }
            Task {
                try? await SFTPService.shared.download(sftp: sftp, remotePath: remotePath, fileName: fileName, to: targetURL)
            }
        }
        
        let start = Date()
        Logger.log("SFTP: download start remote=\(remotePath) size=\(totalSize)", level: .info)
        
        do {
            // 3. Prepare Writer
            let writer = try FileChunkWriter(url: targetURL)
            
            // Handle empty file case immediately
            if totalSize == 0 {
                try await writer.close()
                TransferManager.shared.completeTask(id: taskID)
                return
            }
            
            // 4. Concurrent Download (per-chunk handles to avoid concurrent reads on a single handle)
            let chunkSize: UInt32 = SettingsManager.shared.sftpDownloadChunkBytes
            let maxConcurrency = 4
            let progressTracker = ThreadSafeProgress(totalSize: totalSize, taskID: taskID)
            var activeTasks = 0
            
            try await withThrowingTaskGroup(of: Int64.self) { group in
                for offset in stride(from: 0, to: totalSize, by: Int(chunkSize)) {
                    try await control.waitIfPaused()
                    // Wait if we reached max concurrency
                    if activeTasks >= maxConcurrency {
                        _ = try await group.next()
                        activeTasks -= 1
                    }
                    
                    // Add new task
                    group.addTask {
                        try await control.waitIfPaused()
                        let handle = try await sftp.openFile(filePath: remotePath, flags: .read)
                        defer {
                            Task { try? await handle.close() }
                        }

                        let chunkStart = offset
                        let chunkTotal = UInt32(min(Int64(chunkSize), totalSize - chunkStart))
                        var chunkBytesRead: Int64 = 0
                        
                        while chunkBytesRead < chunkTotal {
                            try await control.waitIfPaused()
                            let currentOffset = UInt64(chunkStart + chunkBytesRead)
                            let needed = chunkTotal - UInt32(chunkBytesRead)
                            
                            let buffer = try await handle.read(from: currentOffset, length: needed)
                            let readable = buffer.readableBytes
                            
                            if readable == 0 { break } // EOF
                            
                            if let data = buffer.getData(at: 0, length: readable) {
                                try await writer.write(data: data, at: currentOffset)
                                chunkBytesRead += Int64(readable)
                                await progressTracker.addBytes(Int64(readable))
                            } else {
                                break
                            }
                        }
                        return chunkBytesRead
                    }
                    activeTasks += 1
                }
                
                // Wait for remaining tasks
                while let _ = try await group.next() {
                    activeTasks -= 1
                }
            }
            
            try await writer.close()
            
            // Final verification and completion
            let finalBytes = await progressTracker.getCurrentBytes()
            if finalBytes != totalSize {
                let msg = "Download incomplete (\(finalBytes)/\(totalSize) bytes)"
                throw NSError(domain: "SFTPService", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            
            let end = Date()
            let elapsed = max(end.timeIntervalSince(start), 0.001)
            let mbps = (Double(finalBytes) / 1024.0 / 1024.0) / elapsed
            Logger.log(String(format: "SFTP: download done %.2f MB in %.2fs (avg %.2f MB/s)", Double(finalBytes) / 1024.0 / 1024.0, elapsed, mbps), level: .info)
            
            TransferManager.shared.completeTask(id: taskID)
        } catch is CancellationError {
            TransferManager.shared.markCancelled(id: taskID)
            Logger.log("SFTP: download cancelled", level: .info)
            throw CancellationError()
        } catch {
            let msg = error.localizedDescription
            TransferManager.shared.failTask(id: taskID, message: msg)
            Logger.log("SFTP: download failed - \(msg)", level: .error)
            throw error
        }
    }

    actor ThreadSafeProgress {
        private let totalSize: Int64
        private let taskID: UUID
        private var bytesTransferred: Int64 = 0
        private var lastUpdate = Date.distantPast
        
        init(totalSize: Int64, taskID: UUID) {
            self.totalSize = totalSize
            self.taskID = taskID
        }
        
        func addBytes(_ count: Int64) {
            bytesTransferred += count
            
            let now = Date()
            // Throttle UI updates to ~10 times per second to save CPU
            if now.timeIntervalSince(lastUpdate) >= 0.1 || bytesTransferred == totalSize {
                lastUpdate = now
                let progress = totalSize > 0 ? Double(bytesTransferred) / Double(totalSize) : 0
                let currentBytes = bytesTransferred
                
                // Ensure UI update happens on Main thread
                DispatchQueue.main.async {
                    TransferManager.shared.updateTask(id: self.taskID, progress: progress, transferredSize: currentBytes)
                }
            }
        }
        
        func getCurrentBytes() -> Int64 {
            return bytesTransferred
        }
    }

    actor FileChunkWriter {
        private let handle: FileHandle
        
        init(url: URL) throws {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            self.handle = try FileHandle(forWritingTo: url)
        }
        
        func write(data: Data, at offset: UInt64) throws {
            try handle.seek(toOffset: offset)
            try handle.write(contentsOf: data)
        }
        
        func close() throws {
            try handle.close()
        }
    }
    
    func upload(sftp: SFTPClient, localURL: URL, remotePath: String) async throws {
        let fileName = localURL.lastPathComponent
        
        // Get local file size
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let totalSize = attributes[.size] as? Int64 ?? 0
        
        let task = TransferTask(fileName: fileName, 
                                remotePath: remotePath, 
                                localPath: localURL.path, 
                                type: .upload, 
                                totalSize: totalSize)
        let taskID = task.id
        let control = TransferControl()
        TransferManager.shared.addTask(task)
        TransferManager.shared.registerControl(id: taskID, control: control)
        TransferManager.shared.registerRetryHandler(id: taskID) { [weak sftp] in
            guard let sftp else { return }
            Task {
                try? await SFTPService.shared.upload(sftp: sftp, localURL: localURL, remotePath: remotePath)
            }
        }

        // Handle empty file quickly
        if totalSize == 0 {
            let handle = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
            try await handle.close()
            TransferManager.shared.completeTask(id: taskID)
            return
        }

        // Concurrent upload (per-chunk handles to avoid concurrent writes on a single handle)
        let chunkSize: Int = max(Int(SettingsManager.shared.sftpUploadChunkBytes), 256 * 1024)
        let maxConcurrency = 4
        let progressTracker = ThreadSafeProgress(totalSize: totalSize, taskID: taskID)
        var activeTasks = 0

        do {
            try await withThrowingTaskGroup(of: Int64.self) { group in
                for offset in stride(from: 0, to: totalSize, by: Int64(chunkSize)) {
                    try await control.waitIfPaused()
                    if activeTasks >= maxConcurrency {
                        _ = try await group.next()
                        activeTasks -= 1
                    }

                    group.addTask {
                        try await control.waitIfPaused()
                        let localHandle = try FileHandle(forReadingFrom: localURL)
                        defer { try? localHandle.close() }

                        let handle = try await sftp.openFile(filePath: remotePath, flags: [.write, .create])
                        defer { Task { try? await handle.close() } }

                        let chunkStart = UInt64(offset)
                        let chunkLen = min(Int64(chunkSize), totalSize - offset)

                        try localHandle.seek(toOffset: chunkStart)
                        guard let data = try localHandle.read(upToCount: Int(chunkLen)), !data.isEmpty else {
                            return 0
                        }

                        let buffer = ByteBuffer(data: data)
                        try await handle.write(buffer, at: chunkStart)
                        await progressTracker.addBytes(Int64(data.count))
                        return Int64(data.count)
                    }
                    activeTasks += 1
                }

                while let _ = try await group.next() {
                    activeTasks -= 1
                }
            }

            let finalBytes = await progressTracker.getCurrentBytes()
            if finalBytes != totalSize {
                let msg = "Upload incomplete (\(finalBytes)/\(totalSize) bytes)"
                throw NSError(domain: "SFTPService", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            TransferManager.shared.completeTask(id: taskID)
        } catch is CancellationError {
            TransferManager.shared.markCancelled(id: taskID)
            Logger.log("SFTP: upload cancelled", level: .info)
            throw CancellationError()
        } catch {
            let msg = error.localizedDescription
            TransferManager.shared.failTask(id: taskID, message: msg)
            Logger.log("SFTP: upload failed - \(msg)", level: .error)
            throw error
        }
    }
    
    func rename(sftp: SFTPClient, oldPath: String, newPath: String) async throws {
        try await sftp.rename(at: oldPath, to: newPath)
    }
    
    func deleteFile(sftp: SFTPClient, at path: String, isDirectory: Bool) async throws {
        if isDirectory {
            try await sftp.rmdir(at: path)
        } else {
            try await sftp.remove(at: path)
        }
    }
    
    private func formatPermissions(_ perms: UInt32) -> String {
        let isDir = (perms & 0x4000) != 0
        var s = isDir ? "d" : "-"
        
        let chars: [Character] = ["r", "w", "x"]
        for i in 0..<3 {
            for j in 0..<3 {
                let bit = UInt32(1) << UInt32((2 - i) * 3 + (2 - j))
                if (perms & bit) != 0 {
                    s.append(chars[j])
                } else {
                    s.append("-")
                }
            }
        }
        return s
    }
}
