import SwiftUI
import Foundation
import AppKit

struct HashEditor: View {
    let data: [String: String]
    var onUpdate: (String, String) -> Void
    var onRename: (String, String, String) -> Void
    var onDelete: (String) -> Void

    struct HashEditTarget: Identifiable {
        let id = UUID()
        let field: String
        let value: String
    }

    @State private var editingTarget: HashEditTarget?
    @State private var editedField: String = ""
    @State private var editedValue: String = ""
    @State private var isAdding = false
    @State private var keySortAscending: Bool? = nil
    @State private var valueSortAscending: Bool? = nil
    @State private var searchText: String = ""

    private var sortedKeysWithIndex: [(index: Int, key: String)] {
        var keys = Array(data.keys)

        if let keySort = keySortAscending {
            keys.sort { keySort ? $0 < $1 : $0 > $1 }
        } else if let valueSort = valueSortAscending {
            keys.sort { a, b in
                let va = data[a] ?? ""
                let vb = data[b] ?? ""
                return valueSort ? va < vb : va > vb
            }
        } else {
            // Default stable order to avoid jitter
            keys.sort()
        }

        if !searchText.isEmpty {
            let query = searchText
            keys = keys.filter { field in
                field.localizedCaseInsensitiveContains(query) ||
                (data[field] ?? "").localizedCaseInsensitiveContains(query)
            }
        }

        return keys.enumerated().map { (index: $0.offset + 1, key: $0.element) }
    }

    var body: some View {
        HashEditorBodyView(
            rows: sortedKeysWithIndex,
            data: data,
            keySortAscending: $keySortAscending,
            valueSortAscending: $valueSortAscending,
            searchText: $searchText,
            onAddRow: { isAdding = true },
            onExportCSV: exportToCSV,
            onEdit: { field, value in
                editingTarget = HashEditTarget(field: field, value: value)
            },
            onDelete: onDelete
        )
        .sheet(item: $editingTarget) { target in
            HashFieldEditorSheet(
                originalField: target.field,
                originalValue: data[target.field] ?? target.value,
                field: $editedField,
                value: $editedValue,
                onCancel: { editingTarget = nil },
                onSave: {
                    let newField = editedField.trimmingCharacters(in: .whitespacesAndNewlines)
                    if newField.isEmpty { return }
                    if newField == target.field {
                        onUpdate(target.field, editedValue)
                    } else {
                        onRename(target.field, newField, editedValue)
                    }
                    editingTarget = nil
                }
            )
        }
        .sheet(isPresented: $isAdding) {
            ValueEditorSheet(
                mode: .hashNewField,
                onSave: { _ in },
                onSaveWithField: { fieldName, value in
                    onUpdate(fieldName, value)
                    isAdding = false
                }
            )
        }
    }

    private func exportToCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hash_export.csv"
        if panel.runModal() == .OK, let url = panel.url {
            var csv = "Key,Value\n"
            for item in sortedKeysWithIndex {
                let val = data[item.key] ?? ""
                let escapedKey = item.key.replacingOccurrences(of: "\"", with: "\"\"")
                let escapedVal = val.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(escapedKey)\",\"\(escapedVal)\"\n"
            }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct HashEditorBodyView: View {
    let rows: [(index: Int, key: String)]
    let data: [String: String]
    @Binding var keySortAscending: Bool?
    @Binding var valueSortAscending: Bool?
    @Binding var searchText: String
    let onAddRow: () -> Void
    let onExportCSV: () -> Void
    let onEdit: (String, String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HashToolbarView(onAddRow: onAddRow, onExportCSV: onExportCSV)
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.surface)

            Divider()

            HashListView(
                rows: rows,
                data: data,
                keySortAscending: $keySortAscending,
                valueSortAscending: $valueSortAscending,
                searchText: $searchText,
                onEdit: onEdit,
                onDelete: onDelete
            )
        }
    }
}

private struct HashListView: View {
    let rows: [(index: Int, key: String)]
    let data: [String: String]
    @Binding var keySortAscending: Bool?
    @Binding var valueSortAscending: Bool?
    @Binding var searchText: String
    let onEdit: (String, String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        List {
            HashTableHeaderView(
                keySortAscending: $keySortAscending,
                valueSortAscending: $valueSortAscending,
                searchText: $searchText
            )
            .frame(height: DesignSystem.Layout.headerHeight)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)

            ForEach(rows, id: \.key) { item in
                let value = data[item.key] ?? ""
                HashRowView(
                    index: item.index,
                    field: item.key,
                    value: value,
                    onCopyKey: { copyToPasteboard(item.key) },
                    onCopyValue: { copyToPasteboard(value) },
                    onEdit: { onEdit(item.key, value) },
                    onDelete: { onDelete(item.key) }
                )
                .frame(height: DesignSystem.Layout.rowHeight + 8)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }
}

private struct HashToolbarView: View {
    let onAddRow: () -> Void
    let onExportCSV: () -> Void

    var body: some View {
        HStack {
            Button(action: onAddRow) {
                Label("Add Row", systemImage: "plus")
            }
            .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))

            Spacer()

            Button(action: onExportCSV) {
                Label("Export CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
        }
    }
}

private struct HashTableHeaderView: View {
    @Binding var keySortAscending: Bool?
    @Binding var valueSortAscending: Bool?
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 0) {
            Text("ID")
                .font(DesignSystem.Typography.caption.weight(.bold))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 60, alignment: .leading)
                .padding(.leading, DesignSystem.Spacing.medium)

            Divider()

            HStack {
                Text("Key")
                    .font(DesignSystem.Typography.caption.weight(.bold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Button(action: {
                    if keySortAscending == true { keySortAscending = false }
                    else { keySortAscending = true }
                    valueSortAscending = nil
                }) {
                    Image(systemName: keySortAscending == nil ? "arrow.up.arrow.down" : (keySortAscending! ? "arrow.up" : "arrow.down"))
                        .font(.system(size: 9))
                        .foregroundColor(keySortAscending != nil ? DesignSystem.Colors.blue : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 200, alignment: .leading)
            .padding(.leading, DesignSystem.Spacing.medium)

            Divider()

            HStack {
                Text("Value")
                    .font(DesignSystem.Typography.caption.weight(.bold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Button(action: {
                    if valueSortAscending == true { valueSortAscending = false }
                    else { valueSortAscending = true }
                    keySortAscending = nil
                }) {
                    Image(systemName: valueSortAscending == nil ? "arrow.up.arrow.down" : (valueSortAscending! ? "arrow.up" : "arrow.down"))
                        .font(.system(size: 9))
                        .foregroundColor(valueSortAscending != nil ? DesignSystem.Colors.blue : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: DesignSystem.Spacing.tiny) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.caption)
                        .frame(width: 120)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.background.opacity(0.5))
                .cornerRadius(DesignSystem.Radius.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DesignSystem.Spacing.medium)
            .padding(.trailing, DesignSystem.Spacing.medium)
        }
    }
}

private struct HashRowView: View {
    let index: Int
    let field: String
    let value: String
    let onCopyKey: () -> Void
    let onCopyValue: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index)")
                .font(DesignSystem.Typography.monospace)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 60, alignment: .leading)
                .padding(.leading, DesignSystem.Spacing.medium)

            Divider()

            Text(field)
                .font(DesignSystem.Typography.body)
                .frame(width: 200, alignment: .leading)
                .padding(.leading, DesignSystem.Spacing.medium)
                .lineLimit(1)
                .textSelection(.enabled)
                .contextMenu {
                    Button("Copy Key") { onCopyKey() }
                }

            Divider()

            HStack {
                Text(value)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .clipped()
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy Value") { onCopyValue() }
                    }

                HStack(spacing: 12) {
                    Button(action: onCopyValue) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.blue)
                        .help("Copy Value")

                    Button(action: onEdit) { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.blue)
                        .help("Edit")

                    Button(action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.pink)
                        .help("Delete")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, DesignSystem.Spacing.medium)
            .padding(.trailing, DesignSystem.Spacing.medium)
        }
    }
}

private struct HashFieldEditorSheet: View {
    let originalField: String
    let originalValue: String
    @Binding var field: String
    @Binding var value: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var jsonError: String?

    var body: some View {
        SheetScaffold(
            title: "Edit Hash Field",
            subtitle: "Update field name and value",
            minSize: NSSize(width: 760, height: 600),
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                FormSection(title: "Field", systemImage: "key") {
                    TextField("Field", text: $field)
                        .textFieldStyle(ModernTextFieldStyle(icon: "key"))
                        .outlined()
                }

                FormSection(
                    title: "Value",
                    systemImage: "doc.plaintext",
                    headerTrailing: {
                        AnyView(
                            Button("Format JSON") { formatJSON() }
                                .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                                .disabled(!JSONFormatting.isCandidate(value))
                        )
                    }
                ) {
                    if let jsonError {
                        Text(jsonError)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.pink)
                            .lineLimit(1)
                    }

                    PlainTextEditor(text: $value, font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
                        .frame(minHeight: 320)
                        .background(DesignSystem.Colors.surfaceSecondary)
                        .cornerRadius(DesignSystem.Radius.small)
                        .outlined()
                }
            }
            .padding()
        } footer: {
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))

                Spacer()

                Button("Save") { onSave() }
                    .buttonStyle(ModernButtonStyle(variant: .primary))
                    .disabled(field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            field = originalField
            value = originalValue
            jsonError = nil
        }
    }

    private func formatJSON() {
        switch JSONFormatting.prettyPrinted(value) {
        case .success(let pretty):
            value = pretty
            jsonError = nil
        case .failure(let error):
            switch error {
            case .invalidUTF8:
                jsonError = "Invalid UTF-8"
            case .invalidJSON:
                jsonError = "Invalid JSON"
            case .formatFailed:
                jsonError = "Format failed"
            }
        }
    }
}
