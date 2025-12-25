import SwiftUI

struct DataRow: View {
    let rowIndex: Int
    let rowData: [String]
    @ObservedObject var viewModel: MySQLViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            // Sequence Cell
            Text("\(rowIndex + 1 + (viewModel.page - 1) * viewModel.limit)")
                .font(DesignSystem.fontBody)
                .padding(8)
                .frame(width: 50, alignment: .center)
                .background(rowIndex % 2 == 0 ? Color.clear : DesignSystem.surfaceColor.opacity(0.3))
                .overlay(
                    Rectangle().stroke(DesignSystem.borderColor.opacity(0.3), lineWidth: 0.5)
                )
            
            ForEach(0..<rowData.count, id: \.self) { colIdx in
                Text(rowData[colIdx])
                    .font(DesignSystem.fontBody)
                    .lineLimit(1)
                    .padding(8)
                    .frame(width: viewModel.columnWidths.indices.contains(colIdx) ? viewModel.columnWidths[colIdx] : 150, alignment: .leading)
                    .background(rowIndex % 2 == 0 ? Color.clear : DesignSystem.surfaceColor.opacity(0.5))
                    .overlay(
                        Rectangle().stroke(DesignSystem.borderColor.opacity(0.5), lineWidth: 0.5)
                    )
                    .textSelection(.enabled)
            }
        }
    }
}

struct HeaderCell: View {
    let title: String
    let width: CGFloat
    let onResize: (CGFloat) -> Void // Pass the absolute new width
    
    @State private var isHoveringHandle = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Content
            HStack(spacing: 0) {
                Text(title)
                    .font(DesignSystem.fontCaption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                
                // Resize Handle Hit Area
                Color.clear
                    .frame(width: 8) // Wider hit area for easier grabbing
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringHandle = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                isDragging = false
                                let newWidth = max(50, width + value.translation.width)
                                onResize(newWidth)
                                dragOffset = 0
                            }
                    )
            }
            .frame(width: width, height: DesignSystem.Layout.headerHeight)
            .background(.ultraThinMaterial) // High-quality transparency
            .overlay(
                Rectangle().stroke(DesignSystem.borderColor.opacity(0.3), lineWidth: 0.5)
            )
            
            // Ghost Guideline
            if isDragging {
                GhostGuideline(orientation: .vertical, color: DesignSystem.Colors.blue)
                    .frame(maxHeight: .infinity) // Try to fill height
                    .offset(x: dragOffset)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(isDragging ? 100 : 0) // Ensure ghost line appears above other headers
    }
}
