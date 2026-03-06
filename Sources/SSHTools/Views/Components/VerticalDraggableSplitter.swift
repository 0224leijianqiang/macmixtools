import SwiftUI
import AppKit

struct VerticalDraggableSplitter: View {
    @Binding var isDragging: Bool
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?
    
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border.opacity(0.8))
            .frame(width: 1)
        .frame(width: DesignSystem.Layout.sidebarSplitterWidth)
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .zIndex(100)
        .overlay {
            if let onStart = onDragStart, let onChanged = onDragChanged, let onEnd = onDragEnded {
                SplitterDragBlocker(
                    isDragging: $isDragging,
                    onDragStart: onStart,
                    onDragChanged: onChanged,
                    onDragEnded: onEnd
                )
            }
        }
    }
}

// MARK: - 阻止窗口拖动的分隔条拖拽层
// 当 isMovableByWindowBackground = true 时，窗口会优先响应拖动。此 NSView 通过
// mouseDownCanMoveWindow = false 阻止窗口移动，使分隔条能正确响应调整大小。
private struct SplitterDragBlocker: NSViewRepresentable {
    @Binding var isDragging: Bool
    var onDragStart: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> SplitterDragBlockerView {
        let view = SplitterDragBlockerView()
        view.coordinator = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: SplitterDragBlockerView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.onDragStart = onDragStart
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.isDraggingBinding = $isDragging
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var onDragStart: (() -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: ((CGFloat) -> Void)?
        var isDraggingBinding: Binding<Bool>?
    }
}

private final class SplitterDragBlockerView: NSView {
    weak var coordinator: SplitterDragBlocker.Coordinator?
    
    /// 关键：阻止窗口拖动，使分隔条能正确响应调整大小
    override var mouseDownCanMoveWindow: Bool { false }
    
    private var dragStartX: CGFloat = 0
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        coordinator?.onDragStart?()
        coordinator?.isDraggingBinding?.wrappedValue = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - dragStartX
        coordinator?.onDragChanged?(delta)
    }
    
    override func mouseUp(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - dragStartX
        coordinator?.onDragEnded?(delta)
        coordinator?.isDraggingBinding?.wrappedValue = false
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}
