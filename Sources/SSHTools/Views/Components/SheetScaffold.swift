import SwiftUI
import AppKit

struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let minSize: NSSize
    let onClose: () -> Void
    let headerTrailing: (() -> AnyView)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        title: String,
        subtitle: String? = nil,
        minSize: NSSize = NSSize(width: 760, height: 600),
        onClose: @escaping () -> Void,
        headerTrailing: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minSize = minSize
        self.onClose = onClose
        self.headerTrailing = headerTrailing
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer()
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.surface)
        }
        .frame(minWidth: minSize.width, minHeight: minSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    DesignSystem.Colors.background,
                    DesignSystem.Colors.surface.opacity(0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(
            WindowConfigurator { window in
                window.styleMask.insert(.resizable)
                window.minSize = minSize
            }
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.fontTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            Spacer()
            if let headerTrailing {
                headerTrailing()
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        DesignSystem.Colors.surface.opacity(0.9),
                        DesignSystem.Colors.surfaceSecondary.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
            }
        )
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.6))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
