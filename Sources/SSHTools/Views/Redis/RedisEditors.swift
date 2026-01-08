import SwiftUI

// MARK: - New Key Sheet
struct NewKeySheet: View {
    var onSave: (String, String, [String: String]) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var keyName = ""
    @State private var selectedType = "String"
    let types = ["String", "Hash", "List", "Set", "Sorted Set"]
    
    // Inputs
    @State private var value = ""
    @State private var field = ""
    @State private var member = ""
    @State private var score = ""
    
    var body: some View {
        SheetScaffold(
            title: "Create New Key",
            minSize: NSSize(width: 520, height: 520),
            onClose: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    FormSection(title: "Key Information", systemImage: "tag") {
                        TextField("Key Name", text: $keyName)
                            .textFieldStyle(ModernTextFieldStyle(icon: "tag"))
                        
                        Picker("Type", selection: $selectedType) {
                            ForEach(types, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    FormSection(title: "Initial Value", systemImage: "text.badge.plus") {
                        if selectedType == "String" {
                            TextField("Value", text: $value)
                                .textFieldStyle(ModernTextFieldStyle())
                        } else if selectedType == "Hash" {
                            TextField("Field Name", text: $field)
                                .textFieldStyle(ModernTextFieldStyle())
                            TextField("Value", text: $value)
                                .textFieldStyle(ModernTextFieldStyle())
                        } else if selectedType == "List" {
                            TextField("Initial Item Value", text: $value)
                                .textFieldStyle(ModernTextFieldStyle())
                        } else if selectedType == "Set" {
                            TextField("Member Value", text: $value)
                                .textFieldStyle(ModernTextFieldStyle())
                        } else if selectedType == "Sorted Set" {
                            TextField("Score", text: $score)
                                .textFieldStyle(ModernTextFieldStyle())
                            TextField("Member", text: $member)
                                .textFieldStyle(ModernTextFieldStyle())
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
                Button("Create") {
                    var ctx: [String: String] = [:]
                    ctx["value"] = value
                    ctx["field"] = field
                    ctx["member"] = member
                    ctx["score"] = score
                    onSave(keyName, selectedType, ctx)
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
                .disabled(keyName.isEmpty)
            }
        }
    }
}
