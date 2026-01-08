import SwiftUI
import AppKit

struct SQLTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var tables: [String] = []
    var columns: [String] = []
    var onSubmit: () -> Void
    
    let keywords = [
        "AND", "OR", "IN", "IS NULL", "IS NOT NULL", "LIKE", "BETWEEN", 
        "DESC", "ASC", "NOT", "EXISTS", "IN", "REGEXP"
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.bezelStyle = .roundedBezel
        
        // Disable features that interfere with SQL typing
        textField.isAutomaticTextCompletionEnabled = false
        
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SQLTextField
        
        init(_ parent: SQLTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
                
                // Check if this was a deletion
                if let event = NSApp.currentEvent, event.type == .keyDown {
                    if event.keyCode == 51 { // Backspace
                        return
                    }
                }

                // Show completion
                if let editor = textField.currentEditor() as? NSTextView {
                    NSObject.cancelPreviousPerformRequests(withTarget: editor, selector: #selector(NSTextView.complete(_:)), object: nil)
                    
                    let range = editor.selectedRange()
                    if range.length == 0 && range.location > 0 {
                        let content = editor.string as NSString
                        let lastChar = content.substring(with: NSRange(location: range.location - 1, length: 1))
                        
                        if CharacterSet.alphanumerics.contains(lastChar.unicodeScalars.first!) {
                            editor.perform(#selector(NSTextView.complete(_:)), with: nil, afterDelay: 0.1)
                        }
                    }
                }
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            let partialString = (textView.string as NSString).substring(with: charRange).uppercased()
            let allSuggestions = parent.keywords + parent.tables + parent.columns
            
            return allSuggestions.filter { 
                $0.uppercased().hasPrefix(partialString)
            }.sorted()
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.complete(nil)
                return true
            }
            return false
        }
    }
}
