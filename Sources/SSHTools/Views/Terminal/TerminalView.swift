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
            
            // 默认 1:1：未手动调整过时，终端与底部文件管理各占一半
            let defaultSftpHeight = (totalHeight - splitterHeight) / 2
            let effectiveSftpHeight = (viewModel.sftpHeight == DesignSystem.Layout.sftpDefaultHeight)
                ? defaultSftpHeight
                : viewModel.sftpHeight
            
            let maxSftpHeight = totalHeight - DesignSystem.Layout.terminalMinHeight - splitterHeight
            let sftpMin = DesignSystem.Layout.sftpMinHeight
            let sftpMax = max(maxSftpHeight, sftpMin)
            let constrainedSftpHeight = min(max(effectiveSftpHeight, sftpMin), sftpMax)
            let terminalPadding: CGFloat = 12
            let ipBarHeight: CGFloat = 32
            let terminalHeight = max(0, totalHeight - constrainedSftpHeight - splitterHeight)
            
            VStack(spacing: 0) {
                // 1. 终端区域（IP 栏半透明叠加在顶部）
                ZStack(alignment: .topTrailing) {
                    Color.black
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(0)
                    
                    XTermWebView(runner: viewModel.runner, tabID: tabID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, ipBarHeight + terminalPadding)
                        .padding(.horizontal, terminalPadding)
                        .padding(.bottom, terminalPadding)
                        .clipped()
                        .allowsHitTesting(true)
                        .zIndex(1)
                    
                    // Reconnect overlay when connection drops
                    ReconnectOverlay(
                        isConnected: viewModel.runner.isConnected,
                        isConnecting: viewModel.runner.isConnecting,
                        error: viewModel.runner.error,
                        onReconnect: { viewModel.connect() }
                    )
                    .frame(height: terminalHeight)
                    .zIndex(25)
                    
                    // Quick Actions - 右下角（Flow 已移至底部面板 tab）
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Button(action: { 
                                    withAnimation(.spring()) {
                                        viewModel.showAIHelper.toggle()
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
                .frame(height: terminalHeight)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text("IP")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text(viewModel.connection.host.isEmpty ? "—" : viewModel.connection.host)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Button(action: copyHostToClipboard) {
                                Text("复制".localized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring()) {
                                    viewModel.toggleMonitor()
                                }
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 14))
                                    .foregroundColor(viewModel.monitorService.isVisible ? .blue : .white.opacity(0.6))
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(height: ipBarHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.15))
                        
                        if viewModel.monitorService.isVisible {
                            HStack {
                                Spacer(minLength: 0)
                                SystemMonitorView(service: viewModel.monitorService)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .allowsHitTesting(true)
                }
                .clipped()
                
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
                
                // 3. 底部面板（文件夹 + Flow 任务 tab 切换）
                TerminalBottomPanel(
                    viewModel: viewModel,
                    height: constrainedSftpHeight
                )
            }
        }
        .onAppear { viewModel.connect() }
        .background(DesignSystem.Colors.background)
    }
    
    private func copyHostToClipboard() {
        let host = viewModel.connection.host
        guard !host.isEmpty else {
            ToastManager.shared.show(message: "No host to copy".localized, type: .warning)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(host, forType: .string)
        ToastManager.shared.show(message: "Copied".localized, type: .success)
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
}

// MARK: - 底部面板（文件夹 / Flow tab）
private struct TerminalBottomPanel: View {
    @ObservedObject var viewModel: TerminalViewModel
    let height: CGFloat

    private var sftpViewModel: SyncedSFTPViewModel {
        let path = viewModel.runner.currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialPath = path.isEmpty ? "/" : path
        return SyncedSFTPViewModelStore.shared.viewModel(
            runner: viewModel.runner,
            initialPath: initialPath,
            onNavigate: { viewModel.runner.currentPath = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 路径栏（最小化时仅显示此项）
            if viewModel.runner.isConnected {
                SFTPPathBar(
                    viewModel: sftpViewModel,
                    isExpanded: Binding(get: { viewModel.isSFTPViewExpanded }, set: { viewModel.toggleSFTP(expanded: $0) }),
                    connectionID: viewModel.connection.id,
                    runner: viewModel.runner,
                    onNavigate: { viewModel.runner.currentPath = $0 }
                )
            }
            if viewModel.isSFTPViewExpanded {
                tabBar
                Divider()
                tabContent
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .background(DesignSystem.Colors.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TerminalViewModel.BottomPanelTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.bottomPanelTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .folder ? "folder.fill" : "list.bullet.rectangle")
                            .font(.system(size: 12))
                        Text(tab == .folder ? "文件夹".localized : "Flow")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(viewModel.bottomPanelTab == tab ? DesignSystem.Colors.blue : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.bottomPanelTab == tab ? DesignSystem.Colors.itemSelected : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(DesignSystem.Colors.surface)
    }

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.bottomPanelTab == .folder {
            folderContent
        } else {
            flowContent
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        if viewModel.runner.isConnected {
            SyncedSFTPView(
                runner: viewModel.runner,
                connectionID: viewModel.connection.id,
                path: $viewModel.runner.currentPath,
                isExpanded: Binding(get: { viewModel.isSFTPViewExpanded }, set: { viewModel.toggleSFTP(expanded: $0) }),
                onNavigate: { viewModel.runner.currentPath = $0 },
                hidePathBar: true
            )
        } else {
            VStack {
                if let error = viewModel.runner.error {
                    Text(error).foregroundColor(.red).padding()
                } else {
                    ProgressView("Connecting...".localized).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var flowContent: some View {
        TerminalFlowOverlay(
            isPresented: .constant(true),
            groups: $viewModel.flowGroups,
            stopOnError: $viewModel.stopFlowOnError,
            onExecuteStep: viewModel.executeFlowStep,
            onExecuteGroup: viewModel.executeFlowGroup,
            onExecuteAll: viewModel.executeAllFlowGroups,
            embedded: true
        )
    }
}
