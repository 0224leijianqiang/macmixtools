import SwiftUI

extension View {
    func outlined(
        cornerRadius: CGFloat = DesignSystem.Radius.small,
        color: Color = DesignSystem.Colors.border.opacity(0.8),
        lineWidth: CGFloat = 1
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color, lineWidth: lineWidth)
        )
    }
}

