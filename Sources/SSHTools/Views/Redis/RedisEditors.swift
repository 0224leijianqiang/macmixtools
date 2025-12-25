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
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("Create New Key")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Text("Key Information")
                            .font(DesignSystem.Typography.caption.weight(.bold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        TextField("Key Name", text: $keyName)
                            .textFieldStyle(ModernTextFieldStyle(icon: "tag"))
                        
                        Picker("Type", selection: $selectedType) {
                            ForEach(types, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Text("Initial Value")
                            .font(DesignSystem.Typography.caption.weight(.bold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
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
                .padding(DesignSystem.Spacing.large)
            }
            
            Divider()
            
            // 按钮
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
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)
        }
        .frame(width: 450, height: 450)
        .background(DesignSystem.Colors.background)
    }
}