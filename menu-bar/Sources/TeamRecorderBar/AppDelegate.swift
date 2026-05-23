import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement in Info.plist handles this,
        // but setting it here ensures it works even if the plist is absent during dev.
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            // First run — show the permission setup guide.
            // Do NOT start the watcher yet; SetupWindowController starts it on completion.
            SetupWindowController.shared.show()
        } else {
            // Setup already done: auto-start the watcher as normal.
            // No-op if watcher is already running (e.g. started via `make run`).
            WatcherManager.shared.autoStartIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only stop a watcher this app started — never kills an externally-launched watcher
        WatcherManager.shared.stopManagedOnly()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app — no windows, never auto-quit on window close
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Called when 'open App.app' runs and the app is already running —
        // i.e. the user double-clicked Start Recorder.command or the .app again.
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            // Setup incomplete — show guide; do NOT auto-start (setup does it on finish)
            SetupWindowController.shared.show()
        } else {
            WatcherManager.shared.autoStartIfNeeded()
            // Brief icon flash confirms to the user that the app is already running
            statusBarController?.flashIcon()
        }
        statusBarController?.refresh()
        return true
    }
}
