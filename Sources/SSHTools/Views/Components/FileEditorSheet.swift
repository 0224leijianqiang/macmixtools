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
        SheetScaffold(
            title: "Edit: \(fileName)",
            minSize: NSSize(width: 700, height: 500),
            onClose: { dismiss() }
        ) {
            PlainTextEditor(text: $content, font: .monospacedSystemFont(ofSize: 13, weight: .regular), inset: DesignSystem.Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(DesignSystem.Radius.small)
                .outlined()
                .padding()
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                
                Spacer()
                
                Button("Save") {
                    onSave(content)
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
            }
        }
    }
}
