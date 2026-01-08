import SwiftUI
import Foundation
import AppKit

/// 统一的 Redis 值编辑弹窗
/// 支持 String、Hash、List、Set 类型的值编辑
/// 自动检测并格式化 JSON 内容
struct ValueEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    
    /// 编辑模式
    enum EditMode {
        case string(String)           // 编辑字符串值
        case hashField(field: String, value: String)  // 编辑 Hash 字段值
        case hashNewField            // 添加新 Hash 字段
        case listItem(index: Int, value: String)      // 编辑 List 项
        case listNewItem             // 添加新 List 项
        case setItem(value: String)  // 编辑 Set 成员
        case setNewItem              // 添加新 Set 成员
    }
    
    let mode: EditMode
    let onSave: (String) -> Void
    let onSaveWithField: ((String, String) -> Void)?  // 用于 Hash 新字段
    
    @State private var value: String
    @State private var fieldName: String = ""
    @State private var isJSONFormatted: Bool = false
    @State private var jsonFormatError: String?
    
    init(mode: EditMode, onSave: @escaping (String) -> Void, onSaveWithField: ((String, String) -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onSaveWithField = onSaveWithField
        
        // 初始化值
        switch mode {
        case .string(let val), .hashField(_, let val), .listItem(_, let val), .setItem(let val):
            _value = State(initialValue: val)
        case .hashNewField, .listNewItem, .setNewItem:
            _value = State(initialValue: "")
            _fieldName = State(initialValue: "")
        }
    }
    
    var title: String {
        switch mode {
        case .string:
            return "编辑值"
        case .hashField(let field, _):
            return "编辑字段: \(field)"
        case .hashNewField:
            return "添加新字段"
        case .listItem(let index, _):
            return "编辑索引 \(index + 1) 的项"
        case .listNewItem:
            return "添加新项"
        case .setItem:
            return "编辑成员"
        case .setNewItem:
            return "添加成员"
        }
    }
    
    var showFieldName: Bool {
        if case .hashNewField = mode {
            return true
        }
        return false
    }
    
    var body: some View {
        SheetScaffold(
            title: title,
            minSize: NSSize(width: 800, height: 600),
            onClose: { dismiss() }
        ) {
            // 内容区域
            VStack(spacing: DesignSystem.Spacing.large) {
                // 字段名输入（仅 Hash 新字段）
                if showFieldName {
                    FormSection(title: "Field Name", systemImage: "key") {
                        TextField("Enter field name", text: $fieldName)
                            .textFieldStyle(ModernTextFieldStyle())
                            .outlined()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.large)
                }
                
                // 值编辑区域
                FormSection(
                    title: showFieldName ? "Field Value" : "Value",
                    systemImage: "doc.plaintext",
                    headerTrailing: {
                        AnyView(
                            Button(action: formatJSON) {
                                Label("Format JSON", systemImage: "curlybraces")
                                    .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(ModernButtonStyle(variant: .ghost, size: .small))
                            .disabled(!isJSONFormatted)
                        )
                    }
                ) {
                    ZStack(alignment: .topLeading) {
                        PlainTextEditor(text: $value, font: .monospacedSystemFont(ofSize: 13, weight: .regular), inset: DesignSystem.Spacing.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill all available space
                            .background(DesignSystem.Colors.surfaceSecondary)
                            .cornerRadius(DesignSystem.Radius.small)
                            .outlined(color: jsonFormatError != nil ? DesignSystem.Colors.pink : DesignSystem.Colors.border.opacity(0.8))
                            .onChange(of: value) { oldValue, newValue in
                                checkJSONFormat(newValue)
                            }
                        
                        // JSON 格式错误提示
                        if let error = jsonFormatError {
                            VStack {
                                Spacer()
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(DesignSystem.Colors.pink)
                                    Text(error)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.pink)
                                    Spacer()
                                }
                                .padding(DesignSystem.Spacing.small)
                                .background(DesignSystem.Colors.background.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.large)
                .padding(.bottom, DesignSystem.Spacing.large)
            }
            .padding(.top, DesignSystem.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } footer: {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(ModernButtonStyle(variant: .secondary))
                
                Spacer()
                
                Button(saveButtonTitle) { saveValue() }
                    .buttonStyle(ModernButtonStyle(variant: .primary))
                    .disabled(!canSave)
            }
        }
        .onAppear {
            checkJSONFormat(value)
        }
    }
    
    private var saveButtonTitle: String {
        switch mode {
        case .hashNewField, .listNewItem, .setNewItem:
            return "添加"
        default:
            return "保存"
        }
    }
    
    private var canSave: Bool {
        if value.isEmpty {
            return false
        }
        if showFieldName && fieldName.isEmpty {
            return false
        }
        return true
    }
    
    /// 检测是否为 JSON 格式
    private func checkJSONFormat(_ text: String) {
        isJSONFormatted = JSONFormatting.isCandidate(text)
        guard isJSONFormatted else {
            jsonFormatError = nil
            return
        }

        if let error = JSONFormatting.validationError(text) {
            switch error {
            case .invalidUTF8:
                jsonFormatError = "无法解析内容"
            case .invalidJSON:
                jsonFormatError = "JSON 格式错误，请检查语法"
            case .formatFailed:
                jsonFormatError = "格式化失败"
            }
        } else {
            jsonFormatError = nil
        }
    }
    
    /// 格式化 JSON
    private func formatJSON() {
        switch JSONFormatting.prettyPrinted(value) {
        case .success(let pretty):
            value = pretty
            jsonFormatError = nil
        case .failure(let error):
            switch error {
            case .invalidUTF8:
                jsonFormatError = "无法解析内容"
            case .invalidJSON:
                jsonFormatError = "JSON 格式错误，请检查语法"
            case .formatFailed:
                jsonFormatError = "格式化失败"
            }
        }
    }
    
    /// 保存值
    private func saveValue() {
        switch mode {
        case .string, .hashField, .listItem, .setItem, .listNewItem, .setNewItem:
            onSave(value)
        case .hashNewField:
            if let onSaveWithField = onSaveWithField {
                onSaveWithField(fieldName, value)
            } else {
                onSave(value)
            }
        }
        dismiss()
    }
}
