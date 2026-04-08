import AVFoundation
import Foundation

final class RecordingController {
    private var audioEngine: AVAudioEngine?
    private var outputFileURL: URL?
    private var pcmBuffers: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Config.sampleRate,
        channels: 1,
        interleaved: true
    )!

    var onAudioLevel: ((Float) -> Void)?

    func startRecording() throws {
        guard checkMicrophonePermission() else {
            throw RecordingError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard hardwareFormat.sampleRate > 0 else {
            throw RecordingError.noAudioInput
        }

        pcmBuffers = []

        let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate audio level for reactive UI
            let level = self.calculateAudioLevel(from: buffer)
            self.onAudioLevel?(level)

            if let converter {
                let ratio = self.targetFormat.sampleRate / hardwareFormat.sampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: self.targetFormat,
                    frameCapacity: outputFrameCapacity
                ) else { return }

                var error: NSError?
                var allConsumed = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if allConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil && convertedBuffer.frameLength > 0 {
                    self.bufferLock.lock()
                    self.pcmBuffers.append(convertedBuffer)
                    self.bufferLock.unlock()
                }
            } else {
                self.bufferLock.lock()
                self.pcmBuffers.append(buffer)
                self.bufferLock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        bufferLock.lock()
        let capturedBuffers = pcmBuffers
        pcmBuffers = []
        bufferLock.unlock()

        guard !capturedBuffers.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriberino_\(UUID().uuidString).wav")

        do {
            try writeWAV(buffers: capturedBuffers, to: url)
            return url
        } catch {
            logTranscriberino("Failed to write WAV: \(error)")
            return nil
        }
    }

    private func writeWAV(buffers: [AVAudioPCMBuffer], to url: URL) throws {
        var allData = Data()
        for buffer in buffers {
            guard let int16Data = buffer.int16ChannelData else { continue }
            let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
            allData.append(Data(bytes: int16Data[0], count: byteCount))
        }

        guard !allData.isEmpty else {
            throw RecordingError.noAudioData
        }

        var fileData = Data()

        let sampleRate: UInt32 = UInt32(Config.sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize = UInt32(allData.count)
        let chunkSize = 36 + dataSize

        // RIFF header
        fileData.append(contentsOf: "RIFF".utf8)
        fileData.append(littleEndian: chunkSize)
        fileData.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        fileData.append(contentsOf: "fmt ".utf8)
        fileData.append(littleEndian: UInt32(16)) // sub-chunk size
        fileData.append(littleEndian: UInt16(1))  // PCM format
        fileData.append(littleEndian: channels)
        fileData.append(littleEndian: sampleRate)
        fileData.append(littleEndian: byteRate)
        fileData.append(littleEndian: blockAlign)
        fileData.append(littleEndian: bitsPerSample)

        // data sub-chunk
        fileData.append(contentsOf: "data".utf8)
        fileData.append(littleEndian: dataSize)
        fileData.append(allData)

        try fileData.write(to: url)
    }

    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        var sum: Float = 0

        // Handle different audio formats
        if let floatData = buffer.floatChannelData?[0] {
            for i in 0..<frameLength {
                let sample = floatData[i]
                sum += sample * sample
            }
        } else if let int16Data = buffer.int16ChannelData?[0] {
            for i in 0..<frameLength {
                let sample = Float(int16Data[i]) / 32768.0  // Normalize int16 to -1.0...1.0
                sum += sample * sample
            }
        } else if let int32Data = buffer.int32ChannelData?[0] {
            for i in 0..<frameLength {
                let sample = Float(int32Data[i]) / 2147483648.0  // Normalize int32 to -1.0...1.0
                sum += sample * sample
            }
        } else {
            return 0.0
        }

        let rms = sqrt(sum / Float(frameLength))
        // Normalize to 0-1 range (typical speech is around 0.1-0.3 RMS)
        return min(rms * 10.0, 1.0)
    }

    private func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default:
            return false
        }
    }

    enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case noAudioInput
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
            case .noAudioInput:
                return "No audio input device found."
            case .noAudioData:
                return "No audio data was captured."
            }
        }
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: MemoryLayout<UInt16>.size))
    }

    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: MemoryLayout<UInt32>.size))
    }
}
