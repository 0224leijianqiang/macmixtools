import SwiftUI
import CryptoKit
import AppKit

enum ToolboxTool: String, CaseIterable, Identifiable {
    case json = "JSON Formatter"
    case jsonDiff = "JSON Diff"
    case base64 = "Base64 Encoder"
    case url = "URL Encoder"
    case hash = "Hash Generator"
    case timestamp = "Unix Timestamp"
    case jwt = "JWT Parser"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .json: return "curlybraces"
        case .jsonDiff: return "arrow.left.and.right.square"
        case .base64: return "number.square"
        case .url: return "link"
        case .hash: return "lock.shield"
        case .timestamp: return "clock"
        case .jwt: return "key.horizontal"
        }
    }
}

struct DevToolboxView: View {
    @State private var selectedTool: ToolboxTool = .json
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Tool Workspace (Top - Expanding)
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: selectedTool.icon)
                        .foregroundColor(.blue)
                    Text(selectedTool.rawValue.localized)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .frame(height: 44)
                .background(DesignSystem.Colors.surface)
                
                Divider()
                
                // Content fills the space
                ZStack {
                    toolWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(DesignSystem.Colors.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Push content to fill space
            
            Divider()
            
            // 2. Toolbar Menu (Bottom)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ToolboxTool.allCases) { tool in
                        Button(action: { selectedTool = tool }) {
                            VStack(spacing: 4) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 16))
                                Text(tool.rawValue.localized)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .frame(minWidth: 80) // Ensure a consistent minimum width
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle()) // IMPORTANT: Make entire frame clickable
                            .background(selectedTool == tool ? Color.blue.opacity(0.15) : Color.clear)
                            .foregroundColor(selectedTool == tool ? .blue : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(DesignSystem.Colors.surface)
            .frame(height: 60)
        }
    }
    
    @ViewBuilder
    private var toolWorkspace: some View {
        switch selectedTool {
        case .json: JSONFormatterTool()
        case .jsonDiff: JSONDiffTool()
        case .base64: Base64Tool()
        case .url: URLEncoderTool()
        case .hash: HashTool()
        case .timestamp: TimestampTool()
        case .jwt: JWTTool()
        }
    }
}

// Sub tools move here but the specific logic for JSONDiff is in JSONDiffEditor.swift
// Keep the sub-tool implementations from previous turn...
struct JSONFormatterTool: View {
    @State private var input = ""
    @State private var output = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input JSON").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150, maxHeight: .infinity)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            
            HStack {
                Button("Format") { format() }.buttonStyle(ModernButtonStyle())
                Button("Compact") { compact() }.buttonStyle(ModernButtonStyle(variant: .secondary))
                Spacer()
                Button("Copy Output") { copyToClipboard(output) }.buttonStyle(.link)
            }
            
            Text("Result").font(.caption).foregroundColor(.secondary)
            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .frame(minHeight: 150, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
        .padding()
    }
    
    private func format() {
        guard let data = input.data(using: .utf8) else { return }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            output = String(data: pretty, encoding: .utf8) ?? ""
        }
    }
    
    private func compact() {
        guard let data = input.data(using: .utf8) else { return }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let compact = try? JSONSerialization.data(withJSONObject: json, options: []) {
            output = String(data: compact, encoding: .utf8) ?? ""
        }
    }
}

struct Base64Tool: View {
    @State private var input = ""
    @State private var output = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $input)
                .frame(minHeight: 100, maxHeight: .infinity)
                .cornerRadius(4)
            
            HStack {
                Button("Encode") { output = Data(input.utf8).base64EncodedString() }.buttonStyle(ModernButtonStyle())
                Button("Decode") {
                    if let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        output = String(data: data, encoding: .utf8) ?? "Invalid UTF8"
                    } else {
                        output = "Invalid Base64"
                    }
                }.buttonStyle(ModernButtonStyle(variant: .secondary))
            }
            
            Text("Output").font(.caption).foregroundColor(.secondary)
            TextEditor(text: .constant(output))
                .frame(minHeight: 100, maxHeight: .infinity)
                .cornerRadius(4)
        }
        .padding()
    }
}

struct TimestampTool: View {
    @State private var timestamp = String(Int(Date().timeIntervalSince1970))
    @State private var dateString = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Section(header: Text("Timestamp to Date").bold()) {
                HStack {
                    TextField("Unix Timestamp", text: $timestamp)
                        .textFieldStyle(ModernTextFieldStyle())
                    Button("Convert") {
                        if let t = Double(timestamp) {
                            let date = Date(timeIntervalSince1970: t)
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            dateString = formatter.string(from: date)
                        }
                    }
                    .buttonStyle(ModernButtonStyle())
                }
                Text(dateString).font(.title3).foregroundColor(.blue)
            }
            
            Divider()
            
            Button("Now: \(Int(Date().timeIntervalSince1970))") {
                timestamp = String(Int(Date().timeIntervalSince1970))
            }.buttonStyle(.link)
            
            Spacer()
        }
        .padding()
    }
}

struct HashTool: View {
    @State private var input = ""
    @State private var md5 = ""
    @State private var sha256 = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $input)
                .frame(minHeight: 100, maxHeight: 200)
                .cornerRadius(4)
                .onChange(of: input) { oldValue, newValue in calculate(newValue) }
            
            labeledResult("MD5", value: md5)
            labeledResult("SHA256", value: sha256)
            Spacer()
        }
        .padding()
    }
    
    private func labeledResult(_ label: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            HStack {
                Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(action: { copyToClipboard(value) }) {
                    Image(systemName: "doc.on.doc")
                }.buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.black.opacity(0.05))
            .cornerRadius(4)
        }
    }
    
    private func calculate(_ newValue: String) {
        let data = Data(newValue.utf8)
        let md5Digest = Insecure.MD5.hash(data: data)
        md5 = md5Digest.map { String(format: "%02hhx", $0) }.joined()
        
        let shaDigest = SHA256.hash(data: data)
        sha256 = shaDigest.map { String(format: "%02hhx", $0) }.joined()
    }
}

struct URLEncoderTool: View { var body: some View { VStack { Text("URL Tool Pending"); Spacer() }.padding() } }
struct JWTTool: View { var body: some View { VStack { Text("JWT Tool Pending"); Spacer() }.padding() } }

func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    ToastManager.shared.show(message: "Copied to clipboard", type: .success)
}
