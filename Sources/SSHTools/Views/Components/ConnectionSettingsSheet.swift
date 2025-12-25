import SwiftUI

struct ConnectionSettingsSheet: View {
    @Binding var connection: SSHConnection
    let onClose: () -> Void
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configuration".localized)
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    // General Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Label("General".localized, systemImage: "desktopcomputer")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.blue)
                        
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
                            
                            if connection.type == .ssh || connection.type == .mysql {
                                TextField("Username".localized, text: $connection.username)
                                    .textFieldStyle(ModernTextFieldStyle(icon: "person"))
                            }
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.Radius.medium)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    // Authentication Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Label("Authentication".localized, systemImage: "lock.shield")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.blue)
                        
                        if connection.type == .ssh {
                            Toggle("Use Private Key".localized, isOn: $connection.useKey)
                                .toggleStyle(.switch)
                                .padding(.bottom, 4)
                            
                            if connection.useKey {
                                HStack {
                                    TextField("Key Path".localized, text: $connection.keyPath)
                                        .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                                    
                                    Button("Browse".localized) {
                                        let panel = NSOpenPanel()
                                        panel.allowsMultipleSelection = false
                                        panel.canChooseDirectories = false
                                        panel.canChooseFiles = true
                                        if panel.runModal() == .OK, let url = panel.url {
                                            connection.keyPath = url.path
                                        }
                                    }
                                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                                }
                                
                                SecureField("Passphrase (Optional)".localized, text: $connection.keyPassphrase)
                                    .textFieldStyle(ModernTextFieldStyle(icon: "lock"))
                            } else {
                                SecureField("Password".localized, text: $connection.password)
                                    .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                            }
                        } else {
                            SecureField("Password (Optional)".localized, text: $connection.password)
                                .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.Radius.medium)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    
                    // Redis Specific Section
                    if connection.type == .redis {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            Label("Redis Settings".localized, systemImage: "server.rack")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.blue)
                            
                            TextField("Database Index".localized, value: $connection.redisDB, formatter: NumberFormatter())
                                .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
                        }
                        .padding()
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.Radius.medium)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    // MySQL Specific Section
                    if connection.type == .mysql {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            Label("MySQL Settings".localized, systemImage: "server.rack")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.blue)
                            
                            TextField("Database".localized, text: $connection.database)
                                .textFieldStyle(ModernTextFieldStyle(icon: "cylinder"))
                        }
                        .padding()
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.Radius.medium)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Close".localized, action: onClose)
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                Spacer()
                Button("Connect".localized, action: onConnect)
                    .buttonStyle(ModernButtonStyle(variant: .primary))
            }
            .padding()
            .background(DesignSystem.Colors.surface)
        }
        .frame(width: 480, height: 600)
        .background(DesignSystem.Colors.background)
    }
}
