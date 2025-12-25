import SwiftUI
import AppKit

struct SQLCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var tables: [String]
    var onExecute: () -> Void
    
    // Standard MySQL Keywords for completion
    let keywords = [
        "SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "LIMIT", "INSERT INTO",
        "UPDATE", "DELETE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
        "ON", "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX", "DESC", "ASC",
        "AND", "OR", "IN", "IS NULL", "IS NOT NULL", "LIKE", "BETWEEN", "VALUES", "SET"
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay // Ensure scroller doesn't take up space
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.drawsBackground = true
        
        // Setup appearance
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        
        // Add some small internal padding for readability
        textView.textContainerInset = NSSize(width: 5, height: 5)
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLCodeEditor
        
        // Caching regex for performance
        private let keywordRegex: NSRegularExpression?
        private let functionRegex = try? NSRegularExpression(pattern: "\\b(COUNT|SUM|AVG|MIN|MAX|NOW|DATE_FORMAT|CONCAT|COALESCE|IFNULL|REPLACE)\\b", options: [.caseInsensitive])
        private let stringRegex = try? NSRegularExpression(pattern: "'[^']*'|\"[^\"]*\"", options: [])
        private let numberRegex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b", options: [])
        private let commentRegex = try? NSRegularExpression(pattern: "--.*|/\\*.*?\\*/", options: [.dotMatchesLineSeparators])

        init(_ parent: SQLCodeEditor) {
            self.parent = parent
            let pattern = "\\b(" + parent.keywords.joined(separator: "|") + ")\\b"
            self.keywordRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            applyHighlighting(textView)
            
            // Cancel previous completion request
            NSObject.cancelPreviousPerformRequests(withTarget: textView, selector: #selector(textView.complete(_:)), object: nil)
            
            // Check if we should show completions
            let selectedRange = textView.selectedRange()
            if selectedRange.length == 0 && selectedRange.location > 0 {
                let content = textView.string as NSString
                let lastCharRange = NSRange(location: selectedRange.location - 1, length: 1)
                let lastChar = content.substring(with: lastCharRange)
                
                // Only trigger after letters/numbers and a short delay to prevent UI flickers
                if CharacterSet.alphanumerics.contains(lastChar.unicodeScalars.first!) {
                    textView.perform(#selector(textView.complete(_:)), with: nil, afterDelay: 0.1)
                }
            }
        }
        
        func applyHighlighting(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let content = textView.string
            let range = NSRange(location: 0, length: textStorage.length)
            
            // Batch updates for performance
            textStorage.beginEditing()
            
            // 0. Reset to default style
            textStorage.setAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ], range: range)
            
            // 1. Keywords (Purple Bold)
            keywordRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r)
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: r)
                }
            }
            
            // 2. Functions (Pink)
            functionRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: r)
                }
            }
            
            // 3. Numbers (Blue)
            numberRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: r)
                }
            }
            
            // 4. Strings (Orange - Overrides keywords/numbers)
            stringRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: r)
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: r)
                }
            }
            
            // 5. Comments (Green - Overrides everything else)
            commentRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let r = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: r)
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: r)
                }
            }
            
            textStorage.endEditing()
        }
        
        // Handle Tab key or specific shortcuts
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.complete(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Command + Enter to execute
                if let event = NSApp.currentEvent, event.modifierFlags.contains(.command) {
                    parent.onExecute()
                    return true
                }
            }
            return false
        }
        
        // Provide completions
        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partialString = (textView.string as NSString).substring(with: charRange).uppercased()
            
            // Combine keywords and table names
            let allSuggestions = parent.keywords + parent.tables
            
            return allSuggestions.filter { 
                $0.uppercased().hasPrefix(partialString)
            }.sorted()
        }
    }
}
