import SwiftUI

func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

struct ListEditor: View {
    let list: [String]
    var onUpdate: (Int, String) -> Void
    var onAdd: ((String) -> Void)?
    var onDelete: ((Int) -> Void)?
    
    struct ListEditTarget: Identifiable {
        let id = UUID()
        let index: Int
        let value: String
    }
    
    @State private var editingTarget: ListEditTarget?
    @State private var isAdding = false
    @State private var indexSortAscending: Bool? = true
    @State private var valueSortAscending: Bool? = nil
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var cachedSortedList: [(index: Int, value: String)] = []
    @State private var lastListCount: Int = 0
    @State private var lastIndexSort: Bool? = nil
    @State private var lastValueSort: Bool? = nil

    private func updateCachedList() {
        var indexed = list.enumerated().map { (index: $0.offset, value: $0.element) }
        
        if let indexSort = indexSortAscending {
            indexed.sort { item1, item2 in indexSort ? item1.index < item2.index : item1.index > item2.index }
        } else if let valueSort = valueSortAscending {
            indexed.sort { item1, item2 in valueSort ? item1.value < item2.value : item1.value > item2.value }
        }
        
        if !debouncedSearchText.isEmpty {
            indexed = indexed.filter { $0.value.localizedCaseInsensitiveContains(debouncedSearchText) }
        }
        
        cachedSortedList = indexed
        lastListCount = list.count
        lastIndexSort = indexSortAscending
        lastValueSort = valueSortAscending
    }
    
    private var sortedList: [(index: Int, value: String)] {
        return cachedSortedList
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isAdding = true }) {
                    Label("Add Row", systemImage: "plus")
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.surface)
            
            Divider() 
            
            List {
                // 表头
                HStack(spacing: 0) {
                    Text("Index")
                        .font(DesignSystem.Typography.caption.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                        .padding(.leading, DesignSystem.Spacing.medium)
                    
                    Divider() 
                    
                    HStack {
                        Text("Value")
                            .font(DesignSystem.Typography.caption.weight(.bold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Button(action: {
                            if valueSortAscending == true { valueSortAscending = false }
                            else { valueSortAscending = true }
                            indexSortAscending = nil
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
                .frame(height: DesignSystem.Layout.headerHeight)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                
                ForEach(sortedList, id: \.index) { item in
                    HStack(spacing: 0) {
                        Text("\(item.index)")
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 80, alignment: .leading)
                            .padding(.leading, DesignSystem.Spacing.medium)
                        
                        Divider() 
                        
                        HStack {
                            Text(item.value)
                                .font(DesignSystem.Typography.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                .clipped()
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("Copy Value") {
                                        copyToPasteboard(item.value)
                                    }
                                }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    copyToPasteboard(item.value)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.blue)
                                .accessibilityLabel("Copy")
                                .help("Copy Value")
                                
                                Button(action: {
                                    editingTarget = ListEditTarget(index: item.index, value: item.value)
                                }) {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.blue)
                                .accessibilityLabel("Edit")
                                .help("Edit")
                                
                                Button(action: { onDelete?(item.index) }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.pink)
                                .accessibilityLabel("Delete")
                                .help("Delete")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.leading, DesignSystem.Spacing.medium)
                        .padding(.trailing, DesignSystem.Spacing.medium)
                    }
                    .frame(height: DesignSystem.Layout.rowHeight + 8)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            updateCachedList()
        }
        .onChange(of: list) { oldValue, _ in
            updateCachedList()
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.UI.searchDebounceInterval * 1_000_000_000))
                if debouncedSearchText != newValue {
                    debouncedSearchText = newValue
                    updateCachedList()
                }
            }
        }
        .onChange(of: debouncedSearchText) { oldValue, _ in
            updateCachedList()
        }
        .onChange(of: indexSortAscending) { oldValue, _ in
            updateCachedList()
        }
        .onChange(of: valueSortAscending) { oldValue, _ in
            updateCachedList()
        }
        .sheet(item: $editingTarget) { target in
            ValueEditorSheet(
                mode: .listItem(index: target.index, value: target.value),
                onSave: { newValue in
                    onUpdate(target.index, newValue)
                    editingTarget = nil
                }
            )
        }
        .sheet(isPresented: $isAdding) {
            ValueEditorSheet(
                mode: .listNewItem,
                onSave: { newValue in
                    onAdd?(newValue)
                    isAdding = false
                }
            )
        }
    }
}

struct StringEditor: View {
    let value: String
    var onSave: (String) -> Void
    
    @State private var editedValue: String
    
    init(value: String, onSave: @escaping (String) -> Void) {
        self.value = value
        self.onSave = onSave
        _editedValue = State(initialValue: value)
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            TextEditor(text: $editedValue)
                .font(DesignSystem.Typography.monospace)
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(DesignSystem.Radius.small)
            
            HStack {
                Spacer()
                Button("Save Changes") {
                    onSave(editedValue)
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
                .disabled(editedValue == value)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .onChange(of: value) { oldValue, newValue in
            editedValue = newValue
        }
    }
}

struct SetEditor: View {
    let items: [String]
    var onUpdate: (String, String) -> Void
    var onAdd: (String) -> Void
    var onDelete: (String) -> Void
    
    struct SetEditTarget: Identifiable {
        let id = UUID()
        let value: String
    }
    
    @State private var editingTarget: SetEditTarget?
    @State private var isAdding = false
    @State private var sortAscending: Bool? = true
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var cachedSortedItems: [(id: Int, value: String)] = []
    @State private var lastItemsCount: Int = 0
    @State private var lastSortAscending: Bool? = nil
    
    private func updateCachedItems() {
        var filtered = items
        if !debouncedSearchText.isEmpty {
            filtered = items.filter { $0.localizedCaseInsensitiveContains(debouncedSearchText) }
        }
        
        var sorted = filtered
        if let ascending = sortAscending {
            sorted = ascending ? filtered.sorted() : filtered.sorted(by: >)
        }
        cachedSortedItems = sorted.enumerated().map { (id: $0.offset, value: $0.element) }
        lastItemsCount = items.count
        lastSortAscending = sortAscending
    }
    
    private var sortedItems: [(id: Int, value: String)] {
        return cachedSortedItems
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isAdding = true }) {
                    Label("Add Member", systemImage: "plus")
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.tiny) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.caption)
                        .frame(width: 120)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.background.opacity(0.5))
                .cornerRadius(DesignSystem.Radius.small)
            }
            .padding(DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.surface)
            
            Divider() 
            
            List {
                // 表头
                HStack(spacing: 0) {
                    Text("ID")
                        .font(DesignSystem.Typography.caption.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 60, alignment: .leading)
                        .padding(.leading, DesignSystem.Spacing.medium)
                    
                    Divider() 
                    
                    HStack {
                        Text("Member")
                            .font(DesignSystem.Typography.caption.weight(.bold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Button(action: { 
                            if sortAscending == true {
                                sortAscending = false
                            } else {
                                sortAscending = true
                            }
                        }) {
                            Image(systemName: sortAscending == true ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9))
                                .foregroundColor(DesignSystem.Colors.blue)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer() 
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DesignSystem.Spacing.medium)
                    .padding(.trailing, DesignSystem.Spacing.medium)
                }
                .frame(height: DesignSystem.Layout.headerHeight)
                .background(Color.gray.opacity(0.1))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                
                ForEach(sortedItems, id: \.value) { item in
                    HStack(spacing: 0) {
                        Text("\(item.id + 1)")
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 60, alignment: .leading)
                            .padding(.leading, DesignSystem.Spacing.medium)
                        
                        Divider() 
                        
                        HStack {
                            Text(item.value)
                                .font(DesignSystem.Typography.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                .clipped()
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("Copy Member") {
                                        copyToPasteboard(item.value)
                                    }
                                }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    copyToPasteboard(item.value)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.blue)
                                .padding(4)
                                .accessibilityLabel("Copy")
                                .help("Copy")
                                
                                Button(action: {
                                    editingTarget = SetEditTarget(value: item.value)
                                }) {
                                    Image(systemName: "pencil")
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.blue)
                                .padding(4)
                                .accessibilityLabel("Edit")
                                .help("Edit")
                                
                                Button(action: { 
                                    onDelete(item.value) 
                                }) {
                                    Image(systemName: "trash")
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.pink)
                                .padding(4)
                                .accessibilityLabel("Delete")
                                .help("Delete")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.leading, DesignSystem.Spacing.medium)
                        .padding(.trailing, DesignSystem.Spacing.medium)
                    }
                    .frame(height: DesignSystem.Layout.rowHeight + 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            updateCachedItems()
        }
        .onChange(of: items) { oldValue, _ in
            updateCachedItems()
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.UI.searchDebounceInterval * 1_000_000_000))
                if debouncedSearchText != newValue {
                    debouncedSearchText = newValue
                    updateCachedItems()
                }
            }
        }
        .onChange(of: debouncedSearchText) { oldValue, _ in
            updateCachedItems()
        }
        .onChange(of: sortAscending) { oldValue, _ in
            updateCachedItems()
        }
        .sheet(item: $editingTarget) { target in
            ValueEditorSheet(mode: .setItem(value: target.value)) { newValue in
                onUpdate(target.value, newValue)
                editingTarget = nil
            }
        }
        .sheet(isPresented: $isAdding) {
            ValueEditorSheet(mode: .setNewItem) { value in
                onAdd(value)
                isAdding = false
            }
        }
    }
}

struct ZSetEditor: View {
    let items: [(member: String, score: Double)]
    var onUpdate: (String, Double) -> Void
    var onDelete: (String) -> Void
    
    struct ZSetEditTarget: Identifiable {
        let id = UUID()
        let member: String
        let score: Double
    }
    
    @State private var editingTarget: ZSetEditTarget?
    @State private var scoreSortAscending: Bool? = true
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var cachedSortedItems: [(id: Int, member: String, score: Double)] = []
    @State private var lastItemsCount: Int = 0
    @State private var lastScoreSort: Bool? = nil
    
    private func updateCachedItems() {
        var filtered = items
        if !debouncedSearchText.isEmpty {
            filtered = items.filter { $0.member.localizedCaseInsensitiveContains(debouncedSearchText) }
        }
        
        if let scoreSort = scoreSortAscending {
            filtered.sort { item1, item2 in scoreSort ? item1.score < item2.score : item1.score > item2.score }
        }
        
        cachedSortedItems = filtered.enumerated().map { (id: $0.offset, member: $0.element.member, score: $0.element.score) }
        lastItemsCount = items.count
        lastScoreSort = scoreSortAscending
    }
    
    private var sortedItems: [(id: Int, member: String, score: Double)] {
        return cachedSortedItems
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: DesignSystem.Spacing.tiny) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.caption)
                        .frame(width: 120)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.background.opacity(0.5))
                .cornerRadius(DesignSystem.Radius.small)
            }
            .padding(DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.surface)
            
            Divider() 
            
            List {
                // 表头
                HStack(spacing: 0) {
                    Text("ID")
                        .font(DesignSystem.Typography.caption.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 60, alignment: .leading)
                        .padding(.leading, DesignSystem.Spacing.medium)
                    
                    Divider() 
                    
                    Text("Member")
                        .font(DesignSystem.Typography.caption.weight(.bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 200, alignment: .leading)
                        .padding(.leading, DesignSystem.Spacing.medium)
                    
                    Divider() 
                    
                    HStack {
                        Text("Score")
                            .font(DesignSystem.Typography.caption.weight(.bold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Button(action: { 
                            if scoreSortAscending == true {
                                scoreSortAscending = false
                            } else {
                                scoreSortAscending = true
                            }
                        }) {
                            Image(systemName: scoreSortAscending == true ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9))
                                .foregroundColor(DesignSystem.Colors.blue)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer() 
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DesignSystem.Spacing.medium)
                    .padding(.trailing, DesignSystem.Spacing.medium)
                }
                .frame(height: DesignSystem.Layout.headerHeight)
                .background(Color.gray.opacity(0.1))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                
                ForEach(sortedItems, id: \.member) { item in
                    HStack(spacing: 0) {
                        Text("\(item.id + 1)")
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 60, alignment: .leading)
                            .padding(.leading, DesignSystem.Spacing.medium)
                        
                        Divider() 
                        
                        Text(item.member)
                            .font(DesignSystem.Typography.body)
                            .frame(width: 200, alignment: .leading)
                            .padding(.leading, DesignSystem.Spacing.medium)
                        
                        Divider() 
                        
                        Text(String(format: "%.2f", item.score))
                            .font(DesignSystem.Typography.monospace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, DesignSystem.Spacing.medium)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                editingTarget = ZSetEditTarget(member: item.member, score: item.score)
                            }) {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.blue)
                            .accessibilityLabel("Edit")
                            
                            Button(action: { onDelete(item.member) }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.pink)
                            .accessibilityLabel("Delete")
                        }
                        .padding(.trailing, DesignSystem.Spacing.medium)
                    }
                    .frame(height: DesignSystem.Layout.rowHeight + 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            updateCachedItems()
        }
        .onChange(of: items.count) { oldValue, newCount in
            if newCount != lastItemsCount {
                updateCachedItems()
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.UI.searchDebounceInterval * 1_000_000_000))
                if debouncedSearchText != newValue {
                    debouncedSearchText = newValue
                    updateCachedItems()
                }
            }
        }
        .onChange(of: debouncedSearchText) { oldValue, _ in
            updateCachedItems()
        }
        .onChange(of: scoreSortAscending) { oldValue, _ in
            updateCachedItems()
        }
        .sheet(item: $editingTarget) { target in
            ZSetScoreEditorSheet(
                member: target.member,
                currentScore: target.score,
                onSave: { newScore in
                    onUpdate(target.member, newScore)
                    editingTarget = nil
                },
                onCancel: {
                    editingTarget = nil
                }
            )
        }
    }
}

struct ZSetScoreEditorSheet: View {
    let member: String
    let currentScore: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void
    
    @State private var newScore: Double
    @Environment(\.dismiss) var dismiss
    
    init(member: String, currentScore: Double, onSave: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.member = member
        self.currentScore = currentScore
        self.onSave = onSave
        self.onCancel = onCancel
        _newScore = State(initialValue: currentScore)
    }
    
    var body: some View {
        SheetScaffold(
            title: "Edit Score",
            subtitle: member,
            minSize: NSSize(width: 460, height: 260),
            onClose: {
                onCancel()
                dismiss()
            }
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Current Score: \(String(format: "%.2f", currentScore))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                TextField("New Score", value: $newScore, formatter: NumberFormatter())
                    .textFieldStyle(ModernTextFieldStyle())
            }
            .padding()
        } footer: {
            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .secondary))

                Spacer()

                Button("Save") {
                    onSave(newScore)
                    dismiss()
                }
                .buttonStyle(ModernButtonStyle(variant: .primary))
            }
        }
    }
}

extension Bool {
    mutating func toggle() {
        self = !self
    }
}
