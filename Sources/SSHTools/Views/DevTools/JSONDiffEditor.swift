import SwiftUI
import CryptoKit
import AppKit

// ... ToolboxTool enum and DevToolboxView stay same ...

struct JSONDiffTool: View {
    @State private var leftText = ""
    @State private var rightText = ""
    
    @State private var leftAttributedText: NSAttributedString = NSAttributedString(string: "")
    @State private var rightAttributedText: NSAttributedString = NSAttributedString(string: "")
    
    var body: some View {
        VStack(spacing: 12) {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Source (Old)").font(.caption.bold()).foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(height: 24) // Fixed height for header alignment
                    
                    JSONHighlightEditor(text: $leftText, attributedText: leftAttributedText)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target (New)").font(.caption.bold()).foregroundColor(.secondary)
                        Spacer()
                        Button(action: performInlineDiff) {
                            Label("Compare", systemImage: "arrow.left.and.right.circle.fill")
                        }
                        .buttonStyle(ModernButtonStyle(variant: .primary, size: .small))
                    }
                    .frame(height: 24) // Identical height
                    
                    JSONHighlightEditor(text: $rightText, attributedText: rightAttributedText)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill entire workspace
            
            HStack {
                Label("Red = Removed", systemImage: "minus.circle.fill").foregroundColor(.red)
                Divider().frame(height: 12)
                Label("Green = Added", systemImage: "plus.circle.fill").foregroundColor(.green)
                Spacer()
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
        .padding()
    }
    
    private func loadExample() {
        leftText = "{\n  \"name\": \"SSHTools\",\n  \"version\": \"1.0.0\",\n  \"features\": [\"SSH\", \"Redis\"]\n}"
        rightText = "{\n  \"name\": \"SSHTools Pro\",\n  \"version\": \"1.1.0\",\n  \"features\": [\"SSH\", \"Redis\", \"Docker\"]\n}"
    }
    
    private func performInlineDiff() {
        // 1. Pre-format both to ensure structure matches
        let formattedLeft = prettyPrint(leftText)
        let formattedRight = prettyPrint(rightText)
        
        leftText = formattedLeft
        rightText = formattedRight
        
        let leftLines = formattedLeft.components(separatedBy: .newlines)
        let rightLines = formattedRight.components(separatedBy: .newlines)
        
        // 2. Simple Line-by-Line Diff logic
        let leftAttr = NSMutableAttributedString(string: formattedLeft, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])
        
        let rightAttr = NSMutableAttributedString(string: formattedRight, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])
        
        // Highlight logic
        let maxLines = max(leftLines.count, rightLines.count)
        
        for i in 0..<maxLines {
            let leftLine = i < leftLines.count ? leftLines[i] : nil
            let rightLine = i < rightLines.count ? rightLines[i] : nil
            
            if leftLine != rightLine {
                if let left = leftLine {
                    let range = (formattedLeft as NSString).range(of: left)
                    if range.location != NSNotFound {
                        leftAttr.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.2), range: range)
                        leftAttr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                    }
                }
                
                if let right = rightLine {
                    let range = (formattedRight as NSString).range(of: right)
                    if range.location != NSNotFound {
                        rightAttr.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.2), range: range)
                        rightAttr.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
                    }
                }
            }
        }
        
        self.leftAttributedText = leftAttr
        self.rightAttributedText = rightAttr
        ToastManager.shared.show(message: "Comparison Complete", type: .success)
    }
    
    private func prettyPrint(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return json
        }
        return String(data: prettyData, encoding: .utf8) ?? json
    }
}

/// Specialized NSTextView wrapper that handles attributed strings for highlighting
struct JSONHighlightEditor: NSViewRepresentable {
    @Binding var text: String
    var attributedText: NSAttributedString
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        // If we have highlighted text, use it. Otherwise use raw text.
        if attributedText.length > 0 && attributedText.string == text {
            if textView.attributedString() != attributedText {
                textView.textStorage?.setAttributedString(attributedText)
            }
        } else if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONHighlightEditor
        init(_ parent: JSONHighlightEditor) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
