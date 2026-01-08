import SwiftUI

struct DataRow: View {
    let rowIndex: Int
    let rowData: [String]
    @ObservedObject var viewModel: MySQLViewModel
    let onEditCell: ((Int, Int) -> Void)?

    @State private var dragStarted = false

    private func flags(from modifiers: EventModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    private func selectRow(columnIndex: Int?, modifiers: EventModifiers) {
        viewModel.selectRow(rowIndex: rowIndex, columnIndex: columnIndex, modifierFlags: flags(from: modifiers))
    }

    private func dragSelect(value: DragGesture.Value, columnIndex: Int?) {
        guard !viewModel.rows.isEmpty else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dy) < abs(dx) { return } // avoid fighting horizontal scrolling/drags

        let step: CGFloat = 34
        let delta = Int((dy / step).rounded())
        let target = max(0, min((viewModel.rows.count - 1), rowIndex + delta))

        viewModel.updateDragSelection(targetRowIndex: target)
    }

    private func copyToPasteboard(_ string: String, toast: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        ToastManager.shared.show(message: toast, type: .success)
    }

    private func sqlIdentifier(_ name: String) -> String {
        // MySQL-style quoting also works well for ClickHouse identifiers.
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    private func sqlLiteral(_ value: String) -> String {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "NULL" { return "NULL" }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func rowTSV() -> String {
        rowData.joined(separator: "\t")
    }

    private func rowTSVWithHeaders() -> String {
        let count = min(viewModel.headers.count, rowData.count)
        let headerLine = viewModel.headers.prefix(count).joined(separator: "\t")
        let rowLine = rowData.prefix(count).joined(separator: "\t")
        return headerLine + "\n" + rowLine
    }

    private func rowInsertSQL() -> String {
        let count = min(viewModel.headers.count, rowData.count)
        let columns = viewModel.headers.prefix(count).map(sqlIdentifier).joined(separator: ", ")
        let values = rowData.prefix(count).map(sqlLiteral).joined(separator: ", ")

        let tableName = viewModel.currentTable ?? "table"
        let qualified: String
        if viewModel.currentDatabase.isEmpty {
            qualified = sqlIdentifier(tableName)
        } else {
            qualified = sqlIdentifier(viewModel.currentDatabase) + "." + sqlIdentifier(tableName)
        }

        return "INSERT INTO \(qualified) (\(columns)) VALUES (\(values));"
    }

    private func rowJSON() -> String {
        let count = min(viewModel.headers.count, rowData.count)
        var dict: [String: String] = [:]
        dict.reserveCapacity(count)
        for i in 0..<count {
            dict[viewModel.headers[i]] = rowData[i]
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    @ViewBuilder
    private func rowCopyMenuItems() -> some View {
        Button("Copy Row (TSV)") { copyToPasteboard(rowTSV(), toast: "Copied Row (TSV)") }
        Button("Copy Row (TSV with Headers)") { copyToPasteboard(rowTSVWithHeaders(), toast: "Copied Row (TSV+Headers)") }
        Button("Copy Row (JSON)") { copyToPasteboard(rowJSON(), toast: "Copied Row (JSON)") }
        Button("Copy Row (SQL INSERT)") { copyToPasteboard(rowInsertSQL(), toast: "Copied Row (SQL INSERT)") }
    }

    private var isSelected: Bool {
        viewModel.selectedRowIndices.contains(rowIndex)
    }

    private var selectedRowBackground: Color {
        DesignSystem.Colors.text.opacity(0.06)
    }

    private var sequenceCellBackground: Color {
        if isSelected {
            if viewModel.selectedColumnIndex == nil {
                return DesignSystem.Colors.blue.opacity(0.18)
            }
            return selectedRowBackground
        }
        return rowIndex % 2 == 0 ? Color.clear : DesignSystem.surfaceColor.opacity(0.3)
    }

    private func dataCellBackground(colIdx: Int) -> Color {
        if isSelected {
            if viewModel.selectedColumnIndex == colIdx {
                return DesignSystem.Colors.blue.opacity(0.18)
            }
            return selectedRowBackground
        }
        if viewModel.selectedColumnIndex == colIdx {
            return DesignSystem.Colors.blue.opacity(0.08)
        }
        return rowIndex % 2 == 0 ? Color.clear : DesignSystem.surfaceColor.opacity(0.5)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sequence Cell
            Text("\(rowIndex + 1 + (viewModel.page - 1) * viewModel.limit)")
                .font(DesignSystem.fontBody)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(8)
                .frame(width: 50, alignment: .center)
                .background(sequenceCellBackground)
                .overlay(
                    Rectangle().stroke(DesignSystem.borderColor.opacity(0.3), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().modifiers([.command, .shift]).onEnded { selectRow(columnIndex: nil, modifiers: [.command, .shift]) })
                .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { selectRow(columnIndex: nil, modifiers: [.shift]) })
                .highPriorityGesture(TapGesture().modifiers(.command).onEnded { selectRow(columnIndex: nil, modifiers: [.command]) })
                .onTapGesture { selectRow(columnIndex: nil, modifiers: []) }
                .contextMenu {
                    rowCopyMenuItems()
                }
            
            ForEach(0..<rowData.count, id: \.self) { colIdx in
                Text(rowData[colIdx])
                    .font(DesignSystem.fontBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(8)
                    .frame(width: viewModel.columnWidths.indices.contains(colIdx) ? viewModel.columnWidths[colIdx] : 150, alignment: .leading)
                    .background(dataCellBackground(colIdx: colIdx))
                    .overlay(
                        Rectangle().stroke(DesignSystem.borderColor.opacity(0.5), lineWidth: 0.5)
                    )
                    .clipped()
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().modifiers([.command, .shift]).onEnded { selectRow(columnIndex: colIdx, modifiers: [.command, .shift]) })
                    .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { selectRow(columnIndex: colIdx, modifiers: [.shift]) })
                    .highPriorityGesture(TapGesture().modifiers(.command).onEnded { selectRow(columnIndex: colIdx, modifiers: [.command]) })
                    .onTapGesture { selectRow(columnIndex: colIdx, modifiers: []) }
                    .contextMenu {
                        Button("Copy Cell") { copyToPasteboard(rowData[colIdx], toast: "Copied Cell") }
                        Button("Copy Column Name") {
                            if viewModel.headers.indices.contains(colIdx) {
                                copyToPasteboard(viewModel.headers[colIdx], toast: "Copied Column Name")
                            }
                        }
                        Divider()
                        Button("Edit Cell…") { onEditCell?(rowIndex, colIdx) }
                            .disabled(viewModel.connection.type == .clickhouse)
                        Divider()
                        rowCopyMenuItems()
                    }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !dragStarted {
                        dragStarted = true
                        viewModel.beginDragSelection(anchorRowIndex: rowIndex)
                    }
                    dragSelect(value: value, columnIndex: nil)
                }
                .onEnded { _ in
                    dragStarted = false
                    viewModel.endDragSelection()
                }
        )
        .contextMenu {
            rowCopyMenuItems()
        }
    }
}

struct HeaderCell: View {
    let title: String
    let width: CGFloat
    let onResize: (CGFloat) -> Void // Pass the absolute new width
    var sortDirection: MySQLViewModel.SortDirection?
    var onToggleSort: (() -> Void)? = nil
    var isSelectedColumn: Bool = false
    var onSelectColumn: (() -> Void)? = nil
    
    @State private var isHoveringHandle = false
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat? = nil
    @State private var cursorPushed = false
    @State private var pendingWidth: CGFloat? = nil
    @State private var lastResizeSentAt: TimeInterval = 0
    @State private var resizeWorkItem: DispatchWorkItem? = nil

    private let resizeThrottleInterval: TimeInterval = 0.05

    private func sendResize(_ newWidth: CGFloat) {
        lastResizeSentAt = CACurrentMediaTime()
        onResize(newWidth)
    }

    private var sortIconName: String? {
        switch sortDirection {
        case .asc: return "chevron.up"
        case .desc: return "chevron.down"
        case nil: return nil
        }
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Content
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(DesignSystem.fontCaption)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectColumn?()
                }
                
                Button(action: { onToggleSort?() }) {
                    Image(systemName: sortIconName ?? "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(sortDirection == nil ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.blue)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Resize Handle Hit Area
                Color.clear
                    .frame(width: 8) // Wider hit area for easier grabbing
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringHandle = hovering
                        if hovering {
                            if !cursorPushed {
                                NSCursor.resizeLeftRight.push()
                                cursorPushed = true
                            }
                        } else if cursorPushed && !isDragging {
                            NSCursor.pop()
                            cursorPushed = false
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = width
                                }
                                isDragging = true
                                if !cursorPushed {
                                    NSCursor.resizeLeftRight.push()
                                    cursorPushed = true
                                }
                                let baseWidth = dragStartWidth ?? width
                                let newWidth = max(50, baseWidth + value.translation.width)
                                pendingWidth = newWidth

                                let now = CACurrentMediaTime()
                                if now - lastResizeSentAt >= resizeThrottleInterval {
                                    resizeWorkItem?.cancel()
                                    resizeWorkItem = nil
                                    sendResize(newWidth)
                                } else if resizeWorkItem == nil {
                                    let delay = max(0, resizeThrottleInterval - (now - lastResizeSentAt))
                                    let work = DispatchWorkItem {
                                        guard isDragging, let latest = pendingWidth else { return }
                                        sendResize(latest)
                                        resizeWorkItem = nil
                                    }
                                    resizeWorkItem = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                                }
                            }
                            .onEnded { value in
                                isDragging = false
                                dragStartWidth = nil
                                resizeWorkItem?.cancel()
                                resizeWorkItem = nil
                                if let latest = pendingWidth {
                                    sendResize(latest)
                                }
                                pendingWidth = nil
                                if cursorPushed && !isHoveringHandle {
                                    NSCursor.pop()
                                    cursorPushed = false
                                }
                            }
                    )
            }
            .frame(width: width, height: DesignSystem.Layout.headerHeight)
            .transaction { transaction in
                transaction.animation = nil
            }
            .background(isSelectedColumn
                        ? AnyShapeStyle(DesignSystem.Colors.blue.opacity(0.08))
                        : AnyShapeStyle(.ultraThinMaterial)) // High-quality transparency
            .overlay(
                Rectangle().stroke(DesignSystem.borderColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .zIndex(isDragging ? 100 : 0) // Ensure ghost line appears above other headers
    }
}
