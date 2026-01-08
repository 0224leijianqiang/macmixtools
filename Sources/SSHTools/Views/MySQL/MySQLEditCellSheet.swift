import SwiftUI
import AppKit

struct MySQLEditCellSheet: View {
    @ObservedObject var viewModel: MySQLViewModel
    let rowIndex: Int
    let columnIndex: Int
    let originalValue: String
    let onClose: () -> Void

    @State private var newValue: String = ""
    @State private var setNull: Bool = false
    @State private var quoteAsString: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var columnName: String {
        guard viewModel.headers.indices.contains(columnIndex) else { return "" }
        return viewModel.headers[columnIndex]
    }

    private var canEdit: Bool {
        viewModel.connection.type != .clickhouse && !viewModel.primaryKeyColumns.isEmpty
    }

    private func sqlIdentifier(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    private func sqlLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func buildSQLPreview() -> String {
        let tableName = viewModel.currentTable ?? "table"
        let qualified = sqlIdentifier(viewModel.currentDatabase) + "." + sqlIdentifier(tableName)
        let setValue = setNull ? "NULL" : (quoteAsString ? sqlLiteral(newValue) : newValue)

        let pk = viewModel.primaryKeyColumns.map(sqlIdentifier).joined(separator: ", ")
        return """
        UPDATE \(qualified)
        SET \(sqlIdentifier(columnName)) = \(setValue)
        WHERE <PRIMARY_KEY: \(pk)>
        LIMIT 1;
        """
    }

    var body: some View {
        SheetScaffold(
            title: "Edit Cell",
            subtitle: "\(viewModel.currentDatabase).\(viewModel.currentTable ?? "") • \(columnName)",
            minSize: NSSize(width: 760, height: 520),
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                if viewModel.connection.type == .clickhouse {
                    Text("ClickHouse does not support UPDATE in this UI.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.pink)
                } else if viewModel.primaryKeyColumns.isEmpty {
                    Text("This table has no primary key, editing is disabled to avoid unsafe UPDATE.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.pink)
                } else {
                    Text("Primary Key: \(viewModel.primaryKeyColumns.joined(separator: ", "))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                FormSection(title: "Original") {
                    Text(originalValue)
                        .font(DesignSystem.Typography.monospace)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.small)
                        .background(DesignSystem.Colors.surfaceSecondary.opacity(0.6))
                        .cornerRadius(DesignSystem.Radius.small)
                        .outlined()
                }

                FormSection(title: "New Value") {
                    VStack(alignment: .leading, spacing: 10) {
                        PlainTextEditor(text: $newValue)
                            .frame(minHeight: 120)
                            .outlined()

                        Toggle("Set NULL", isOn: $setNull)
                            .toggleStyle(.switch)

                        Toggle("Quote as string", isOn: $quoteAsString)
                            .toggleStyle(.switch)
                            .disabled(setNull)
                    }
                }

                FormSection(title: "SQL Preview") {
                    Text(buildSQLPreview())
                        .font(DesignSystem.Typography.monospace)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.small)
                        .background(DesignSystem.Colors.surfaceSecondary.opacity(0.6))
                        .cornerRadius(DesignSystem.Radius.small)
                        .outlined()
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.pink)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .onAppear {
                newValue = originalValue == "NULL" ? "" : originalValue
                setNull = (originalValue == "NULL")
            }
        } footer: {
            HStack {
                Button("Cancel") { onClose() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))

                Spacer()

                Button(isSaving ? "Saving…" : "Save") {
                    guard canEdit else { return }
                    errorMessage = nil
                    isSaving = true
                    Task {
                        do {
                            try await viewModel.updateCell(
                                rowIndex: rowIndex,
                                columnIndex: columnIndex,
                                newValue: newValue,
                                setNull: setNull,
                                quoteAsString: quoteAsString
                            )
                            await MainActor.run {
                                ToastManager.shared.show(message: "Updated", type: .success)
                                viewModel.page = 1
                                viewModel.loadData()
                                isSaving = false
                                onClose()
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                isSaving = false
                            }
                        }
                    }
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
                .disabled(isSaving || !canEdit)
            }
        }
    }
}

