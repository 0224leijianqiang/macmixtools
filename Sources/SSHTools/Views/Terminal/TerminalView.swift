import SwiftUI

struct TerminalView: View {
    @StateObject private var viewModel: TerminalViewModel
    @Namespace private var bottomID
    
    init(connection: SSHConnection) {
        _viewModel = StateObject(wrappedValue: TerminalViewModel(connection: connection))
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let splitterHeight: CGFloat = 8
            
            // 计算高度
            let maxSftpHeight = totalHeight - DesignSystem.Layout.terminalMinHeight - splitterHeight
            let constrainedSftpHeight = min(max(viewModel.sftpHeight, DesignSystem.Layout.sftpMinHeight), max(maxSftpHeight, DesignSystem.Layout.sftpMinHeight))
            let terminalHeight = max(0, totalHeight - constrainedSftpHeight - splitterHeight)
            
            VStack(spacing: 0) {
                // 1. 终端区域
                ZStack(alignment: .topTrailing) {
                    SwiftTermView(runner: viewModel.runner)
                        .frame(height: terminalHeight)
                        .background(Color.black)
                        .clipped()
                        .allowsHitTesting(true)
                    
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
                    }
                    .padding(10)
                    .zIndex(10)
                    
                    // AI 助手按钮 - 右下角
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
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
                            path: $viewModel.runner.currentPath,
                            isExpanded: Binding(get: { viewModel.isSFTPViewExpanded }, set: { viewModel.toggleSFTP(expanded: $0) }),
                            onNavigate: { dir in
                                viewModel.runner.sendRaw("cd \"\(dir)\"\r")
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
        .onDisappear { viewModel.disconnect() }
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
}
