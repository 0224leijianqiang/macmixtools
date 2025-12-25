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
        TransferManager.shared.addTask(task)
        
        // 3. Prepare Local File
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        let localHandle = try FileHandle(forWritingTo: targetURL)
        defer { try? localHandle.close() }
        
        // 4. Open Remote Handle
        let handle = try await sftp.openFile(filePath: remotePath, flags: .read)
        defer { 
            Task { try? await handle.close() }
        }
        
        // 5. Optimized Concurrent Pipelined Download
        let chunkSize: UInt32 = 128 * 1024 
        let pipelineDepth = 12 // Increased depth
        var bytesRead: Int64 = 0
        var writeOffset: UInt64 = 0
        var chunkBuffer: [UInt64: Data] = [:] // Buffer for out-of-order chunks
        
        try await withThrowingTaskGroup(of: (UInt64, Data).self) { group in
            var fetchOffset: UInt64 = 0
            
            // Initial pipeline fill
            for _ in 0..<pipelineDepth {
                if fetchOffset < UInt64(totalSize) {
                    let currentOffset = fetchOffset
                    let length = min(UInt32(totalSize - Int64(currentOffset)), chunkSize)
                    group.addTask {
                        let buffer = try await handle.read(from: currentOffset, length: length)
                        return (currentOffset, buffer.getData(at: 0, length: buffer.readableBytes) ?? Data())
                    }
                    fetchOffset += UInt64(length)
                }
            }
            
            // Process chunks
            while bytesRead < totalSize {
                guard let (chunkOffset, data) = try await group.next() else { break }
                
                chunkBuffer[chunkOffset] = data
                
                // Write any contiguous chunks starting from writeOffset
                while let nextData = chunkBuffer[writeOffset] {
                    try localHandle.seek(toOffset: writeOffset)
                    localHandle.write(nextData)
                    bytesRead += Int64(nextData.count)
                    writeOffset += UInt64(nextData.count)
                    chunkBuffer.removeValue(forKey: writeOffset - UInt64(nextData.count))
                    
                    let progress = totalSize > 0 ? Double(bytesRead) / Double(totalSize) : 0
                    TransferManager.shared.updateTask(id: taskID, progress: progress, transferredSize: bytesRead)
                }
                
                // Keep pipeline full
                if fetchOffset < UInt64(totalSize) {
                    let currentOffset = fetchOffset
                    let length = min(UInt32(totalSize - Int64(currentOffset)), chunkSize)
                    group.addTask {
                        let buffer = try await handle.read(from: currentOffset, length: length)
                        return (currentOffset, buffer.getData(at: 0, length: buffer.readableBytes) ?? Data())
                    }
                    fetchOffset += UInt64(length)
                }
            }
        }
        
        TransferManager.shared.completeTask(id: taskID)
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
        TransferManager.shared.addTask(task)
        
        // Open local file for reading
        let localHandle = try FileHandle(forReadingFrom: localURL)
        defer { try? localHandle.close() }
        
        // Open remote file for writing
        let handle = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        defer { Task { try? await handle.close() } }
        
        // Optimized Concurrent Pipelined Upload
        let chunkSize = 128 * 1024 
        let pipelineDepth = 12
        var bytesWritten: Int64 = 0
        
        try await withThrowingTaskGroup(of: Int64.self) { group in
            var readOffset: UInt64 = 0
            
            // Initial fill
            for _ in 0..<pipelineDepth {
                if let data = try localHandle.read(upToCount: chunkSize), !data.isEmpty {
                    let currentOffset = readOffset
                    let buffer = ByteBuffer(data: data)
                    let count = Int64(data.count)
                    group.addTask {
                        try await handle.write(buffer, at: currentOffset)
                        return count
                    }
                    readOffset += UInt64(count)
                }
            }
            
            // Drain and refill
            while let written = try await group.next() {
                bytesWritten += written
                let progress = totalSize > 0 ? Double(bytesWritten) / Double(totalSize) : 0
                TransferManager.shared.updateTask(id: taskID, progress: progress, transferredSize: bytesWritten)
                
                if let data = try localHandle.read(upToCount: chunkSize), !data.isEmpty {
                    let currentOffset = readOffset
                    let buffer = ByteBuffer(data: data)
                    let count = Int64(data.count)
                    group.addTask {
                        try await handle.write(buffer, at: currentOffset)
                        return count
                    }
                    readOffset += UInt64(count)
                }
            }
        }
        
        try await handle.close()
        TransferManager.shared.completeTask(id: taskID)
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
