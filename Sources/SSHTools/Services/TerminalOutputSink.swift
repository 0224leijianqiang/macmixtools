import Foundation

protocol TerminalOutputSink: AnyObject {
    func writeToTerminal(_ data: Data)
}

