import SwiftUI

struct MySQLFilterBuilderPopover: View {
    @ObservedObject var viewModel: MySQLViewModel
    @Binding var isPresented: Bool

    enum FilterOperator: String, CaseIterable, Identifiable {
        case equals = "="
        case notEquals = "!="
        case greater = ">"
        case greaterOrEqual = ">="
        case less = "<"
        case lessOrEqual = "<="
        case like = "LIKE"
        case `in` = "IN"
        case isNull = "IS NULL"
        case isNotNull = "IS NOT NULL"

        var id: String { rawValue }

        var requiresValue: Bool {
            switch self {
            case .isNull, .isNotNull: return false
            default: return true
            }
        }
    }

    @State private var selectedColumn: String = ""
    @State private var selectedOperator: FilterOperator = .equals
    @State private var valueText: String = ""
    @State private var quoteValue: Bool = true

    @State private var presetName: String = ""

    private var availableColumns: [String] {
        let cols = !viewModel.headers.isEmpty ? viewModel.headers : viewModel.allColumns
        return Array(Set(cols)).sorted()
    }

    private func sqlIdentifier(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    private func sqlLiteral(_ value: String) -> String {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "NULL" { return "NULL" }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func buildClause() -> String? {
        let col = selectedColumn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !col.isEmpty else { return nil }

        let op = selectedOperator
        let left = sqlIdentifier(col)

        if !op.requiresValue {
            return "\(left) \(op.rawValue)"
        }

        let rawValue = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }

        switch op {
        case .in:
            let items = rawValue
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return nil }
            let rendered = items.map { quoteValue ? sqlLiteral($0) : $0 }.joined(separator: ", ")
            return "\(left) IN (\(rendered))"
        default:
            let renderedValue = quoteValue ? sqlLiteral(rawValue) : rawValue
            return "\(left) \(op.rawValue) \(renderedValue)"
        }
    }

    private func insertClause(run: Bool) {
        guard let clause = buildClause() else { return }

        let trimmed = viewModel.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel.whereClause = clause
        } else {
            viewModel.whereClause = trimmed + " AND " + clause
        }

        if run {
            viewModel.page = 1
            viewModel.loadData()
            isPresented = false
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Filter Builder")
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            FormSection(title: "Add Filter") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Column", selection: $selectedColumn) {
                        ForEach(availableColumns, id: \.self) { col in
                            Text(col).tag(col)
                        }
                    }
                    .onAppear {
                        if selectedColumn.isEmpty {
                            selectedColumn = availableColumns.first ?? ""
                        }
                    }

                    Picker("Operator", selection: $selectedOperator) {
                        ForEach(FilterOperator.allCases) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }

                    if selectedOperator.requiresValue {
                        TextField(selectedOperator == .in ? "Value (comma-separated)" : "Value", text: $valueText)
                            .textFieldStyle(.roundedBorder)

                        Toggle("Quote value", isOn: $quoteValue)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Button("Insert") { insertClause(run: false) }
                            .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                        Spacer()
                        Button("Apply") { insertClause(run: true) }
                            .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                    }
                }
            }

            FormSection(title: "Presets") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Preset name", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            viewModel.saveFilterPreset(name: presetName, whereClause: viewModel.whereClause)
                            presetName = ""
                        }
                        .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                        .disabled(viewModel.whereClause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if viewModel.filterPresets.isEmpty {
                        Text("No presets yet")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(viewModel.filterPresets) { preset in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                            .font(DesignSystem.Typography.body.weight(.semibold))
                                            .lineLimit(1)
                                        Text(preset.whereClause)
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    Spacer()
                                    Button("Apply") { viewModel.applyFilterPreset(preset) }
                                        .buttonStyle(ModernButtonStyle(variant: .secondary, size: .small))
                                    Button(role: .destructive) {
                                        viewModel.deleteFilterPreset(id: preset.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete")
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(DesignSystem.Colors.surfaceSecondary.opacity(0.6))
                                .cornerRadius(DesignSystem.Radius.small)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 460)
    }
}

