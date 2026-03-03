import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum TerminalFlowStepType: String, Codable, CaseIterable, Identifiable {
    case command
    case upload

    var id: String { rawValue }
}

enum FlowStepStatus: Equatable {
    case idle
    case running
    case success
    case failed(String)
}

struct TerminalFlowStep: Identifiable, Codable {
    var id = UUID()
    var title: String
    var command: String
    var type: TerminalFlowStepType = .command
    var localPath: String = ""
    var remoteDirectory: String = ""
    var isExecuted: Bool = false
    var status: FlowStepStatus = .idle

    private enum CodingKeys: String, CodingKey {
        case id, title, command, type, localPath, remoteDirectory
    }

    init(id: UUID = UUID(), title: String, command: String, type: TerminalFlowStepType = .command, localPath: String = "", remoteDirectory: String = "", isExecuted: Bool = false) {
        self.id = id
        self.title = title
        self.command = command
        self.type = type
        self.localPath = localPath
        self.remoteDirectory = remoteDirectory
        self.isExecuted = isExecuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        type = try container.decodeIfPresent(TerminalFlowStepType.self, forKey: .type) ?? .command
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath) ?? ""
        remoteDirectory = try container.decodeIfPresent(String.self, forKey: .remoteDirectory) ?? ""
        isExecuted = false
    }
}

struct TerminalFlowGroup: Identifiable, Codable {
    var id = UUID()
    var name: String
    var steps: [TerminalFlowStep]
    var isCollapsed: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, steps, isCollapsed
    }

    init(id: UUID = UUID(), name: String, steps: [TerminalFlowStep], isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.steps = steps
        self.isCollapsed = isCollapsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Group"
        steps = try container.decodeIfPresent([TerminalFlowStep].self, forKey: .steps) ?? []
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }
}

struct TerminalFlowOverlay: View {
    @Binding var isPresented: Bool
    @Binding var groups: [TerminalFlowGroup]
    @Binding var stopOnError: Bool
    let onExecuteStep: (TerminalFlowStep, UUID) -> Void
    let onExecuteGroup: (TerminalFlowGroup) -> Void
    let onExecuteAll: () -> Void
    @State private var searchText: String = ""
    @State private var panelWidth: CGFloat = 520
    @State private var panelHeight: CGFloat = 520
    @State private var resizeStart: CGSize? = nil
    @State private var isHoveringResize: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                headerView
                Divider()
                groupList
            }
            .background(Color.white.opacity(0.95))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                resizeHandle
            }

            bubbleTail
        }
        .frame(width: panelWidth)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerTitleRow
            if isSingleGroupMode {
                compactActionsRow
            } else {
                headerActionsRow
            }
            searchRow
        }
        .padding(12)
    }

    private var headerTitleRow: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .foregroundColor(DesignSystem.Colors.blue)
            Text("Flow")
                .font(.system(size: 13, weight: .semibold))
            if !isSingleGroupMode {
                Text("\(groups.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(10)
            }
            Spacer()

            if !groups.isEmpty && !isSingleGroupMode {
                Button("Clear") {
                    withAnimation {
                        groups.removeAll()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Button(action: { withAnimation { isPresented = false } }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var headerActionsRow: some View {
        HStack(spacing: 8) {
            Button(action: addGroup) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Group")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: toggleAllCollapsed) {
                HStack(spacing: 6) {
                    Image(systemName: allCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    Text(allCollapsed ? "Expand All" : "Collapse All")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(groups.isEmpty)

            Toggle(isOn: $stopOnError) {
                Text("Stop on error")
                    .font(.system(size: 10, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button(action: onExecuteAll) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Run All")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(DesignSystem.Colors.blue)
                .foregroundColor(.white)
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .disabled(groups.isEmpty)
        }
    }

    private var compactActionsRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $stopOnError) {
                Text("Stop on error")
                    .font(.system(size: 10, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Spacer()

            Button(action: addGroup) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Group")
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .font(.system(size: 11, weight: .medium))
            TextField("Search groups or steps", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.Colors.text)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(DesignSystem.Colors.surfaceSecondary)
        .cornerRadius(6)
    }

    private var groupList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach($groups) { $group in
                    if matchesSearch(group: group, query: searchText) {
                        groupCard($group)
                    }
                }
                if !searchText.isEmpty && !hasSearchResults {
                    Text("No matching steps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.vertical, 12)
                }
            }
            .padding(12)
        }
        .frame(height: max(240, panelHeight - 110))
        .background(Color.white.opacity(0.95))
    }

    private var bubbleTail: some View {
        HStack {
            Spacer()
            Triangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 14, height: 8)
                .rotationEffect(.degrees(180))
            Spacer().frame(width: 40)
        }
        .padding(.bottom, -8)
        .zIndex(2)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(6)
            .background(Color.white.opacity(0.9))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
            .padding(8)
            .opacity(isHoveringResize ? 1 : 0.2)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringResize = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeStart == nil {
                            resizeStart = CGSize(width: panelWidth, height: panelHeight)
                        }
                        let base = resizeStart ?? CGSize(width: panelWidth, height: panelHeight)
                        let newWidth = max(420, base.width - value.translation.width)
                        let newHeight = max(320, base.height - value.translation.height)
                        panelWidth = newWidth
                        panelHeight = newHeight
                    }
                    .onEnded { _ in
                        resizeStart = nil
                    }
            )
    }

    private func groupCard(_ group: Binding<TerminalFlowGroup>) -> some View {
        let groupValue = group.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            groupHeaderRow(group)

            if !groupValue.isCollapsed {
                VStack(spacing: 6) {
                    ForEach(groupValue.steps) { step in
                        stepCard(step, groupID: groupValue.id)
                    }
                }
            }
        }
        .padding(isSingleGroupMode ? 6 : 8)
        .background(isSingleGroupMode ? DesignSystem.Colors.surfaceSecondary.opacity(0.6) : DesignSystem.Colors.surface)
        .cornerRadius(isSingleGroupMode ? 8 : 10)
        .overlay(
            RoundedRectangle(cornerRadius: isSingleGroupMode ? 8 : 10)
                .stroke(Color.primary.opacity(isSingleGroupMode ? 0.04 : 0.06), lineWidth: 1)
        )
        .onDrag {
            NSItemProvider(object: groupValue.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            handleGroupDrop(providers, onto: groupValue.id)
        }
    }

    private func groupHeaderRow(_ group: Binding<TerminalFlowGroup>) -> some View {
        let groupValue = group.wrappedValue
        return HStack(spacing: 8) {
            Button(action: { group.isCollapsed.wrappedValue.toggle() }) {
                Image(systemName: groupValue.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField("Group name", text: group.name)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.text)

            Text("\(groupValue.steps.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(10)

            Spacer()

            Button(action: { onExecuteGroup(groupValue) }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    if !isSingleGroupMode {
                        Text("Run")
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.blue)
                .padding(.vertical, 4)
                .padding(.horizontal, isSingleGroupMode ? 6 : 8)
                .background(DesignSystem.Colors.blue.opacity(0.12))
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { addStep(to: groupValue.id) }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isSingleGroupMode {
                Button(action: { removeGroup(groupValue.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, isSingleGroupMode ? 2 : 0)
    }

    private func stepCard(_ step: TerminalFlowStep, groupID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIndicator(for: step.status)

                Picker("", selection: stepTypeBinding(stepID: step.id, groupID: groupID)) {
                    Text("Cmd").tag(TerminalFlowStepType.command)
                    Text("Upload").tag(TerminalFlowStepType.upload)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 92)

                TextField("Step title", text: stepTitleBinding(stepID: step.id, groupID: groupID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.text)

                Spacer()

                Button(action: { moveStep(step.id, in: groupID, direction: -1) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canMoveStep(step.id, in: groupID, direction: -1))

                Button(action: { moveStep(step.id, in: groupID, direction: 1) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canMoveStep(step.id, in: groupID, direction: 1))

                Button(action: { onExecuteStep(step, groupID) }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.blue)
                        .padding(4)
                        .background(DesignSystem.Colors.blue.opacity(0.12))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { removeStep(step.id, from: groupID) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if step.type == .command {
                TextField("Command", text: stepCommandBinding(stepID: step.id, groupID: groupID))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(step.localPath.isEmpty ? "No file selected" : step.localPath)
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button("Choose") {
                            pickLocalFile(for: groupID, stepID: step.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .medium))
                    }
                    TextField("Remote directory (fallback: current path)", text: stepRemoteDirBinding(stepID: step.id, groupID: groupID))
                        .textFieldStyle(.plain)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(DesignSystem.Colors.surfaceSecondary)
                        .cornerRadius(4)
                }
            }

            if case .failed(let message) = step.status {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(isSingleGroupMode ? 6 : 8)
        .background(DesignSystem.Colors.surfaceSecondary)
        .cornerRadius(isSingleGroupMode ? 6 : 8)
    }

    private func addGroup() {
        withAnimation {
            groups.append(TerminalFlowGroup(name: "Group", steps: []))
        }
    }

    private func addStep(to groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        withAnimation {
            groups[index].steps.append(TerminalFlowStep(title: "", command: "", type: .command))
        }
    }

    private func removeStep(_ id: UUID, from groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        withAnimation {
            groups[index].steps.removeAll { $0.id == id }
        }
    }

    private func removeGroup(_ id: UUID) {
        withAnimation {
            groups.removeAll { $0.id == id }
        }
    }

    private func pickLocalFile(for groupID: UUID, stepID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let handleSelection: (URL) -> Void = { url in
            guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
                  let stepIndex = groups[groupIndex].steps.firstIndex(where: { $0.id == stepID })
            else { return }
            groups[groupIndex].steps[stepIndex].localPath = url.path
            if groups[groupIndex].steps[stepIndex].title.isEmpty {
                groups[groupIndex].steps[stepIndex].title = url.lastPathComponent
            }
        }

        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    handleSelection(url)
                }
            }
        } else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    handleSelection(url)
                }
            }
        }
    }

    // MARK: - Drag & Drop Helpers
    private func handleGroupDrop(_ providers: [NSItemProvider], onto targetID: UUID) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let str = object as? String, let sourceID = UUID(uuidString: str) else { return }
            DispatchQueue.main.async {
                guard let from = groups.firstIndex(where: { $0.id == sourceID }),
                      let to = groups.firstIndex(where: { $0.id == targetID }),
                      from != to else { return }
                let item = groups.remove(at: from)
                groups.insert(item, at: to)
            }
        }
        return true
    }

    private func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    @ViewBuilder
    private func statusIndicator(for status: FlowStepStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .running:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 14, height: 14)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.red)
        }
    }

    private func stepTypeBinding(stepID: UUID, groupID: UUID) -> Binding<TerminalFlowStepType> {
        Binding(
            get: { stepValue(stepID: stepID, groupID: groupID)?.type ?? .command },
            set: { newValue in
                updateStep(stepID: stepID, groupID: groupID) { $0.type = newValue }
            }
        )
    }

    private func stepTitleBinding(stepID: UUID, groupID: UUID) -> Binding<String> {
        Binding(
            get: { stepValue(stepID: stepID, groupID: groupID)?.title ?? "" },
            set: { newValue in
                updateStep(stepID: stepID, groupID: groupID) { $0.title = newValue }
            }
        )
    }

    private func stepCommandBinding(stepID: UUID, groupID: UUID) -> Binding<String> {
        Binding(
            get: { stepValue(stepID: stepID, groupID: groupID)?.command ?? "" },
            set: { newValue in
                updateStep(stepID: stepID, groupID: groupID) { $0.command = newValue }
            }
        )
    }

    private func stepRemoteDirBinding(stepID: UUID, groupID: UUID) -> Binding<String> {
        Binding(
            get: { stepValue(stepID: stepID, groupID: groupID)?.remoteDirectory ?? "" },
            set: { newValue in
                updateStep(stepID: stepID, groupID: groupID) { $0.remoteDirectory = newValue }
            }
        )
    }

    private func stepValue(stepID: UUID, groupID: UUID) -> TerminalFlowStep? {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let stepIndex = groups[groupIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return nil }
        return groups[groupIndex].steps[stepIndex]
    }

    private func updateStep(stepID: UUID, groupID: UUID, update: (inout TerminalFlowStep) -> Void) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let stepIndex = groups[groupIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }
        update(&groups[groupIndex].steps[stepIndex])
    }

    private func stepIndex(stepID: UUID, groupID: UUID) -> Int? {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return nil }
        return groups[groupIndex].steps.firstIndex(where: { $0.id == stepID })
    }

    private func canMoveStep(_ stepID: UUID, in groupID: UUID, direction: Int) -> Bool {
        guard let index = stepIndex(stepID: stepID, groupID: groupID),
              let groupIndex = groups.firstIndex(where: { $0.id == groupID })
        else { return false }
        let targetIndex = index + direction
        return targetIndex >= 0 && targetIndex < groups[groupIndex].steps.count
    }

    private func moveStep(_ stepID: UUID, in groupID: UUID, direction: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let index = groups[groupIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }
        let targetIndex = index + direction
        guard targetIndex >= 0 && targetIndex < groups[groupIndex].steps.count else { return }
        withAnimation {
            groups[groupIndex].steps.swapAt(index, targetIndex)
        }
    }

    private var allCollapsed: Bool {
        !groups.isEmpty && groups.allSatisfy { $0.isCollapsed }
    }

    private func toggleAllCollapsed() {
        let target = !allCollapsed
        for index in groups.indices {
            groups[index].isCollapsed = target
        }
    }

    private var isSingleGroupMode: Bool {
        groups.count == 1
    }

    private var hasSearchResults: Bool {
        groups.contains { matchesSearch(group: $0, query: searchText) }
    }

    private func matchesSearch(group: TerminalFlowGroup, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if group.name.lowercased().contains(lower) { return true }
        for step in group.steps {
            if step.title.lowercased().contains(lower) { return true }
            if step.command.lowercased().contains(lower) { return true }
            if step.localPath.lowercased().contains(lower) { return true }
            if step.remoteDirectory.lowercased().contains(lower) { return true }
        }
        return false
    }
}
