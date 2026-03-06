import SwiftUI
import AppKit

struct SFTPTableView: NSViewRepresentable {
    @ObservedObject var viewModel: SyncedSFTPViewModel
    let onNavigate: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = DragSelectTableView()
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.headerView = NSTableHeaderView()
        tableView.rowSizeStyle = .small
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autoresizingMask = [.width]

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name".localized
        nameCol.resizingMask = [.autoresizingMask]
        nameCol.minWidth = 180
        nameCol.isEditable = false
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(nameCol)

        let permCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("perm"))
        permCol.title = "Permissions".localized
        permCol.resizingMask = []
        permCol.width = 85
        permCol.isEditable = false
        tableView.addTableColumn(permCol)

        let ownerCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("owner"))
        ownerCol.title = "Owner".localized
        ownerCol.resizingMask = []
        ownerCol.width = 80
        ownerCol.isEditable = false
        tableView.addTableColumn(ownerCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size".localized
        sizeCol.resizingMask = []
        sizeCol.width = 70
        sizeCol.isEditable = false
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        tableView.addTableColumn(sizeCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date".localized
        dateCol.resizingMask = []
        dateCol.width = 120
        dateCol.isEditable = false
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)
        tableView.addTableColumn(dateCol)

        tableView.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.dragSelectionDelegate = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.handleClick(_:))
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(tableView: tableView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? DragSelectTableView else { return }
        context.coordinator.viewModel = viewModel

        // Keep header sort indicator in sync with current sort state.
        let desiredDescriptor: NSSortDescriptor = {
            switch viewModel.sortField {
            case .name:
                return NSSortDescriptor(key: "name", ascending: viewModel.sortAscending)
            case .size:
                return NSSortDescriptor(key: "size", ascending: viewModel.sortAscending)
            case .date:
                return NSSortDescriptor(key: "date", ascending: viewModel.sortAscending)
            }
        }()
        if tableView.sortDescriptors.first?.key != desiredDescriptor.key || tableView.sortDescriptors.first?.ascending != desiredDescriptor.ascending {
            tableView.sortDescriptors = [desiredDescriptor]
        }

        if context.coordinator.lastFilesRevision != viewModel.filesRevision {
            context.coordinator.lastFilesRevision = viewModel.filesRevision
            tableView.reloadData()
        }

        context.coordinator.applySelection(to: tableView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onNavigate: onNavigate)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, DragSelectTableViewDelegate {
        var viewModel: SyncedSFTPViewModel
        let onNavigate: (String) -> Void

        weak var tableView: DragSelectTableView?
        var lastFilesRevision: UInt64 = 0
        private var isApplyingSelection = false

        init(viewModel: SyncedSFTPViewModel, onNavigate: @escaping (String) -> Void) {
            self.viewModel = viewModel
            self.onNavigate = onNavigate
            self.lastFilesRevision = viewModel.filesRevision
        }

        func attach(tableView: DragSelectTableView) {
            self.tableView = tableView
        }

        // MARK: DataSource
        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.files.count
        }

        // MARK: Delegate
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < viewModel.files.count else { return nil }
            let file = viewModel.files[row]
            let colId = tableColumn?.identifier.rawValue ?? "name"

            switch colId {
            case "name":
                let id = NSUserInterfaceItemIdentifier("SFTPNameCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: self) as? SFTPNameCellView) ?? {
                    let v = SFTPNameCellView()
                    v.identifier = id
                    return v
                }()
                cell.configure(with: file)
                return cell
            case "perm":
                return makeTextCell(tableView: tableView, id: "SFTPPermCell", text: file.permissions, alignment: .left, monospaced: true)
            case "owner":
                return makeTextCell(tableView: tableView, id: "SFTOwnerCell", text: "\(file.owner):\(file.group)", alignment: .left, monospaced: false)
            case "size":
                return makeTextCell(tableView: tableView, id: "SFTPSizeCell", text: file.size, alignment: .right, monospaced: false)
            case "date":
                return makeTextCell(tableView: tableView, id: "SFTPDateCell", text: file.date, alignment: .right, monospaced: false)
            default:
                return makeTextCell(tableView: tableView, id: "SFTPDefaultCell", text: "", alignment: .left, monospaced: false)
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            guard let tableView = notification.object as? NSTableView else { return }

            let ids = tableView.selectedRowIndexes.compactMap { idx -> UUID? in
                guard idx >= 0, idx < viewModel.files.count else { return nil }
                return viewModel.files[idx].id
            }
            viewModel.selectedFileIds = Set(ids)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let desc = tableView.sortDescriptors.first else { return }
            let ascending = desc.ascending
            switch desc.key {
            case "name":
                viewModel.setSort(field: .name, ascending: ascending)
            case "size":
                viewModel.setSort(field: .size, ascending: ascending)
            case "date":
                viewModel.setSort(field: .date, ascending: ascending)
            default:
                break
            }
        }

        func applySelection(to tableView: DragSelectTableView) {
            isApplyingSelection = true
            defer { isApplyingSelection = false }

            let selected = viewModel.selectedFileIds
            let indexes = IndexSet(viewModel.files.enumerated().compactMap { i, f in selected.contains(f.id) ? i : nil })
            if tableView.selectedRowIndexes != indexes {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        private func makeTextCell(tableView: NSTableView, id: String, text: String, alignment: NSTextAlignment, monospaced: Bool) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier(id)
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
                let v = NSTableCellView()
                v.identifier = identifier
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.lineBreakMode = .byTruncatingTail
                tf.maximumNumberOfLines = 1
                tf.textColor = .secondaryLabelColor
                tf.alignment = alignment
                tf.font = monospaced ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 11)
                v.textField = tf
                v.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                    tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
                    tf.centerYAnchor.constraint(equalTo: v.centerYAnchor)
                ])
                return v
            }()
            cell.textField?.stringValue = text
            return cell
        }

        // MARK: DragSelectTableViewDelegate
        func dragSelectTableView(_ tableView: DragSelectTableView, menuFor event: NSEvent) -> NSMenu? {
            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)
            if row >= 0, !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
            }

            let selectedCount = tableView.selectedRowIndexes.count
            let menu = NSMenu()

            if selectedCount > 1 {
                menu.addItem(NSMenuItem(title: "Upload to Current Directory", action: #selector(uploadToCurrentDirectory(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Download", action: #selector(downloadSelected(_:)), keyEquivalent: ""))
                let del = NSMenuItem(title: "Delete", action: #selector(deleteSelected(_:)), keyEquivalent: "")
                menu.addItem(del)
                menu.items.forEach { $0.target = self }
                return menu
            }

            guard row >= 0, row < viewModel.files.count else {
                menu.addItem(NSMenuItem(title: "Upload to Current Directory", action: #selector(uploadToCurrentDirectory(_:)), keyEquivalent: ""))
                menu.items.forEach { $0.target = self }
                return menu
            }
            let file = viewModel.files[row]

            menu.addItem(NSMenuItem(title: "Upload to Current Directory", action: #selector(uploadToCurrentDirectory(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Rename", action: #selector(rename(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Copy Full Path", action: #selector(copyPath(_:)), keyEquivalent: ""))

            let del = NSMenuItem(title: "Delete", action: #selector(deleteOne(_:)), keyEquivalent: "")
            menu.addItem(del)

            if !file.isDirectory {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Edit", action: #selector(edit(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Download", action: #selector(downloadOne(_:)), keyEquivalent: ""))
            }

            menu.items.forEach { $0.target = self }
            return menu
        }

        // MARK: Actions
        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < viewModel.files.count else { return }
            let file = viewModel.files[row]
            guard file.isDirectory else { return }
            let fullPath = viewModel.path.hasSuffix("/") ? viewModel.path + file.name : viewModel.path + "/" + file.name
            viewModel.navigate(to: fullPath)
        }

        @objc func handleClick(_ sender: Any?) {
            // 单击仅选择，不进入目录；双击由 handleDoubleClick 处理进入目录
        }

        private func fileForClickedRow() -> RemoteFile? {
            guard let tableView else { return nil }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < viewModel.files.count else { return nil }
            return viewModel.files[row]
        }

        @objc func downloadSelected(_ sender: Any?) {
            viewModel.downloadSelectedFiles()
        }

        @objc func deleteSelected(_ sender: Any?) {
            ErrorHandler.showConfirmation("Delete selected files?".localized) { confirmed in
                if confirmed { self.viewModel.deleteSelectedFiles() }
            }
        }

        @objc func rename(_ sender: Any?) {
            guard let file = fileForClickedRow() else { return }
            DispatchQueue.main.async {
                self.viewModel.activeRenameFile = file
                self.viewModel.isRenameOpen = true
            }
        }

        @objc func copyPath(_ sender: Any?) {
            guard let file = fileForClickedRow() else { return }
            let fullPath = viewModel.path.hasSuffix("/") ? viewModel.path + file.name : viewModel.path + "/" + file.name
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fullPath, forType: .string)
            ToastManager.shared.show(message: "Path copied".localized, type: .success)
        }

        @objc func deleteOne(_ sender: Any?) {
            guard let file = fileForClickedRow() else { return }
            viewModel.deleteFile(file)
        }

        @objc func edit(_ sender: Any?) {
            guard let file = fileForClickedRow() else { return }
            viewModel.editFile(file)
        }

        @objc func downloadOne(_ sender: Any?) {
            guard let file = fileForClickedRow() else { return }
            viewModel.download(file: file)
        }

        @objc func uploadToCurrentDirectory(_ sender: Any?) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                viewModel.uploadFile(from: url)
            }
        }
    }
}

protocol DragSelectTableViewDelegate: AnyObject {
    func dragSelectTableView(_ tableView: DragSelectTableView, menuFor event: NSEvent) -> NSMenu?
}

final class DragSelectTableView: NSTableView {
    weak var dragSelectionDelegate: DragSelectTableViewDelegate?

    private var isDraggingSelection = false
    private var dragAnchorRow: Int?
    private var dragBaseSelection = IndexSet()
    private var dragIsAdditive = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        isDraggingSelection = false
        dragAnchorRow = (row >= 0) ? row : nil
        dragBaseSelection = selectedRowIndexes
        dragIsAdditive = event.modifierFlags.contains(.command)

        // Finder-like: click selects a single row unless cmd/shift modifies.
        if row >= 0 {
            if event.modifierFlags.contains(.shift), let anchor = selectedRowIndexes.first {
                let lower = min(anchor, row)
                let upper = max(anchor, row)
                selectRowIndexes(IndexSet(integersIn: lower...upper), byExtendingSelection: false)
            } else if dragIsAdditive {
                if selectedRowIndexes.contains(row) {
                    let newSel = selectedRowIndexes.subtracting(IndexSet(integer: row))
                    selectRowIndexes(newSel, byExtendingSelection: false)
                } else {
                    selectRowIndexes(selectedRowIndexes.union(IndexSet(integer: row)), byExtendingSelection: false)
                }
            } else {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else {
            selectRowIndexes(IndexSet(), byExtendingSelection: false)
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchorRow else {
            super.mouseDragged(with: event)
            return
        }
        isDraggingSelection = true

        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return }

        let lower = min(anchor, row)
        let upper = max(anchor, row)
        let range = IndexSet(integersIn: lower...upper)

        if dragIsAdditive {
            selectRowIndexes(dragBaseSelection.union(range), byExtendingSelection: false)
        } else {
            selectRowIndexes(range, byExtendingSelection: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingSelection = false
        dragAnchorRow = nil
        dragBaseSelection = IndexSet()
        dragIsAdditive = false
        super.mouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        dragSelectionDelegate?.dragSelectTableView(self, menuFor: event)
    }
}

final class SFTPNameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 13, weight: .regular)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 1
        nameField.font = NSFont.systemFont(ofSize: 12)

        addSubview(iconView)
        addSubview(nameField)

        self.textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with file: RemoteFile) {
        let symbol = file.isDirectory ? "folder.fill" : "doc"
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = file.isDirectory ? NSColor.systemBlue : NSColor.labelColor
        nameField.stringValue = file.name
    }
}
