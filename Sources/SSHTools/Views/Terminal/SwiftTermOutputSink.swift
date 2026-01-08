import Foundation
import SwiftTerm

extension SwiftTerm.TerminalView: TerminalOutputSink {
    func writeToTerminal(_ data: Data) {
        self.feed(byteArray: ArraySlice([UInt8](data)))
    }
}

