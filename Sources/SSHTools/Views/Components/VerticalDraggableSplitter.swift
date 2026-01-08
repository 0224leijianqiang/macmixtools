import SwiftUI

struct VerticalDraggableSplitter: View {
    @Binding var isDragging: Bool
    
    var body: some View {
        ZStack {
            // Invisible divider line
            Rectangle()
                .fill(isDragging ? DesignSystem.Colors.blue : DesignSystem.Colors.border)
                .frame(width: 1)
            
            // Highlight when dragging
            if isDragging {
                Rectangle()
                    .fill(DesignSystem.Colors.blue)
                    .frame(width: 2)
            }
        }
        .frame(width: 8)
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .zIndex(100)
    }
}
