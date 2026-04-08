import Foundation

@MainActor
final class PipelineCoordinator: ObservableObject {
    @Published var state: PipelineState = .idle
    @Published var audioLevel: Float = 0.0

    private let recordingController = RecordingController()
    private let transcriptionService = TranscriptionService()
    private let cleanupService = CleanupService()
    private let textInjectionService = TextInjectionService()
    private let indicatorWindow = IndicatorWindow()

    private var lastActionTime: Date = .distantPast
    private var recordingStartTime: Date?

    init() {
        indicatorWindow.setCoordinator(self)
        recordingController.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
    }

    func handleHotkeyPress() {
        let now = Date()
        guard now.timeIntervalSince(lastActionTime) >= Config.cooldownDuration else { return }

        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndProcess()
        case .processing, .injecting, .ready:
            break
        }
    }

    private func startRecording() {
        do {
            try recordingController.startRecording()
            recordingStartTime = Date()
            state = .recording
            indicatorWindow.show(state: .recording)
        } catch {
            logTranscriberino("Failed to start recording: \(error)")
            reset()
        }
    }

    private func stopRecordingAndProcess() {
        guard let startTime = recordingStartTime else {
            reset()
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        guard let audioURL = recordingController.stopRecording() else {
            reset()
            return
        }

        if duration < Config.minimumRecordingDuration {
            logTranscriberino("Recording too short (\(String(format: "%.1f", duration))s), discarding.")
            try? FileManager.default.removeItem(at: audioURL)
            reset()
            return
        }

        state = .processing
        indicatorWindow.show(state: .processing)

        Task {
            await runPipeline(audioURL: audioURL)
        }
    }

    private func runPipeline(audioURL: URL) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            reset()
        }

        do {
            var t0 = Date()
            let rawTranscript = try await transcriptionService.transcribe(audioURL: audioURL)
            logTranscriberino("Transcription took \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logTranscriberino("Empty transcript, skipping.")
                return
            }

            t0 = Date()
            let cleanedText = await cleanupService.clean(rawTranscript)
            logTranscriberino("Cleanup took \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")

            state = .injecting
            try textInjectionService.inject(text: cleanedText)

            state = .ready
            indicatorWindow.show(state: .ready)

            try await Task.sleep(nanoseconds: 1_000_000_000)
            lastActionTime = Date()
        } catch {
            logTranscriberino("Pipeline error: \(error)")
        }
    }

    private func reset() {
        state = .idle
        indicatorWindow.hide()
        recordingStartTime = nil
        audioLevel = 0.0
    }
}
