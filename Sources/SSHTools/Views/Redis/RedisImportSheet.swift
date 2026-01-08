import SwiftUI
import UniformTypeIdentifiers

struct RedisImportSheet: View {
    @ObservedObject var viewModel: RedisViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var targetKey: String = ""
    @State private var targetType: String = "List"
    @State private var csvData: [[String]] = []
    @State private var headers: [String] = []
    @State private var selectedValueColumn: Int = 0
    @State private var selectedFieldColumn: Int = 0
    @State private var isLoadingFile = false
    @State private var fileName: String = ""
    
    // Transformation State
    @State private var isTransformEnabled = false
    @State private var transformScript: String = DataTransformer.defaultScript
    @State private var previewTransformedData: String = ""
    @State private var transformationError: String? = nil
    
    // AI Script Helper State
    @State private var showAIScriptHelper = false
    @State private var aiScriptPrompt = ""
    @State private var isGeneratingScript = false
    
    let types = ["List", "Set", "Hash"]
    
    var body: some View {
        SheetScaffold(
            title: "Import Data to Redis",
            minSize: NSSize(width: 820, height: 720),
            onClose: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    // File Selection Section
                    FormSection(title: "File Source", systemImage: "filemenu.and.selection") {
                        HStack {
                            if fileName.isEmpty {
                                Text("No file selected")
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            } else {
                                Label(fileName, systemImage: "doc.text.fill")
                                    .foregroundColor(DesignSystem.Colors.blue)
                            }

                            Spacer()

                            Button("Select CSV") { selectFile() }
                                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                        }
                        .padding()
                        .background(DesignSystem.Colors.surfaceSecondary)
                        .cornerRadius(DesignSystem.Radius.medium)
                        .outlined(cornerRadius: DesignSystem.Radius.medium)
                    }

                    if !headers.isEmpty {
                        // Configuration Section
                        FormSection(title: "Redis Configuration", systemImage: "gearshape.fill") {
                            VStack(spacing: DesignSystem.Spacing.small) {
                                HStack {
                                    Text("Key Name")
                                        .frame(width: 100, alignment: .leading)
                                    TextField("e.g. my_list_key", text: $targetKey)
                                        .textFieldStyle(ModernTextFieldStyle())
                                }

                                HStack {
                                    Text("Data Type")
                                        .frame(width: 100, alignment: .leading)
                                    Picker("", selection: $targetType) {
                                        ForEach(types, id: \.self) { type in
                                            Text(type).tag(type)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }

                        // Mapping Section
                        FormSection(title: "Column Mapping", systemImage: "arrow.left.arrow.right") {
                            VStack(spacing: DesignSystem.Spacing.small) {
                                if targetType == "Hash" {
                                    HStack {
                                        Text("Field Column")
                                            .frame(width: 100, alignment: .leading)
                                        Picker("", selection: $selectedFieldColumn) {
                                            ForEach(0..<headers.count, id: \.self) { i in
                                                Text(headers[i]).tag(i)
                                            }
                                        }
                                    }
                                }

                                HStack {
                                    Text("Value Column")
                                        .frame(width: 100, alignment: .leading)
                                    Picker("", selection: $selectedValueColumn) {
                                        ForEach(0..<headers.count, id: \.self) { i in
                                            Text(headers[i]).tag(i)
                                        }
                                    }
                                }
                            }
                        }

                        // Transformation Section
                        FormSection(title: "Data Transformation", systemImage: "wand.and.stars") {
                            Toggle("Enable Data Transformation", isOn: $isTransformEnabled)
                                .toggleStyle(.switch)

                            if isTransformEnabled {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("JavaScript (ES6 supported)")
                                            .font(DesignSystem.Typography.caption)

                                        Spacer()

                                        Button(action: { withAnimation { showAIScriptHelper.toggle() } }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "sparkles")
                                                Text("AI Script")
                                            }
                                            .font(.caption.bold())
                                            .foregroundColor(.purple)
                                        }
                                        .buttonStyle(.plain)
                                        .popover(isPresented: $showAIScriptHelper) {
                                            VStack(spacing: 12) {
                                                Text("Describe transformation")
                                                    .font(.headline)
                                                TextField("e.g. Uppercase all values", text: $aiScriptPrompt)
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 250)
                                                    .onSubmit { generateScript() }

                                                HStack {
                                                    if isGeneratingScript {
                                                        ProgressView().scaleEffect(0.5)
                                                    }
                                                    Spacer()
                                                    Button("Generate") { generateScript() }
                                                        .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                                                        .disabled(aiScriptPrompt.isEmpty || isGeneratingScript)
                                                }
                                            }
                                            .padding()
                                        }
                                    }

                                    TextEditor(text: $transformScript)
                                        .font(.monospaced(.body)())
                                        .frame(height: 150)
                                        .padding(4)
                                        .background(DesignSystem.Colors.surfaceSecondary)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2)))

                                    HStack {
                                        Button("Preview Transformation") { runTransformationPreview() }
                                            .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))

                                        Spacer()
                                    }

                                    if let error = transformationError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }

                                    if !previewTransformedData.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Result Preview (First 3 items):")
                                                .font(.caption.bold())
                                            Text(previewTransformedData)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(8)
                                                .background(DesignSystem.Colors.surfaceSecondary)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(DesignSystem.Colors.surface.opacity(0.5))
                                .cornerRadius(8)
                            }
                        }

                        // Preview Section
                        FormSection(title: "Data Preview (First 5 rows)", systemImage: "tablecells") {
                            VStack(spacing: 0) {
                                ForEach(csvData.prefix(5).indices, id: \.self) { rowIndex in
                                    HStack {
                                        let row = csvData[rowIndex]
                                        if targetType == "Hash" {
                                            Text(row.indices.contains(selectedFieldColumn) ? row[selectedFieldColumn] : "-")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Divider()
                                        }
                                        Text(row.indices.contains(selectedValueColumn) ? row[selectedValueColumn] : "-")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    Divider()
                                }
                            }
                            .background(DesignSystem.Colors.surfaceSecondary)
                            .cornerRadius(DesignSystem.Radius.small)
                            .outlined()
                        }
                    }
                }
                .padding()
            }
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))

                Spacer()

                Button(action: performImport) {
                    if viewModel.isPerformingWrite {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Text("Start Import")
                    }
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
                .disabled(targetKey.isEmpty || headers.isEmpty || viewModel.isPerformingWrite)
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                parseCSV(at: url)
            }
        }
    }
    
    private func parseCSV(at url: URL) {
        isLoadingFile = true
        fileName = url.lastPathComponent
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let rows = content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                if let firstRow = rows.first {
                    // Simple CSV parser: handles quoted fields
                    let parsedHeaders = parseCSVRow(firstRow)
                    let parsedData = rows.dropFirst().map { parseCSVRow($0) }
                    
                    DispatchQueue.main.async {
                        self.headers = parsedHeaders
                        self.csvData = parsedData
                        self.isLoadingFile = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.viewModel.errorMsg = "Failed to read file: \(error.localizedDescription)"
                    self.isLoadingFile = false
                }
            }
        }
    }
    
    // Improved CSV row parser to handle quoted commas
    private func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i+1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i += 1
        }
        result.append(current)
        return result
    }
    
    private func getExtractedData() -> Any {
        if targetType == "Hash" {
            var hashData: [String: String] = [:]
            for row in csvData {
                if row.indices.contains(selectedFieldColumn) && row.indices.contains(selectedValueColumn) {
                    hashData[row[selectedFieldColumn]] = row[selectedValueColumn]
                }
            }
            return hashData
        } else {
            var values: [String] = []
            for row in csvData {
                if row.indices.contains(selectedValueColumn) {
                    values.append(row[selectedValueColumn])
                }
            }
            return values
        }
    }
    
    private func runTransformationPreview() {
        let rawData = getExtractedData()
        
        // For preview, take a subset
        var previewInput: Any
        if let dict = rawData as? [String: String] {
            let keys = Array(dict.keys.prefix(3))
            previewInput = dict.filter { keys.contains($0.key) }
        } else if let array = rawData as? [String] {
            previewInput = Array(array.prefix(3))
        } else {
            previewInput = rawData
        }
        
        do {
            let result = try DataTransformer.shared.transform(data: previewInput, script: transformScript)
            transformationError = nil
            if let resultData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: resultData, encoding: .utf8) {
                previewTransformedData = jsonString
            } else {
                previewTransformedData = "\(result)"
            }
        } catch {
            transformationError = error.localizedDescription
            previewTransformedData = ""
        }
    }
    
    private func generateScript() {
        guard !aiScriptPrompt.isEmpty else { return }
        isGeneratingScript = true
        
        Task {
            do {
                let script = try await GeminiService.shared.generateTransformationScript(requirement: aiScriptPrompt, dataType: targetType)
                
                await MainActor.run {
                    self.transformScript = script
                    self.isGeneratingScript = false
                    self.showAIScriptHelper = false
                    self.aiScriptPrompt = ""
                    // Auto preview
                    self.runTransformationPreview()
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingScript = false
                    self.transformationError = "AI Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performImport() {
        var finalData = getExtractedData()
        
        if isTransformEnabled {
            do {
                finalData = try DataTransformer.shared.transform(data: finalData, script: transformScript)
            } catch {
                viewModel.errorMsg = "Transformation failed: \(error.localizedDescription)"
                return
            }
        }
        
        // Convert back to specific types
        var values: [String] = []
        var hashData: [String: String] = [:]
        
        if let dict = finalData as? [String: String] {
            hashData = dict
            // If target type changed but data is hash, we might need to flatten it or warn?
            // Assuming user kept logic consistent.
        } else if let array = finalData as? [String] {
            values = array
        } else if let array = finalData as? [Any] {
             // Handle JS returning mixed types, convert to string
             values = array.map { "\($0)" }
        }
        
        // If user returned an array but target is Hash, or vice versa, this might fail or be empty.
        // We rely on user logic matching target type.
        
        viewModel.importData(key: targetKey, type: targetType, values: values, hashData: hashData) { success in
            if success {
                dismiss()
            }
        }
    }
}
