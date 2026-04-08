import Foundation

final class Logger {
    static let shared = Logger()

    private let logFile: URL
    private let queue = DispatchQueue(label: "com.transcriberino.logging")

    init() {
        let logsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriberino")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFile = logsDir.appendingPathComponent("transcriberino.log")
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"

        // Print to console
        print(fullMessage, terminator: "")

        // Write to file
        queue.async {
            if let data = fullMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let fileHandle = FileHandle(forWritingAtPath: self.logFile.path) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
            }
        }
    }
}

func logTranscriberino(_ message: String) {
    Logger.shared.log("[Transcriberino] \(message)")
}
