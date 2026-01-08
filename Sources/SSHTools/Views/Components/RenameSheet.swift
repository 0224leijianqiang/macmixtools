import SwiftUI

struct RenameSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let currentName: String
    let onRename: (String) -> Void
    
    @State private var newName: String
    
    init(currentName: String, onRename: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onRename = onRename
        _newName = State(initialValue: currentName)
    }
    
    var body: some View {
        SheetScaffold(
            title: "Rename".localized,
            minSize: NSSize(width: 420, height: 220),
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("New Name".localized)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                TextField("New Name".localized, text: $newName)
                    .textFieldStyle(ModernTextFieldStyle(icon: "pencil"))
                    .outlined()
                    .onSubmit { save() }
            }
            .padding()
        } footer: {
            HStack {
                Button("Cancel".localized) { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Rename".localized) { save() }
                    .buttonStyle(ModernButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.isEmpty || newName == currentName)
            }
        }
    }
    
    private func save() {
        if !newName.isEmpty && newName != currentName {
            onRename(newName)
            dismiss()
        }
    }
}
