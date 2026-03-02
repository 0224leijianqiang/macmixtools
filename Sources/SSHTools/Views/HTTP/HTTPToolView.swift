import SwiftUI
import Combine
import CryptoKit
import AppKit

struct HeaderItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var key: String
    var value: String
}

struct HTTPRequestHistory: Identifiable, Codable {
    var id = UUID()
    let url: String
    let method: String
    let headers: [HeaderItem]
    let body: String
    let date: Date
}

struct HTTPAISpec: Decodable {
    struct AIHeaderItem: Decodable {
        let key: String
        let value: String
    }

    let method: String?
    let url: String?
    let headers: [AIHeaderItem]
    let body: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        body = try container.decodeIfPresent(String.self, forKey: .body)

        if let arrayHeaders = try? container.decodeIfPresent([AIHeaderItem].self, forKey: .headers) {
            headers = arrayHeaders ?? []
        } else if let dictHeaders = try? container.decodeIfPresent([String: String].self, forKey: .headers) {
            headers = (dictHeaders ?? [:]).map { AIHeaderItem(key: $0.key, value: $0.value) }
        } else {
            headers = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case url
        case headers
        case body
    }
}

enum HTTPAIParseError: LocalizedError {
    case invalidJSON
    case missingURL

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "AI response is not valid JSON."
        case .missingURL:
            return "AI response did not include a URL."
        }
    }
}

class HTTPToolViewModel: ObservableObject {
    @Published var url: String = "https://httpbin.org/get" { didSet { saveDraft() } }
    @Published var method: String = "GET" { didSet { saveDraft() } }
    @Published var headers: [HeaderItem] = [] { didSet { saveDraft() } }
    @Published var body: String = "" { didSet { saveDraft() } }
    
    // Response
    @Published var responseStatus: String = ""
    @Published var statusCode: Int = 0
    @Published var responseTime: String = ""
    @Published var responseSize: String = ""
    @Published var responseBody: String = ""
    @Published var responseBodyFormatted: String = ""
    @Published var isLoading = false
    
    // History
    @Published var history: [HTTPRequestHistory] = []
    @Published var showHistory = false
    
    let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    private let historyKey = "http_request_history"
    private let draftKey = "http_request_draft"
    
    init() {
        loadHistory()
        loadDraft()
    }
    
    private func formatJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8) ?? text
        } catch {
            return text
        }
    }
    
    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HTTPRequestHistory].self, from: data) {
            history = decoded
        }
    }
    
    func loadDraft() {
        if let data = UserDefaults.standard.data(forKey: draftKey),
           let draft = try? JSONDecoder().decode(HTTPRequestHistory.self, from: data) {
            self.url = draft.url
            self.method = draft.method
            self.headers = draft.headers
            self.body = draft.body
        }
    }
    
    func saveDraft() {
        let draft = HTTPRequestHistory(url: url, method: method, headers: headers, body: body, date: Date())
        if let encoded = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(encoded, forKey: draftKey)
        }
    }

    func buildCurl() -> String {
        var parts: [String] = ["curl", "-X", method, "\"\(url)\""]
        for header in headers where !header.key.isEmpty {
            let value = header.value.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("-H \"\(header.key): \(value)\"")
        }
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("--data \"\(escaped)\"")
        }
        return parts.joined(separator: " ")
    }

    func copyRequestCommand() {
        let curl = buildCurl()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(curl, forType: .string)
        ToastManager.shared.show(message: "cURL copied", type: .success)
    }

    func copyResponse() {
        let text = responseBodyFormatted.isEmpty ? responseBody : responseBodyFormatted
        guard !text.isEmpty else {
            ToastManager.shared.show(message: "No response", type: .warning)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ToastManager.shared.show(message: "Response copied", type: .success)
    }

    func exportResponse() {
        let text = responseBodyFormatted.isEmpty ? responseBody : responseBodyFormatted
        guard !text.isEmpty else {
            ToastManager.shared.show(message: "No response", type: .warning)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "response.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                ToastManager.shared.show(message: "Response exported", type: .success)
            } catch {
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }
    
    private func computeHash(url: String, method: String, headers: [HeaderItem], body: String) -> String {
        let sortedHeaders = headers.sorted { $0.key < $1.key }
        let headerString = sortedHeaders.map { "\($0.key):\($0.value)" }.joined(separator: "|")
        let input = "\(method)|\(url)|\(headerString)|\(body)"
        let digest = Insecure.MD5.hash(data: input.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func saveHistoryItem() {
        let currentHash = computeHash(url: url, method: method, headers: headers, body: body)
        
        // Filter out existing items with same content hash
        var newHistory = history.filter { item in
            let itemHash = computeHash(url: item.url, method: item.method, headers: item.headers, body: item.body)
            return itemHash != currentHash
        }
        
        // Create new item
        let item = HTTPRequestHistory(url: url, method: method, headers: headers, body: body, date: Date())
        
        // Add to front
        newHistory.insert(item, at: 0)
        
        // Limit to 50
        if newHistory.count > 50 {
            newHistory = Array(newHistory.prefix(50))
        }
        history = newHistory
        
        // Persist
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    func restoreHistory(_ item: HTTPRequestHistory) {
        self.url = item.url
        self.method = item.method
        self.headers = item.headers
        self.body = item.body
        self.showHistory = false
    }
    
    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
    
    func sendRequest() {
        guard let requestUrl = URL(string: url) else {
            ToastManager.shared.show(message: "Invalid URL", type: .error)
            return
        }
        
        // Save to history on send
        saveHistoryItem()
        
        isLoading = true
        responseStatus = ""
        statusCode = 0
        responseBody = ""
        responseBodyFormatted = ""
        responseTime = ""
        responseSize = ""
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = method
        
        for header in headers {
            if !header.key.isEmpty {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
        }
        
        if ["POST", "PUT", "PATCH"].contains(method) {
            request.httpBody = body.data(using: .utf8)
        }
        
        let startTime = Date()
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                let duration = Date().timeIntervalSince(startTime)
                self.responseTime = String(format: "%.2fs", duration)
                
                if let error = error {
                    ToastManager.shared.show(message: error.localizedDescription, type: .error)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    self.statusCode = httpResponse.statusCode
                    self.responseStatus = "\(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                }
                
                if let data = data {
                    self.responseSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                    
                    if let str = String(data: data, encoding: .utf8) {
                        self.responseBody = str
                        self.responseBodyFormatted = self.formatJSON(str)
                    } else {
                        self.responseBody = "(Binary data)"
                        self.responseBodyFormatted = "(Binary data)"
                    }
                }
                
                // Show success/warning toast based on status code
                if self.statusCode >= 200 && self.statusCode < 300 {
                    ToastManager.shared.show(message: "Request Successful", type: .success)
                } else {
                    ToastManager.shared.show(message: "Request returned \(self.statusCode)", type: .warning)
                }
            }
        }
        task.resume()
    }
    
    func addHeader() {
        headers.append(HeaderItem(key: "", value: ""))
    }
    
    func removeHeader(at index: Int) {
        if headers.indices.contains(index) {
            headers.remove(at: index)
        }
    }

    func parseAISpec(from text: String) throws -> HTTPAISpec {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HTTPAIParseError.invalidJSON }

        let jsonText: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw HTTPAIParseError.invalidJSON
        }

        do {
            return try JSONDecoder().decode(HTTPAISpec.self, from: data)
        } catch {
            throw HTTPAIParseError.invalidJSON
        }
    }

    func applyAISpec(_ spec: HTTPAISpec) throws {
        guard let urlValue = spec.url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlValue.isEmpty else {
            throw HTTPAIParseError.missingURL
        }

        let methodValue = (spec.method ?? "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedMethod = methods.contains(methodValue) ? methodValue : "GET"

        self.url = urlValue
        self.method = normalizedMethod
        self.headers = spec.headers.map { HeaderItem(key: $0.key, value: $0.value) }
        self.body = spec.body ?? ""
    }
}

struct HTTPToolView: View {
    @StateObject private var viewModel = HTTPToolViewModel()
    @State private var requestTab = 0
    @State private var responseTab = 0
    @State private var showAIParser = false
    @State private var aiDocument = ""
    @State private var isAIParsing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Method, URL, Send
            HStack(spacing: DesignSystem.spacingSmall) {
                // History Button
                Button(action: { viewModel.showHistory.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                .popover(isPresented: $viewModel.showHistory, arrowEdge: .bottom) {
                    // ... (rest of popover)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Request History")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                viewModel.clearHistory()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                        .padding()
                        
                        Divider()
                        
                        if viewModel.history.isEmpty {
                            Text("No history")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            List(viewModel.history) { item in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(item.method)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                        Text(item.url)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Text(item.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.restoreHistory(item)
                                }
                            }
                            .frame(width: 300, height: 400)
                        }
                    }
                }

                Button(action: { showAIParser.toggle() }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                .popover(isPresented: $showAIParser, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Request Parser")
                            .font(.headline)

                        Text("Paste API docs or instructions, then let AI fill the request.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $aiDocument)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 420, height: 240)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DesignSystem.borderColor.opacity(0.6), lineWidth: 1)
                            )

                        HStack {
                            Button("Cancel") {
                                showAIParser = false
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: parseAIDocument) {
                                if isAIParsing {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Text("Parse")
                                }
                            }
                            .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                            .disabled(aiDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIParsing)
                        }
                    }
                    .padding()
                }

                Button(action: { viewModel.copyRequestCommand() }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                .help("Copy cURL")

                Button(action: { viewModel.copyResponse() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                .help("Copy response")

                Button(action: { viewModel.exportResponse() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                .help("Export response")
                
                Picker("", selection: $viewModel.method) {
                    ForEach(viewModel.methods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .frame(width: 100)
                
                TextField("Enter URL".localized, text: $viewModel.url)
                    .textFieldStyle(ModernTextFieldStyle())
                    .onSubmit { viewModel.sendRequest() }
                
                Button(action: viewModel.sendRequest) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send".localized)
                    }
                    .opacity(viewModel.isLoading ? 0 : 1)
                    .overlay {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, DesignSystem.spacingMedium)
            .frame(height: 44)
            .background(DesignSystem.surfaceColor)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DesignSystem.borderColor),
                alignment: .bottom
            )
            
            HSplitView {
                // Request Pane
                VStack(spacing: 0) {
                    Picker("", selection: $requestTab) {
                        Text("Headers".localized).tag(0)
                        Text("Body".localized).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if requestTab == 0 {
                        // Headers Editor
                        List {
                            ForEach(Array(viewModel.headers.enumerated()), id: \.element.id) { index, header in
                                HStack {
                                    TextField("Key".localized, text: Binding(
                                        get: { viewModel.headers[index].key },
                                        set: { viewModel.headers[index].key = $0 }
                                    ))
                                    .textFieldStyle(ModernTextFieldStyle())
                                    
                                    TextField("Value".localized, text: Binding(
                                        get: { viewModel.headers[index].value },
                                        set: { viewModel.headers[index].value = $0 }
                                    ))
                                    .textFieldStyle(ModernTextFieldStyle())
                                    
                                    Button(action: { viewModel.removeHeader(at: index) }) {
                                        Image(systemName: "trash.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Button(action: viewModel.addHeader) {
                                Label("Add Header".localized, systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    } else {
                        // Body Editor
                        TextEditor(text: $viewModel.body)
                            .font(.system(.body, design: .monospaced))
                            .padding(4)
                            .background(Color.white)
                    }
                }
                .frame(minWidth: 300)
                
                // Response Pane
                VStack(spacing: 0) {
                    // Status Bar
                    HStack(spacing: DesignSystem.spacingMedium) {
                        if !viewModel.responseStatus.isEmpty {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.responseStatus)
                                    .font(DesignSystem.fontCaption.bold())
                                    .foregroundColor(statusColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.1))
                            .cornerRadius(4)
                        } else {
                            Text("No response yet")
                                .font(DesignSystem.fontCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !viewModel.responseTime.isEmpty {
                            Label(viewModel.responseTime, systemImage: "timer")
                                .font(DesignSystem.fontCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !viewModel.responseSize.isEmpty {
                            Label(viewModel.responseSize, systemImage: "shippingbox")
                                .font(DesignSystem.fontCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !viewModel.responseBody.isEmpty {
                            Picker("", selection: $responseTab) {
                                Text("Pretty").tag(0)
                                Text("Raw").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                    .padding(12)
                    .background(DesignSystem.surfaceColor)
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(DesignSystem.borderColor),
                        alignment: .bottom
                    )
                    
                    if !viewModel.responseBody.isEmpty {
                        ScrollView {
                            Text(responseDisplay)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                        }
                        .background(Color.white)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text("Response will appear here")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DesignSystem.backgroundColor)
                    }
                }
                .frame(minWidth: 300)
            }
        }
    }
    
    private var statusColor: Color {
        if viewModel.statusCode >= 200 && viewModel.statusCode < 300 { return .green }
        if viewModel.statusCode >= 400 { return .red }
        return .orange
    }
    
    private var responseDisplay: String {
        responseTab == 0 ? viewModel.responseBodyFormatted : viewModel.responseBody
    }

    private func parseAIDocument() {
        let input = aiDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isAIParsing = true

        Task {
            do {
                let response = try await GeminiService.shared.generateHTTPRequestSpec(prompt: input)
                let spec = try viewModel.parseAISpec(from: response)
                await MainActor.run {
                    do {
                        try viewModel.applyAISpec(spec)
                        requestTab = (spec.body ?? "").isEmpty ? 0 : 1
                        showAIParser = false
                        aiDocument = ""
                        ToastManager.shared.show(message: "AI request parsed", type: .success)
                    } catch {
                        ToastManager.shared.show(message: error.localizedDescription, type: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: error.localizedDescription, type: .error)
                }
            }
            await MainActor.run { isAIParsing = false }
        }
    }
}
