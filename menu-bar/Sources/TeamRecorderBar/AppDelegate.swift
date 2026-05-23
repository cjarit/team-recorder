import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement in Info.plist handles this,
        // but setting it here ensures it works even if the plist is absent during dev.
        NSApp.setActivationPolicy(.accessory)
        configureNotifications()

        statusBarController = StatusBarController()

        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            // First run — show the permission setup guide.
            // Do NOT start the watcher yet; SetupWindowController starts it on completion.
            SetupWindowController.shared.show()
        } else {
            // Setup already done: auto-start the watcher as normal.
            // No-op if watcher is already running (e.g. started via `make run`).
            autoStartOrShowSetup()
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
            autoStartOrShowSetup()
            // Show alert instead of flashIcon() — ผู้ใช้ใหม่มักไม่รู้ว่าแอปอยู่ที่ menu bar
            showAlreadyRunningAlert()
        }
        statusBarController?.refresh()
        return true
    }

    private func showAlreadyRunningAlert() {
        let alert = NSAlert()
        alert.messageText     = "Team Recorder กำลังทำงานอยู่"
        alert.informativeText = "มองหา icon ที่ menu bar มุมขวาบนของจอ (○ waveform)"
        alert.alertStyle      = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Setup Guide")
        // ชั่วคราว switch เป็น .regular เพื่อให้ alert ขึ้น front ได้
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertSecondButtonReturn {
            SetupWindowController.shared.show()
        }
    }

    private func autoStartOrShowSetup() {
        guard PermissionChecker.screenRecording() == .granted else {
            UserDefaults.standard.set(false, forKey: "setupCompleted")
            SetupWindowController.shared.show()
            return
        }
        WatcherManager.shared.autoStartIfNeeded()
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        }
        completionHandler()
    }
}
