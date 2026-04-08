import HotKey
import Carbon

@MainActor
final class HotkeyManager {
    private var hotKey: HotKey?
    private weak var coordinator: PipelineCoordinator?

    init(coordinator: PipelineCoordinator) {
        self.coordinator = coordinator
    }

    func register() {
        hotKey = HotKey(key: .d, modifiers: .option)
        hotKey?.keyDownHandler = { [weak self] in
            self?.coordinator?.handleHotkeyPress()
        }
    }

    func unregister() {
        hotKey = nil
    }
}
