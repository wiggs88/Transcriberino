import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: PipelineCoordinator!
    private var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        logTranscriberino("App launched")

        // Check accessibility permission (prompts user if needed)
        if !TextInjectionService.checkAccessibilityPermission() {
            logTranscriberino("Accessibility permission not granted. Text injection may not work.")
        }

        // Setup pipeline
        coordinator = PipelineCoordinator()
        hotkeyManager = HotkeyManager(coordinator: coordinator)
        hotkeyManager.register()

        logTranscriberino("Ready. Press Option+D to start dictation.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }
}
