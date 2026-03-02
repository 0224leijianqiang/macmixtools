import SwiftUI
import AppKit

struct TerminalView: View {
    @ObservedObject private var viewModel: TerminalViewModel
    @Namespace private var bottomID
    
    private let tabID: UUID

    init(connection: SSHConnection, tabID: UUID) {
        _viewModel = ObservedObject(wrappedValue: TerminalViewModelStore.shared.viewModel(for: connection))
        self.tabID = tabID
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let splitterHeight: CGFloat = DesignSystem.Layout.terminalSplitterHeight
            
            // 计算高度
            let maxSftpHeight = totalHeight - DesignSystem.Layout.terminalMinHeight - splitterHeight
            let constrainedSftpHeight = min(max(viewModel.sftpHeight, DesignSystem.Layout.sftpMinHeight), max(maxSftpHeight, DesignSystem.Layout.sftpMinHeight))
            let terminalHeight = max(0, totalHeight - constrainedSftpHeight - splitterHeight)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal.fill")
                                .foregroundColor(DesignSystem.Colors.blue)
                            Text(viewModel.connection.name)
                                .font(.headline)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Button(action: {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString("\(viewModel.connection.effectiveUsername)@\(viewModel.connection.host)", forType: .string)
                            }) {
                                Text("\(viewModel.connection.effectiveUsername)@\(viewModel.connection.host)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.surfaceSecondary)
                            .cornerRadius(8)

                            if !viewModel.runner.currentPath.isEmpty {
                                Button(action: {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(viewModel.runner.currentPath, forType: .string)
                                }) {
                                    Text(viewModel.runner.currentPath)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.surfaceSecondary)
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Connection Status
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            statusDot
                            Text(statusText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Button(action: copyLastOutput) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.blue)
                            .help("Copy last output")
                            if !viewModel.runner.isConnected && !viewModel.runner.isConnecting {
                                Button("Reconnect") {
                                    viewModel.connect()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.blue)
                            }
                        }

                        if let error = viewModel.runner.error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .cornerRadius(DesignSystem.Radius.small)
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .frame(height: 48)
                .background(DesignSystem.Colors.surface)
                
                Divider()

                // 1. 终端区域
                ZStack(alignment: .topTrailing) {
                    XTermWebView(runner: viewModel.runner, tabID: tabID)
                        .frame(height: terminalHeight)
                        .background(Color.black)
                        .clipped()
                        .allowsHitTesting(true)
                        .zIndex(0)

                    // Reconnect overlay when connection drops
                    ReconnectOverlay(
                        isConnected: viewModel.runner.isConnected,
                        isConnecting: viewModel.runner.isConnecting,
                        error: viewModel.runner.error,
                        onReconnect: { viewModel.connect() }
                    )
                    .frame(height: terminalHeight)
                    .zIndex(25)
                    
                    // 悬浮按钮组 - 右上角
                    HStack(alignment: .top, spacing: 8) {
                        if viewModel.monitorService.isVisible {
                            SystemMonitorView(service: viewModel.monitorService)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .allowsHitTesting(true)
                        }
                        
                        Button(action: { 
                            withAnimation(.spring()) {
                                viewModel.toggleMonitor() 
                            }
                        }) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 14))
                                .foregroundColor(viewModel.monitorService.isVisible ? .blue : .white.opacity(0.6))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(true)
                    }
                    .padding(10)
                    .allowsHitTesting(false) // Container doesn't block, only buttons inside do
                    .zIndex(10)
                    
                    // Quick Actions - 右下角
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Button(action: { 
                                    withAnimation(.spring()) {
                                        viewModel.showFlowPanel.toggle()
                                        if viewModel.showFlowPanel {
                                            viewModel.showAIHelper = false
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle")
                                        Text("Flow")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.showFlowPanel ? DesignSystem.Colors.blue : DesignSystem.Colors.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(true)

                                Button(action: { 
                                    withAnimation(.spring()) {
                                        viewModel.showAIHelper.toggle()
                                        if viewModel.showAIHelper {
                                            viewModel.showFlowPanel = false
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                        Text("AI Assistant".localized)
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.showAIHelper ? Color.purple : Color.purple.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .allowsHitTesting(true)
                            }
                            .padding(20)
                        }
                    }
                    .zIndex(5)
                    
                    // AI 面板弹出
                    if viewModel.showAIHelper {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                TerminalAIOverlay(
                                    isPresented: $viewModel.showAIHelper,
                                    prompt: $viewModel.aiPrompt,
                                    isGenerating: $viewModel.isAIGenerating,
                                    steps: $viewModel.aiSteps,
                                    onGenerate: viewModel.generateAICommand,
                                    onExecuteStep: viewModel.executeAIStep
                                )
                                .padding(.trailing, 20)
                                .padding(.bottom, 60) // Shift up to be above the button
                                .allowsHitTesting(true)
                            }
                        }
                        .allowsHitTesting(true)
                        .zIndex(20)
                    }

                    if viewModel.showFlowPanel {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                TerminalFlowOverlay(
                                    isPresented: $viewModel.showFlowPanel,
                                    groups: $viewModel.flowGroups,
                                    stopOnError: $viewModel.stopFlowOnError,
                                    onExecuteStep: viewModel.executeFlowStep,
                                    onExecuteGroup: viewModel.executeFlowGroup,
                                    onExecuteAll: viewModel.executeAllFlowGroups
                                )
                                .padding(.trailing, 20)
                                .padding(.bottom, 60)
                                .allowsHitTesting(true)
                            }
                        }
                        .allowsHitTesting(true)
                        .zIndex(20)
                    }
                    
                    // 连接状态横幅
                    if viewModel.runner.isConnecting || viewModel.showSuccessBanner {
                        HStack {
                            Spacer()
                            statusBanner
                            Spacer()
                        }
                        .padding(.top, 40)
                        .allowsHitTesting(false) // CRITICAL: Don't block terminal selection
                        .zIndex(30)
                    }
                }
                
                // 2. 分割线
                DraggableSplitter(
                    isDragging: $viewModel.isDragging,
                    offset: $viewModel.dragOffset,
                    onDragChanged: { translation in
                        viewModel.updateLayout(translation: translation, isEnded: false)
                    },
                    onDragEnded: { translation in
                        viewModel.updateLayout(translation: translation, isEnded: true)
                    }
                )
                .frame(height: splitterHeight)
                
                // 3. SFTP 区域
                Group {
                    if viewModel.runner.isConnected {
                        SyncedSFTPView(
                            runner: viewModel.runner,
                            connectionID: viewModel.connection.id,
                            path: $viewModel.runner.currentPath,
                            isExpanded: Binding(get: { viewModel.isSFTPViewExpanded }, set: { viewModel.toggleSFTP(expanded: $0) }),
                            onNavigate: { dir in
                                viewModel.runner.currentPath = dir
                            }
                        )
                    } else {
                        VStack {
                            if let error = viewModel.runner.error {
                                Text(error).foregroundColor(.red).padding()
                            } else {
                                ProgressView("Connecting...").padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: constrainedSftpHeight)
                .background(DesignSystem.Colors.surface)
            }
        }
        .onAppear { viewModel.connect() }
        .background(DesignSystem.Colors.background)
    }
    
    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.runner.isConnecting {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.5).controlSize(.small)
                Text("Connecting...".localized).font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        } else if viewModel.showSuccessBanner {
            Text("Success".localized).font(.caption).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.green.opacity(0.8)).cornerRadius(12)
        }
    }

    private var statusText: String {
        if viewModel.runner.isConnecting {
            return "Connecting"
        }
        return viewModel.runner.isConnected ? "Connected" : "Disconnected"
    }

    @ViewBuilder
    private var statusDot: some View {
        if viewModel.runner.isConnecting {
            ProgressView().scaleEffect(0.5).controlSize(.mini)
        } else {
            Circle()
                .fill(viewModel.runner.isConnected ? DesignSystem.Colors.green : DesignSystem.Colors.pink)
                .frame(width: 6, height: 6)
        }
    }

    private func copyLastOutput() {
        let text = viewModel.runner.getLastOutput()
        guard !text.isEmpty else {
            ToastManager.shared.show(message: "No output to copy", type: .warning)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ToastManager.shared.show(message: "Output copied", type: .success)
    }
}
