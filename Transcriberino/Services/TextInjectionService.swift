import AppKit

final class TextInjectionService {
    func inject(text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logTranscriberino("Text copied to clipboard. Cmd+V to paste.")
    }

    static func checkAccessibilityPermission() -> Bool {
        let granted = AXIsProcessTrusted()
        logTranscriberino("Accessibility permission check: \(granted ? "GRANTED" : "DENIED")")
        return granted
    }
}
