import SwiftUI

// MARK: - 设计系统常量
struct RedisDesignSystem {
    // 颜色
    static let primaryBlue = Color.blue
    static let primaryGreen = Color.green
    static let primaryRed = Color.red
    static let primaryOrange = Color.orange
    static let secondaryText = Color.secondary
    static let background = Color(nsColor: .controlBackgroundColor)
    static let textBackground = Color(nsColor: .textBackgroundColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    
    // 字体大小
    static let fontSizeLarge: CGFloat = 16
    static let fontSizeMedium: CGFloat = 13
    static let fontSizeSmall: CGFloat = 12
    static let fontSizeTiny: CGFloat = 11
    static let fontSizeMicro: CGFloat = 10
    
    // 间距
    static let spacingLarge: CGFloat = 16
    static let spacingMedium: CGFloat = 12
    static let spacingSmall: CGFloat = 8
    static let spacingTiny: CGFloat = 4
    
    // 圆角
    static let cornerRadiusLarge: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 6
    static let cornerRadiusSmall: CGFloat = 4
    
    // 按钮尺寸
    static let buttonHeight: CGFloat = 28
    static let iconButtonSize: CGFloat = 24
    static let headerHeight: CGFloat = 32
}

// MARK: - 公共样式组件
struct PrimaryButtonStyle: ViewModifier {
    let color: Color
    let height: CGFloat
    
    init(color: Color = RedisDesignSystem.primaryBlue, height: CGFloat = RedisDesignSystem.buttonHeight) {
        self.color = color
        self.height = height
    }
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: RedisDesignSystem.fontSizeSmall, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, RedisDesignSystem.spacingMedium)
            .padding(.vertical, RedisDesignSystem.spacingSmall)
            .frame(height: height)
            .background(color)
            .cornerRadius(RedisDesignSystem.cornerRadiusMedium)
    }
}

struct IconButtonStyle: ViewModifier {
    let color: Color
    let size: CGFloat
    
    init(color: Color = RedisDesignSystem.primaryBlue, size: CGFloat = RedisDesignSystem.iconButtonSize) {
        self.color = color
        self.size = size
    }
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: RedisDesignSystem.fontSizeMedium))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.1))
            .cornerRadius(RedisDesignSystem.cornerRadiusMedium)
    }
}

struct SearchFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: RedisDesignSystem.fontSizeMedium))
            .padding(.horizontal, RedisDesignSystem.spacingMedium)
            .padding(.vertical, 8) // Increased vertical padding
            .background(RedisDesignSystem.textBackground.opacity(0.5))
            .cornerRadius(RedisDesignSystem.cornerRadiusLarge)
            // No border
    }
}

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: RedisDesignSystem.fontSizeTiny, weight: .semibold))
            .foregroundColor(RedisDesignSystem.secondaryText)
            .padding(.horizontal, RedisDesignSystem.spacingLarge)
            .padding(.vertical, RedisDesignSystem.spacingMedium)
            .background(RedisDesignSystem.background)
    }
}

struct TableHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: RedisDesignSystem.fontSizeTiny, weight: .semibold))
            .foregroundColor(RedisDesignSystem.secondaryText)
            .frame(height: RedisDesignSystem.headerHeight)
            .background(RedisDesignSystem.background)
    }
}

extension View {
    func primaryButton(color: Color = RedisDesignSystem.primaryBlue, height: CGFloat = RedisDesignSystem.buttonHeight) -> some View {
        modifier(PrimaryButtonStyle(color: color, height: height))
    }
    
    func iconButton(color: Color = RedisDesignSystem.primaryBlue, size: CGFloat = RedisDesignSystem.iconButtonSize) -> some View {
        modifier(IconButtonStyle(color: color, size: size))
    }
    
    func searchField() -> some View {
        modifier(SearchFieldStyle())
    }
    
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }
    
    func tableHeader() -> some View {
        modifier(TableHeaderStyle())
    }
}

