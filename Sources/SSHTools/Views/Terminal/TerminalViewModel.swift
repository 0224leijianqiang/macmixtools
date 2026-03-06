import SwiftUI
import Combine
import Citadel

class TerminalViewModel: ObservableObject {
    let connection: SSHConnection
    @Published var runner: SSHRunner
    @Published var monitorService: SystemMonitorService
    
    // Layout State
    @Published var sftpHeight: CGFloat = DesignSystem.Layout.sftpDefaultHeight
    @Published var lastSftpHeight: CGFloat = DesignSystem.Layout.sftpDefaultHeight
    @Published var isSFTPViewExpanded = true
    @Published var isDragging = false
    @Published var dragOffset: CGFloat = 0
    
    // AI Helper State
    @Published var showAIHelper = false
    @Published var aiPrompt = ""
    @Published var isAIGenerating = false
    @Published var aiSteps: [AIStep] = []

    /// 底部面板 tab：文件夹 或 Flow 任务
    enum BottomPanelTab: String, CaseIterable {
        case folder
        case flow
    }
    @Published var bottomPanelTab: BottomPanelTab = .folder
    @Published var showFlowPanel = false
    @Published var flowGroups: [TerminalFlowGroup] = []
    @Published var isFlowRunning = false
    @Published var stopFlowOnError = true
    
    @Published var showSuccessBanner = false
    
    private var cancellables = Set<AnyCancellable>()
    private var flowExecutionTask: Task<Void, Never>?
    private let flowStorageKey: String
    private let stopOnErrorKey: String
    
    init(connection: SSHConnection) {
        self.connection = connection
        let runner = SSHRunner()
        self.runner = runner
        self.monitorService = SystemMonitorService(runner: runner)
        let baseKey = "sshtools.flow.\(connection.id.uuidString)"
        self.flowStorageKey = baseKey + ".groups"
        self.stopOnErrorKey = baseKey + ".stopOnError"
        loadFlowSteps()
        
        // Forward runner changes to ViewModel to trigger View updates
        runner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Forward monitorService changes (isVisible 等) 到 ViewModel，否则 TerminalView 不会在弹窗开/关时重绘
        monitorService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        // Handle success banner
        runner.$isConnected
            .sink { [weak self] connected in
                if connected {
                    self?.showSuccessBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            self?.showSuccessBanner = false
                        }
                    }
                }
            }
            .store(in: &cancellables)

        $flowGroups
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveFlowSteps()
            }
            .store(in: &cancellables)

        $stopFlowOnError
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.saveFlowSteps()
            }
            .store(in: &cancellables)

    }
    
    deinit {
        cancellables.removeAll()
        // Essential for resource recovery when tab is closed
        runner.disconnect()
        monitorService.stopMonitoring()
    }
    
    func connect() {
        if !runner.isConnected {
            runner.connect(connection: connection)
        }
    }
    
    func disconnect() {
        runner.disconnect()
        monitorService.stopMonitoring()
    }
    
    func toggleMonitor() {
        withAnimation {
            monitorService.toggle()
        }
    }
    
    func diagnoseError() {
        let lastOutput = runner.getLastOutput()
        guard !lastOutput.isEmpty else { 
            ToastManager.shared.show(message: "No terminal output to analyze", type: .warning)
            return 
        }
        
        showAIHelper = true
        isAIGenerating = true
        aiSteps = []
        aiPrompt = "Analyzing terminal output for errors..."
        
        Task {
            do {
                let sysInfo = await runner.detectSystemInfo()
                let prompt = "The user is seeing the following output in their terminal. If there is an error, please explain what it means and provide steps to fix it. If there is no error, summarize the current status.\n\nTerminal Output:\n\(lastOutput)"
                
                let response = try await GeminiService.shared.generateCommand(prompt: prompt, context: sysInfo)
                
                await MainActor.run {
                    self.isAIGenerating = false
                    self.aiPrompt = "Error Analysis"
                    
                    // Try to parse as steps if LLM was clever enough, otherwise treat as one long explanation
                    if let data = response.data(using: .utf8),
                       let steps = try? JSONDecoder().decode([AIStep].self, from: data) {
                        withAnimation {
                            self.aiSteps = steps
                        }
                    } else {
                        // Create a temporary step for the explanation
                        let explanation = AIStep(desc: response, cmd: "# Analysis Result")
                        withAnimation {
                            self.aiSteps = [explanation]
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAIGenerating = false
                    ToastManager.shared.show(message: error.localizedDescription, type: .error)
                }
            }
        }
    }
    
    func generateAICommand() {
        guard !aiPrompt.isEmpty else { return }
        isAIGenerating = true
        aiSteps = [] 
        
        Task {
            do {
                let sysInfo = await runner.detectSystemInfo()
                let response = try await GeminiService.shared.generateCommand(prompt: aiPrompt, context: sysInfo)
                
                await MainActor.run {
                    self.isAIGenerating = false
                    
                    if let data = response.data(using: .utf8),
                       let steps = try? JSONDecoder().decode([AIStep].self, from: data) {
                        withAnimation {
                            self.aiSteps = steps
                        }
                    } else {
                        // Fallback: Single command mode
                        self.runner.sendRaw(response)
                        
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(response, forType: .string)
                        
                        self.showAIHelper = false
                        self.aiPrompt = ""
                        ToastManager.shared.show(message: "Command generated & copied".localized, type: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAIGenerating = false
                    ToastManager.shared.show(message: error.localizedDescription, type: .error)
                }
            }
        }
    }
    
    func executeAIStep(_ step: AIStep) {
        runner.sendRaw(step.cmd + "\r")
        if let index = aiSteps.firstIndex(where: { $0.id == step.id }) {
            withAnimation {
                aiSteps[index].isExecuted = true
            }
        }
    }

    func executeFlowStep(_ step: TerminalFlowStep, in groupID: UUID) {
        flowExecutionTask?.cancel()
        flowExecutionTask = Task { [weak self] in
            await self?.resetFlowStepStatus(step.id, in: groupID)
            await self?.setFlowRunning(true)
            _ = await self?.runFlowStep(step, in: groupID)
            await self?.setFlowRunning(false)
        }
    }

    func executeFlowGroup(_ group: TerminalFlowGroup) {
        flowExecutionTask?.cancel()
        flowExecutionTask = Task { [weak self] in
            await self?.resetFlowGroupStatus(group.id)
            await self?.setFlowRunning(true)
            _ = await self?.runFlowSteps(group.steps, in: group.id)
            await self?.setFlowRunning(false)
        }
    }

    func executeAllFlowGroups() {
        flowExecutionTask?.cancel()
        flowExecutionTask = Task { [weak self] in
            guard let self else { return }
            await resetAllFlowStatuses()
            await setFlowRunning(true)
            for group in self.flowGroups {
                if Task.isCancelled { break }
                let shouldContinue = await self.runFlowSteps(group.steps, in: group.id)
                if Task.isCancelled || (!shouldContinue && self.stopFlowOnError) { break }
            }
            await setFlowRunning(false)
        }
    }
    
    func updateLayout(translation: CGFloat, isEnded: Bool) {
        if isEnded {
            isDragging = false
            let calculatedHeight = sftpHeight - translation
            dragOffset = 0
            
            if calculatedHeight > (DesignSystem.Layout.sftpCollapsedHeight + 10) {
                isSFTPViewExpanded = true
                lastSftpHeight = calculatedHeight
                sftpHeight = calculatedHeight
            } else {
                isSFTPViewExpanded = false
                sftpHeight = DesignSystem.Layout.sftpCollapsedHeight
            }
        } else {
            isDragging = true
            dragOffset = translation
        }
    }
    
    func toggleSFTP(expanded: Bool) {
        withAnimation {
            isSFTPViewExpanded = expanded
            if expanded {
                sftpHeight = max(lastSftpHeight, 200)
            } else {
                lastSftpHeight = max(sftpHeight, 200)
                sftpHeight = DesignSystem.Layout.sftpCollapsedHeight
            }
        }
    }

    private func loadFlowSteps() {
        if let stored = UserDefaults.standard.object(forKey: stopOnErrorKey) as? Bool {
            stopFlowOnError = stored
        }

        if let data = UserDefaults.standard.data(forKey: flowStorageKey) {
            if let decoded = try? JSONDecoder().decode([TerminalFlowGroup].self, from: data) {
                flowGroups = decoded
                return
            }
            if let decodedSteps = try? JSONDecoder().decode([TerminalFlowStep].self, from: data) {
                flowGroups = [TerminalFlowGroup(name: "Default", steps: decodedSteps)]
                return
            }
        }

        // Legacy fallback: migrate old global storage if present
        if let legacy = UserDefaults.standard.data(forKey: "sshtools.flow.global"),
           let decoded = try? JSONDecoder().decode([TerminalFlowGroup].self, from: legacy) {
            flowGroups = decoded
        }
    }

    private func saveFlowSteps() {
        guard let data = try? JSONEncoder().encode(flowGroups) else { return }
        UserDefaults.standard.set(data, forKey: flowStorageKey)
        UserDefaults.standard.set(stopFlowOnError, forKey: stopOnErrorKey)
    }

    private func runFlowSteps(_ steps: [TerminalFlowStep], in groupID: UUID) async -> Bool {
        var allSucceeded = true
        for step in steps {
            if Task.isCancelled { return false }
            let success = await runFlowStep(step, in: groupID)
            allSucceeded = allSucceeded && success
            if stopFlowOnError && !success { return false }
        }
        return allSucceeded
    }

    private func runFlowStep(_ step: TerminalFlowStep, in groupID: UUID) async -> Bool {
        await MainActor.run {
            self.setFlowStepStatus(step.id, in: groupID, status: .running)
        }
        switch step.type {
        case .command:
            let trimmed = step.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                await MainActor.run {
                    self.setFlowStepStatus(step.id, in: groupID, status: .failed("命令为空"))
                }
                return false
            }
            await MainActor.run {
                self.runner.sendRaw(trimmed + "\r")
                self.setFlowStepStatus(step.id, in: groupID, status: .success)
            }
            return true

        case .upload:
            let trimmed = step.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await MainActor.run {
                    ToastManager.shared.show(message: "请选择要上传的文件", type: .warning)
                    self.setFlowStepStatus(step.id, in: groupID, status: .failed("未选择文件"))
                }
                return false
            }
            guard let sftp = await MainActor.run(resultType: SFTPClient?.self, body: { self.runner.sftp }) else {
                await MainActor.run {
                    ToastManager.shared.show(message: "SFTP 未连接", type: .error)
                    self.setFlowStepStatus(step.id, in: groupID, status: .failed("SFTP 未连接"))
                }
                return false
            }
            let base = step.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBase: String
            if !base.isEmpty {
                resolvedBase = base
            } else {
                let runnerPath = await MainActor.run { self.runner.currentPath }
                resolvedBase = runnerPath.isEmpty ? "/" : runnerPath
            }
            let remoteDir = resolvedBase
            let fileName = URL(fileURLWithPath: trimmed).lastPathComponent
            let remotePath = remoteDir.hasSuffix("/") ? remoteDir + fileName : remoteDir + "/" + fileName
            do {
                try await SFTPService.shared.upload(sftp: sftp, localURL: URL(fileURLWithPath: trimmed), remotePath: remotePath)
                await MainActor.run {
                    self.setFlowStepStatus(step.id, in: groupID, status: .success)
                }
                return true
            } catch {
                await MainActor.run {
                    ToastManager.shared.show(message: error.localizedDescription, type: .error)
                    self.setFlowStepStatus(step.id, in: groupID, status: .failed(error.localizedDescription))
                }
                return false
            }
        }
    }

    @MainActor
    private func setFlowStepStatus(_ stepID: UUID, in groupID: UUID, status: FlowStepStatus) {
        if let groupIndex = flowGroups.firstIndex(where: { $0.id == groupID }),
           let stepIndex = flowGroups[groupIndex].steps.firstIndex(where: { $0.id == stepID }) {
            withAnimation {
                flowGroups[groupIndex].steps[stepIndex].status = status
                if case .success = status {
                    flowGroups[groupIndex].steps[stepIndex].isExecuted = true
                }
            }
        }
    }

    @MainActor
    private func resetFlowGroupStatus(_ groupID: UUID) {
        guard let index = flowGroups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in flowGroups[index].steps.indices {
            flowGroups[index].steps[i].status = .idle
            flowGroups[index].steps[i].isExecuted = false
        }
    }

    @MainActor
    private func resetAllFlowStatuses() {
        for gid in flowGroups.map(\.id) {
            resetFlowGroupStatus(gid)
        }
    }

    @MainActor
    private func resetFlowStepStatus(_ stepID: UUID, in groupID: UUID) {
        if let groupIndex = flowGroups.firstIndex(where: { $0.id == groupID }),
           let stepIndex = flowGroups[groupIndex].steps.firstIndex(where: { $0.id == stepID }) {
            flowGroups[groupIndex].steps[stepIndex].status = .idle
            flowGroups[groupIndex].steps[stepIndex].isExecuted = false
        }
    }

    @MainActor
    private func setFlowRunning(_ running: Bool) {
        withAnimation {
            isFlowRunning = running
        }
    }
}
