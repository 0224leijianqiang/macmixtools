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
        VStack(spacing: DesignSystem.Spacing.medium) {
            Text("Rename".localized)
                .font(DesignSystem.Typography.headline)
            
            TextField("New Name", text: $newName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 300)
                .onSubmit {
                    save()
                }
            
            HStack {
                Button("Cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Rename".localized) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty || newName == currentName)
            }
        }
        .padding()
        .frame(width: 350)
    }
    
    private func save() {
        if !newName.isEmpty && newName != currentName {
            onRename(newName)
            dismiss()
        }
    }
}
