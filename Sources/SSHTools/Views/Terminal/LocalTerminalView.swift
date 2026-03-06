import SwiftUI
import Combine

final class LocalTerminalViewModel: ObservableObject {
    let connection: SSHConnection
    @Published var runner: LocalTerminalRunner
    private var cancellables = Set<AnyCancellable>()
    private let pathStore = LocalTerminalPathStore.shared

    init(connection: SSHConnection) {
        self.connection = connection
        let runner = LocalTerminalRunner(connectionID: connection.id)
        self.runner = runner

        runner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        runner.$currentPath
            .sink { [weak self] path in
                guard let self else { return }
                self.pathStore.updatePath(path, for: self.connection.id)
            }
            .store(in: &cancellables)

        pathStore.updatePath(runner.currentPath, for: connection.id)
    }

    deinit {
        cancellables.removeAll()
        runner.disconnect()
    }

    func connect() {
        if !runner.isConnected {
            runner.connect()
        }
    }

    func disconnect() {
        runner.disconnect()
    }
}

struct LocalTerminalView: View {
    @StateObject private var viewModel: LocalTerminalViewModel
    private let tabID: UUID

    init(connection: SSHConnection, tabID: UUID) {
        _viewModel = StateObject(wrappedValue: LocalTerminalViewModel(connection: connection))
        self.tabID = tabID
    }

    var body: some View {
        ZStack {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            XTermWebView(runner: viewModel.runner, tabID: tabID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .clipped()

            ReconnectOverlay(
                isConnected: viewModel.runner.isConnected,
                isConnecting: viewModel.runner.isConnecting,
                error: viewModel.runner.error,
                onReconnect: { viewModel.connect() }
            )
        }
        .onAppear { viewModel.connect() }
        .background(DesignSystem.Colors.background)
    }
}
