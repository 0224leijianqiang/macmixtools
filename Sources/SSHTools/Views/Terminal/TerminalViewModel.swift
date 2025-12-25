import SwiftUI
import Combine

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
    
    @Published var showSuccessBanner = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init(connection: SSHConnection) {
        self.connection = connection
        let runner = SSHRunner()
        self.runner = runner
        self.monitorService = SystemMonitorService(runner: runner)
        
        // Forward runner changes to ViewModel to trigger View updates
        runner.objectWillChange
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
    }
    
    deinit {
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
    
    func updateLayout(translation: CGFloat, isEnded: Bool) {
        if isEnded {
            isDragging = false
            let calculatedHeight = sftpHeight - translation
            dragOffset = 0
            
            if calculatedHeight > (DesignSystem.Layout.sftpMinHeight + 10) {
                isSFTPViewExpanded = true
                lastSftpHeight = calculatedHeight
                sftpHeight = calculatedHeight
            } else {
                isSFTPViewExpanded = false
                sftpHeight = DesignSystem.Layout.sftpMinHeight
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
                sftpHeight = DesignSystem.Layout.sftpMinHeight
            }
        }
    }
}
