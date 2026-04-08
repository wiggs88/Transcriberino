import AppKit
import Carbon
import Foundation

enum Config {
    // MARK: - Hotkey
    static let hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_D)
    static let hotkeyModifiers: NSEvent.ModifierFlags = .option

    // MARK: - Transcription
    static let parakeetBinaryPath = "/Users/gianfrancodbeis/.local/bin/parakeet-mlx"
    static let transcriptionTimeoutSeconds: TimeInterval = 30

    // MARK: - Recording
    static let sampleRate: Double = 16000
    static let minimumRecordingDuration: TimeInterval = 0.5

    // MARK: - Cleanup
    static let cleanupMode: CleanupMode = .fast
    static let ollamaURL = URL(string: "http://localhost:11434/api/generate")!
    static let ollamaModel = "qwen:14b"
    static let ollamaTimeoutSeconds: TimeInterval = 30

    // MARK: - Text Injection
    static let pasteDelay: TimeInterval = 0.2
    static let clipboardRestoreDelay: TimeInterval = 0.2

    // MARK: - Indicator
    static let indicatorTopOffset: CGFloat = 40
    static let indicatorCornerRadius: CGFloat = 12
    static let indicatorAnimationDuration: TimeInterval = 0.15

    // MARK: - Debounce
    static let cooldownDuration: TimeInterval = 0.5

    enum CleanupMode {
        case fast
        case llm
    }
}
