import Foundation

final class TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String {
        let binaryPath = Config.parakeetBinaryPath

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw TranscriptionError.binaryNotFound(binaryPath)
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            audioURL.path,
            "--output-format", "txt",
            "--output-dir", outputDir.path,
        ]

        // Pass explicit HF_HOME and Homebrew bin so ffmpeg is found
        var env = ProcessInfo.processInfo.environment
        env["HF_HOME"] = "\(NSHomeDirectory())/.cache/huggingface"
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        process.environment = env

        let stderr = Pipe()
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()

            let timeoutItem = DispatchWorkItem {
                guard process.isRunning else { return }
                process.terminate()
                if resumed.setIfFalse() {
                    continuation.resume(throwing: TranscriptionError.timeout)
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + Config.transcriptionTimeoutSeconds,
                execute: timeoutItem
            )

            process.terminationHandler = { _ in
                timeoutItem.cancel()
                guard resumed.setIfFalse() else { return }

                let exitCode = process.terminationStatus
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let outStr = String(data: outData, encoding: .utf8) ?? ""

                logTranscriberino("parakeet exit=\(exitCode)")
                if !errStr.isEmpty { logTranscriberino("parakeet stderr: \(errStr)") }
                if !outStr.isEmpty { logTranscriberino("parakeet stdout: \(outStr)") }

                let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
                logTranscriberino("outputDir contents: \(dirContents)")

                if exitCode != 0 && errStr.lowercased().contains("error") {
                    continuation.resume(throwing: TranscriptionError.processFailed(errStr))
                    return
                }

                // Read the output .txt file parakeet writes
                do {
                    let files = dirContents
                        .filter { $0.hasSuffix(".txt") }
                        .map { outputDir.appendingPathComponent($0) }

                    if let txtFile = files.first {
                        let text = try String(contentsOf: txtFile, encoding: .utf8)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text)
                    } else {
                        continuation.resume(throwing: TranscriptionError.noOutput)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                if resumed.setIfFalse() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private final class LockedFlag: @unchecked Sendable {
        private var _value = false
        private let lock = NSLock()

        func setIfFalse() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _value { return false }
            _value = true
            return true
        }
    }

    enum TranscriptionError: LocalizedError {
        case binaryNotFound(String)
        case timeout
        case processFailed(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .binaryNotFound(let path):
                return "parakeet-mlx not found at \(path). Install with: uv tool install parakeet-mlx"
            case .timeout:
                return "Transcription timed out after \(Int(Config.transcriptionTimeoutSeconds))s."
            case .processFailed(let msg):
                return "Transcription failed: \(msg)"
            case .noOutput:
                return "Transcription produced no output."
            }
        }
    }
}
