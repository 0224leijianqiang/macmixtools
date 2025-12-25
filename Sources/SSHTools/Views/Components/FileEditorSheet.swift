import SwiftUI

struct FileEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let fileName: String
    let onSave: (String) -> Void
    
    @State private var content: String
    
    init(fileName: String, content: String, onSave: @escaping (String) -> Void) {
        self.fileName = fileName
        _content = State(initialValue: content)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit: \(fileName)")
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
            
            // Editor
            TextEditor(text: $content)
                .font(DesignSystem.Typography.monospace)
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.surfaceSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary))
                
                Spacer()
                
                Button("Save") {
                    onSave(content)
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
