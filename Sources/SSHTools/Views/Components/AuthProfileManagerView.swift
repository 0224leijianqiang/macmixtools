import SwiftUI

struct AuthProfileManagerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var authManager = AuthProfileManager.shared
    @State private var editingProfile: SSHAuthProfile?
    @State private var showEditor = false

    var body: some View {
        SheetScaffold(
            title: "Authentication Profiles".localized,
            minSize: NSSize(width: 560, height: 420),
            onClose: { dismiss() },
            headerTrailing: {
                AnyView(
                    Button(action: addProfile) {
                        Label("Add Profile".localized, systemImage: "plus")
                    }
                    .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                    .padding(.trailing, 12)
                )
            }
        ) {
            List {
                if authManager.profiles.isEmpty {
                    Text("No profiles yet. Add one to reuse credentials.".localized)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(authManager.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.alias)
                                    .font(DesignSystem.Typography.body.bold())
                                Text("\(profile.username)@\(profile.useKey ? "Key" : "Password")")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 12) {
                                Button("Edit".localized) {
                                    editingProfile = profile
                                    showEditor = true
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.blue)

                                Button("Delete".localized) {
                                    authManager.deleteProfile(id: profile.id)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
        } footer: {
            HStack {
                Spacer()
                Button("Done".localized) { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
            }
        }
        .sheet(isPresented: $showEditor) {
            if let profile = editingProfile {
                AuthProfileEditorView(profile: profile) { updated in
                    if authManager.profiles.contains(where: { $0.id == updated.id }) {
                        authManager.updateProfile(updated)
                    } else {
                        authManager.addProfile(updated)
                    }
                    showEditor = false
                }
            }
        }
    }

    private func addProfile() {
        editingProfile = SSHAuthProfile(alias: "New Profile".localized, username: "root")
        showEditor = true
    }
}

struct AuthProfileEditorView: View {
    @State var profile: SSHAuthProfile
    let onSave: (SSHAuthProfile) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        SheetScaffold(
            title: profile.alias.isEmpty ? "New Profile".localized : profile.alias,
            minSize: NSSize(width: 460, height: 520),
            onClose: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    FormSection(title: "Profile".localized, systemImage: "person") {
                        TextField("Alias (e.g. Production)".localized, text: $profile.alias)
                            .textFieldStyle(ModernTextFieldStyle(icon: "tag"))

                        TextField("Username".localized, text: $profile.username)
                            .textFieldStyle(ModernTextFieldStyle(icon: "person"))
                    }

                    FormSection(title: "Authentication".localized, systemImage: "lock.shield") {
                        Toggle("Use Private Key".localized, isOn: $profile.useKey)
                            .toggleStyle(.switch)

                        if profile.useKey {
                            HStack {
                                TextField("Key Path".localized, text: $profile.keyPath)
                                    .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                                Button("Browse".localized) {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    if panel.runModal() == .OK { profile.keyPath = panel.url?.path ?? "" }
                                }
                                .buttonStyle(ModernButtonStyle(variant: .secondary))
                            }
                            SecureField("Passphrase (Optional)".localized, text: $profile.keyPassphrase)
                                .textFieldStyle(ModernTextFieldStyle(icon: "lock"))
                        } else {
                            SecureField("Password".localized, text: $profile.password)
                                .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                        }
                    }
                }
                .padding()
            }
        } footer: {
            HStack {
                Button("Cancel".localized) { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                Spacer()
                Button("Save".localized) {
                    onSave(profile)
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
            }
        }
    }
}
