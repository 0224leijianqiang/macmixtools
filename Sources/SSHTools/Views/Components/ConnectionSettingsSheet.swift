import SwiftUI

struct ConnectionSettingsSheet: View {
    @Binding var connection: SSHConnection
    let onClose: () -> Void
    let onConnect: () -> Void

    @ObservedObject var authManager = AuthProfileManager.shared
    @State private var showProfileManager = false

    var body: some View {
        SheetScaffold(
            title: "Configuration".localized,
            minSize: NSSize(width: 520, height: 650),
            onClose: onClose,
            headerTrailing: {
                AnyView(
                    Button(action: { showProfileManager = true }) {
                        Label("Manage Profiles".localized, systemImage: "person.badge.key")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                )
            }
        ) {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    generalSection
                    authenticationSection
                    redisSection
                    mySQLSection
                }
                .padding()
            }
        } footer: {
            HStack {
                Button("Close".localized, action: onClose)
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                Spacer()
                Button("Connect".localized, action: onConnect)
                    .buttonStyle(ModernButtonStyle(variant: .primary))
            }
        }
        .sheet(isPresented: $showProfileManager) { AuthProfileManagerView() }
    }

    private var generalSection: some View {
        FormSection(title: "General".localized, systemImage: "desktopcomputer") {
            VStack(spacing: DesignSystem.Spacing.small) {
                TextField("Name".localized, text: $connection.name)
                    .textFieldStyle(ModernTextFieldStyle(icon: "tag"))

                HStack(spacing: DesignSystem.Spacing.small) {
                    TextField("Host".localized, text: $connection.host)
                        .textFieldStyle(ModernTextFieldStyle(icon: "network"))

                    TextField("Port".localized, text: $connection.port)
                        .textFieldStyle(ModernTextFieldStyle(icon: "number"))
                        .frame(width: 100)
                }
            }
        }
    }

    private var authenticationSection: some View {
        FormSection(title: "Authentication".localized, systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Auth Profile".localized)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $connection.authProfileId) {
                    Text("Custom (Manual)".localized).tag(nil as UUID?)
                    Divider()
                    ForEach(authManager.profiles) { profile in
                        Text(profile.alias).tag(profile.id as UUID?)
                    }
                }
                .labelsHidden()
                .onChange(of: connection.authProfileId) { _, newValue in
                    if let profileId = newValue, let profile = authManager.profiles.first(where: { $0.id == profileId }) {
                        connection.username = profile.username
                        connection.useKey = profile.useKey
                        connection.keyPath = profile.keyPath
                        connection.password = profile.password
                        connection.keyPassphrase = profile.keyPassphrase
                    }
                }
            }

            Divider().padding(.vertical, 4)

            if connection.authProfileId == nil {
                manualCredentialsSection
            } else if let profileId = connection.authProfileId,
                      let profile = authManager.profiles.first(where: { $0.id == profileId }) {
                profileSummarySection(profile: profile)
            }
        }
    }

    @ViewBuilder
    private var manualCredentialsSection: some View {
        if connection.type == .ssh || connection.type == .mysql || connection.type == .clickhouse {
            TextField("Username".localized, text: $connection.username)
                .textFieldStyle(ModernTextFieldStyle(icon: "person"))
        }

        if connection.type == .ssh {
            Toggle("Use Private Key".localized, isOn: $connection.useKey)
                .toggleStyle(.switch)
                .padding(.bottom, 4)

            if connection.useKey {
                HStack {
                    TextField("Key Path".localized, text: $connection.keyPath)
                        .textFieldStyle(ModernTextFieldStyle(icon: "key"))

                    Button("Browse".localized) { browseForKey() }
                        .buttonStyle(ModernButtonStyle(variant: .secondary))
                }

                SecureField("Passphrase (Optional)".localized, text: $connection.keyPassphrase)
                    .textFieldStyle(ModernTextFieldStyle(icon: "lock"))
            } else {
                SecureField("Password".localized, text: $connection.password)
                    .textFieldStyle(ModernTextFieldStyle(icon: "key"))
            }
        } else if connection.type == .mysql || connection.type == .clickhouse {
            SecureField("Password (Optional)".localized, text: $connection.password)
                .textFieldStyle(ModernTextFieldStyle(icon: "key"))
        }
    }

    private func profileSummarySection(profile: SSHAuthProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(profile.username)@\(profile.useKey ? "Private Key" : "Password")")
                .font(DesignSystem.Typography.body.bold())
            if profile.useKey {
                Text(profile.keyPath)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surfaceSecondary)
        .cornerRadius(DesignSystem.Radius.small)
    }

    @ViewBuilder
    private var redisSection: some View {
        if connection.type == .redis {
            FormSection(title: "Redis Settings".localized, systemImage: "server.rack") {
                TextField("Database Index".localized, value: $connection.redisDB, formatter: NumberFormatter())
                    .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
            }
        }
    }

    @ViewBuilder
    private var mySQLSection: some View {
        if connection.type == .mysql {
            FormSection(title: "MySQL Settings".localized, systemImage: "server.rack") {
                TextField("Database".localized, text: $connection.database)
                    .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
            }
        } else if connection.type == .clickhouse {
            FormSection(title: "ClickHouse Settings".localized, systemImage: "server.rack") {
                TextField("Database".localized, text: $connection.database)
                    .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
            }
        }
    }

    private func browseForKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            connection.keyPath = url.path
        }
    }
}
