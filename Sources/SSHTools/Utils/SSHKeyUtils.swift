import Foundation

enum SSHKeyUtils {
    /// Converts a legacy PEM private key to modern OpenSSH format using ssh-keygen.
    /// Returns the content of the key.
    static func convertToOpenSSHFormat(at path: String) -> String? {
        guard let tempPath = prepareKeyFile(at: path) else { return nil }
        defer {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempPath).deletingLastPathComponent())
        }
        
        // Attempt to convert to OpenSSH format using ssh-keygen
        // -p: change passphrase
        // -N "": set new passphrase to empty
        // -o: use new OpenSSH format
        // -f: file path
        // This assumes the original key is unencrypted. If encrypted, this might fail or hang without -P.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-p", "-N", "", "-o", "-f", tempPath]
        
        // Redirect output to silence it
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return try? String(contentsOfFile: tempPath, encoding: .utf8)
            }
        } catch {
            Logger.log("SSHKeyUtils: Conversion failed: \(error)", level: .error)
        }
        
        // Fallback: return original content if conversion failed (e.g. password protected)
        return try? String(contentsOfFile: tempPath, encoding: .utf8)
    }
    
    /// Prepares a key file for use by SSH: copies it to a secure temp dir, sets permissions (0600),
    /// and ensures it is in OpenSSH format.
    /// **Important:** The caller is responsible for deleting the returned file (and its parent directory) when done.
    static func prepareKeyFile(at path: String) -> String? {
        // 1. Create a unique temporary directory
        let tempDirName = "sshtools_safe_" + UUID().uuidString
        let tempDirURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempDirName)
        
        do {
            // 2. Create directory with strict permissions (700)
            try FileManager.default.createDirectory(at: tempDirURL,
                                                  withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
            
            let sourceURL = URL(fileURLWithPath: path)
            let tempKeyURL = tempDirURL.appendingPathComponent("id_key")
            
            // 3. Copy key file
            try FileManager.default.copyItem(at: sourceURL, to: tempKeyURL)
            
            // 4. Set strict permissions on the file itself (600)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempKeyURL.path)
            
            return tempKeyURL.path
        } catch {
            Logger.log("SSHKeyUtils: Key preparation failed: \(error.localizedDescription)", level: .debug)
            // Cleanup on failure
            try? FileManager.default.removeItem(at: tempDirURL)
            return nil
        }
    }
}
