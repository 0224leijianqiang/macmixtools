import SwiftUI

struct FormSection<Content: View>: View {
    let title: String
    let systemImage: String?
    let subtitle: String?
    let headerTrailing: (() -> AnyView)?
    let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        subtitle: String? = nil,
        headerTrailing: (() -> AnyView)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.blue)
                } else {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.blue)
                }

                Spacer()

                if let headerTrailing {
                    headerTrailing()
                }
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            content
        }
        .padding()
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.medium)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
