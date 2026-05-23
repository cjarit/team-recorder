import AppKit
import ServiceManagement
import UserNotifications

/// Owns the NSStatusItem and all menu interactions.
/// Refreshed on every status.json write (via DispatchSourceFileSystemObject)
/// and by a 5-second poll fallback for when the file doesn't exist yet.
class StatusBarController {
    private let statusItem: NSStatusItem

    // Dynamically updated menu items
    private var statusLine:          NSMenuItem!
    private var startRecordingItem:  NSMenuItem!
    private var stopRecordingItem:   NSMenuItem!
    private var toggleItem:          NSMenuItem!
    private var recoverItem:         NSMenuItem!
    private var folderPathItem:      NSMenuItem!   // shows current RECORDING_DIR (disabled)
    private var changeFolderItem:    NSMenuItem!
    private var lastRecordingItem:   NSMenuItem!
    private var launchAtLoginItem:   NSMenuItem!
    private var launchWarningItem:   NSMenuItem!   // hidden unless watcher failed to start
    fileprivate var icalBuddyStatusItem: NSMenuItem!   // shows live icalBuddy probe state
    fileprivate var icalBuddyProbeInFlight = false     // prevents stacking probes
    private var permSubmenuDelegate: PermSubmenuDelegate! // kept alive for NSMenuDelegate

    // File watcher for status.json
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer:  Timer?

    private var currentStatus: RecorderStatus?
    private var lastNotifiedRecordingPath: String?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        startWatching()
        refresh()
    }

    // MARK: — Menu construction

    private func buildMenu() {
        let menu = NSMenu()

        // Bold title row
        let titleItem = NSMenuItem()
        titleItem.attributedTitle = NSAttributedString(
            string: "Team Recorder",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // Launch-failure warning — hidden by default, shown when watcher can't start
        launchWarningItem = NSMenuItem(
            title: "⚠ Can't start watcher — Show details…",
            action: #selector(showLaunchWarning),
            keyEquivalent: ""
        )
        launchWarningItem.target = self
        launchWarningItem.isHidden = true
        menu.addItem(launchWarningItem)

        menu.addItem(.separator())

        // Live status line
        statusLine = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())

        // Manual recording controls
        startRecordingItem = NSMenuItem(
            title: "▶  Start Recording",
            action: #selector(startRecording),
            keyEquivalent: ""
        )
        startRecordingItem.target = self
        menu.addItem(startRecordingItem)

        stopRecordingItem = NSMenuItem(
            title: "■  Stop Recording",
            action: #selector(stopRecording),
            keyEquivalent: ""
        )
        stopRecordingItem.target = self
        menu.addItem(stopRecordingItem)

        menu.addItem(.separator())

        // Watcher start/stop toggle
        toggleItem = NSMenuItem(
            title: "Start Watcher",
            action: #selector(toggleWatcher),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        recoverItem = NSMenuItem(
            title: "Recover Recorder…",
            action: #selector(recoverRecorder),
            keyEquivalent: ""
        )
        recoverItem.target = self
        recoverItem.isHidden = true
        menu.addItem(recoverItem)

        // Recordings folder submenu
        let folderItem = NSMenuItem(title: "📁  Recordings Folder", action: nil, keyEquivalent: "")
        let folderSubmenu = NSMenu()

        folderPathItem = NSMenuItem(title: "~/Documents/Teams Recording", action: nil, keyEquivalent: "")
        folderPathItem.isEnabled = false
        folderSubmenu.addItem(folderPathItem)

        let openFolderItem = NSMenuItem(
            title: "Open Folder",
            action: #selector(openRecordingsFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        folderSubmenu.addItem(openFolderItem)

        folderSubmenu.addItem(.separator())

        changeFolderItem = NSMenuItem(
            title: "Change Folder…",
            action: #selector(changeRecordingsFolder),
            keyEquivalent: ""
        )
        changeFolderItem.target = self
        folderSubmenu.addItem(changeFolderItem)

        folderItem.submenu = folderSubmenu
        menu.addItem(folderItem)

        menu.addItem(.separator())

        // Last recording — clickable when a path is available
        lastRecordingItem = NSMenuItem(title: "No recordings yet", action: nil, keyEquivalent: "")
        lastRecordingItem.isEnabled = false
        menu.addItem(lastRecordingItem)

        menu.addItem(.separator())

        // Permissions submenu
        let permItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permSubmenu = NSMenu()
        permSubmenuDelegate = PermSubmenuDelegate()
        permSubmenuDelegate.controller = self
        permSubmenu.delegate = permSubmenuDelegate

        let screenItem = NSMenuItem(
            title: "Screen Recording…",
            action: #selector(openPermScreenRecording),
            keyEquivalent: ""
        )
        screenItem.target = self
        permSubmenu.addItem(screenItem)

        let micItem = NSMenuItem(
            title: "Microphone…",
            action: #selector(openPermMicrophone),
            keyEquivalent: ""
        )
        micItem.target = self
        permSubmenu.addItem(micItem)

        let calItem = NSMenuItem(
            title: "Calendar…",
            action: #selector(openPermCalendar),
            keyEquivalent: ""
        )
        calItem.target = self
        permSubmenu.addItem(calItem)

        permSubmenu.addItem(.separator())

        icalBuddyStatusItem = NSMenuItem(
            title: icalBuddyMenuTitle(),
            action: #selector(retryIcalBuddyAccess),
            keyEquivalent: ""
        )
        icalBuddyStatusItem.target = self
        icalBuddyStatusItem.toolTip = "Click to re-probe. Status updates each time you open this menu."
        permSubmenu.addItem(icalBuddyStatusItem)

        permItem.submenu = permSubmenu
        menu.addItem(permItem)

        // Setup Guide — re-opens the step-by-step permission window
        let setupItem = NSMenuItem(
            title: "Setup Guide…",
            action: #selector(openSetupGuide),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(.separator())

        // Launch at Login toggle
        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    // MARK: — Actions

    @objc private func startRecording() {
        WatcherManager.shared.startRecording()
    }

    @objc private func stopRecording() {
        WatcherManager.shared.stopRecording()
    }

    @objc private func toggleWatcher() {
        WatcherManager.shared.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func recoverRecorder() {
        let alert = NSAlert()
        alert.messageText = "Recover Recorder?"
        alert.informativeText = "This will stop any stuck recording process and clear stale menu-bar status. The current file may be incomplete."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WatcherManager.shared.recoverStaleRecordingState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func openRecordingsFolder() {
        if let path = currentStatus?.lastRecordingPath {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            NSWorkspace.shared.open(dir)
            return
        }
        NSWorkspace.shared.open(WatcherManager.shared.recordingDirectory())
    }

    @objc private func changeRecordingsFolder() {
        NSApp.activate(ignoringOtherApps: true)   // bring picker above other windows
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt               = "Choose Folder"
        panel.message              = "Select the folder where recordings will be saved"
        panel.directoryURL         = WatcherManager.shared.recordingDirectory()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WatcherManager.shared.setRecordingDir(url)
        // Update the path display optimistically — next refresh will confirm
        folderPathItem.title = abbreviatedPath(url.path)
    }

    @objc private func openLastRecording() {
        guard let path = currentStatus?.lastRecordingPath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    @objc private func openPermScreenRecording() {
        openPrefPane("Privacy_ScreenCapture")
    }
    @objc private func openPermMicrophone() {
        openPrefPane("Privacy_Microphone")
    }
    @objc private func openPermCalendar() {
        openPrefPane("Privacy_Calendars")
    }
    private func openPrefPane(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: — File watching

    private func startWatching() {
        watchFile()
        // 5-second poll fallback handles startup (file may not exist yet) and missed events.
        // Also re-attaches the DispatchSource if watchFile() returned early because the
        // file was absent when the app launched.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
            if self?.fileSource == nil {
                self?.watchFile()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .watcherStateChanged,
            object: nil
        )
    }

    private func watchFile() {
        let path = RecorderStatus.statusFileURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }  // File absent — poll timer will retry

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            self?.refresh()
            // Atomic writes (Python's os.replace) trigger rename; re-attach after settle
            let data = source?.data ?? []
            if data.contains(.delete) || data.contains(.rename) {
                source?.cancel()
                self?.fileSource = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.watchFile()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    @objc func refresh() {
        let previousStatus = currentStatus
        currentStatus = RecorderStatus.load()
        updateStatusLine()
        updateControlItems()
        updateFolderItems()
        updateLastRecordingItem()
        updateLaunchAtLoginItem()
        updateLaunchWarning()
        updateIcon()
        notifyIfRecordingSaved(previous: previousStatus, current: currentStatus)
    }

    // MARK: — Menu updates

    private func updateStatusLine() {
        let s = currentStatus
        if isStaleRecordingState {
            statusLine.title = "⚠ Status stale — recover recorder"
            return
        }
        guard let s else {
            statusLine.title = WatcherManager.shared.isRunning
                ? "○ Watcher running — no status yet"
                : "○ Idle — watcher not running"
            return
        }
        switch s.state {
        case "recording":
            let name = s.meetingName ?? "Meeting"
            statusLine.title = "● Recording: \(name)"
        case "stopping":
            statusLine.title = "◌ Stopping…"
        case "waiting":
            statusLine.title = "○ Waiting for Teams meeting…"
        case "error":
            let err   = s.lastError ?? "Unknown error"
            let short = err.count > 60 ? String(err.prefix(57)) + "…" : err
            statusLine.title = "⚠ Error: \(short)"
        default:
            statusLine.title = "○ Idle"
        }
    }

    /// Update all three watcher/recording control items together.
    private func updateControlItems() {
        let state     = currentStatus?.state ?? "idle"
        let running   = WatcherManager.shared.isRunning
        let stale     = isStaleRecordingState
        let recording = state == "recording" && !stale
        let stopping  = state == "stopping" && !stale

        // ▶ Start Recording: enabled when watcher is up and not already recording/stopping
        startRecordingItem.isEnabled = running && !recording && !stopping && !stale

        // ■ Stop Recording: enabled only while recording
        stopRecordingItem.isEnabled = recording
        recoverItem.isHidden = !stale && state != "error"
        recoverItem.isEnabled = stale || state == "error"

        // Start/Stop Watcher toggle
        if WatcherManager.shared.watcherURL == nil {
            toggleItem.title     = "Watcher not configured"
            toggleItem.isEnabled = false
        } else {
            toggleItem.title     = running ? "Stop Watcher" : "Start Watcher"
            toggleItem.isEnabled = true
        }
    }

    private func updateFolderItems() {
        let dir = WatcherManager.shared.recordingDirectory()
        folderPathItem.title = abbreviatedPath(dir.path)

        // Disable "Change Folder…" while a recording is active or stopping
        let state = currentStatus?.state ?? "idle"
        changeFolderItem.isEnabled = (state != "recording" && state != "stopping") || isStaleRecordingState
    }

    private func updateLastRecordingItem() {
        guard let name = currentStatus?.lastRecordingName else {
            lastRecordingItem.title    = "No recordings yet"
            lastRecordingItem.isEnabled = false
            lastRecordingItem.action   = nil
            return
        }
        var label = "Last: \(name)"
        if let savedAt = currentStatus?.lastSavedAt, savedAt.count >= 16 {
            let time = String(savedAt.dropFirst(11).prefix(5))  // "HH:MM"
            label += " (\(time))"
        }
        lastRecordingItem.title = label
        if currentStatus?.lastRecordingPath != nil {
            lastRecordingItem.isEnabled = true
            lastRecordingItem.action    = #selector(openLastRecording)
            lastRecordingItem.target    = self
        } else {
            lastRecordingItem.isEnabled = false
        }
    }

    private func updateIcon() {
        let hasError = WatcherManager.shared.lastLaunchError != nil
        let state = hasError ? "error" : (isStaleRecordingState ? "error" : (currentStatus?.state ?? "idle"))
        statusItem.button?.image   = icon(for: state)
        statusItem.button?.toolTip = tooltipText(for: state)
    }

    private func updateLaunchWarning() {
        // Auto-clear stale launch error if a watcher is now running (e.g. started via `make run`)
        WatcherManager.shared.clearLaunchErrorIfRunning()
        let hasError = WatcherManager.shared.lastLaunchError != nil
        launchWarningItem.isHidden = !hasError
    }

    @objc private func showLaunchWarning() {
        guard let error = WatcherManager.shared.lastLaunchError else { return }
        let alert = NSAlert()
        alert.messageText = "Team Recorder — Can't start watcher"
        alert.informativeText = error.userDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run Setup Guide")
        alert.addButton(withTitle: "Open Project Folder")
        alert.addButton(withTitle: "Dismiss")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SetupWindowController.shared.show()
        case .alertSecondButtonReturn:
            if let dir = WatcherManager.shared.projectDirectory {
                NSWorkspace.shared.open(dir)
            }
        default:
            break
        }
    }

    @objc private func retryIcalBuddyAccess() {
        NSApp.activate(ignoringOtherApps: true)
        // Probe is async (≤4s). Result shown in the completion alert below.
        PermissionChecker.primeIcalBuddyCalendar(
            projectDirectory: WatcherManager.shared.projectDirectory
        ) { [weak self] ok, detail in
            DispatchQueue.main.async {
                guard let self else { return }
                UserDefaults.standard.set(ok, forKey: "icalBuddyVerified")
                self.icalBuddyStatusItem.title = self.icalBuddyMenuTitle()
                let result = NSAlert()
                result.messageText = ok ? "icalBuddy Access Confirmed" : "icalBuddy Access Advisory"
                result.informativeText = ok
                    ? "icalBuddy can read Calendar events. Recordings will be named after meeting titles."
                    : "icalBuddy probe returned an advisory:\n\(detail)\n\nRecordings may be named \"Teams Meeting\". Grant Calendar access to icalBuddy in System Settings → Privacy & Security → Automation."
                result.alertStyle = ok ? .informational : .warning
                result.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                result.runModal()
            }
        }
    }

    // MARK: — Icon helpers

    private func icon(for state: String) -> NSImage? {
        let size = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        switch state {
        case "recording":
            let colorConf = NSImage.SymbolConfiguration(hierarchicalColor: .systemRed)
            return NSImage(systemSymbolName: "record.circle.fill",
                           accessibilityDescription: "Recording")?
                .withSymbolConfiguration(size.applying(colorConf))
        case "stopping":
            let colorConf = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            return NSImage(systemSymbolName: "stop.circle",
                           accessibilityDescription: "Stopping")?
                .withSymbolConfiguration(size.applying(colorConf))
        case "error":
            let colorConf = NSImage.SymbolConfiguration(hierarchicalColor: .systemOrange)
            return NSImage(systemSymbolName: "exclamationmark.circle.fill",
                           accessibilityDescription: "Error")?
                .withSymbolConfiguration(size.applying(colorConf))
        default:
            let img = NSImage(systemSymbolName: "waveform.circle",
                              accessibilityDescription: "Team Recorder")?
                .withSymbolConfiguration(size)
            img?.isTemplate = true
            return img
        }
    }

    private func tooltipText(for state: String) -> String {
        if isStaleRecordingState {
            return "Team Recorder — stale status, click to recover"
        }
        switch state {
        case "recording":
            let name = currentStatus?.meetingName ?? "Meeting"
            return "Team Recorder — Recording: \(name)"
        case "stopping":  return "Team Recorder — Stopping…"
        case "waiting":   return "Team Recorder — Waiting for Teams meeting"
        case "error":     return "Team Recorder — Error (click for details)"
        default:          return "Team Recorder"
        }
    }

    // MARK: — Helpers

    /// Shorten a path for display: ~/Documents/… instead of /Users/name/Documents/…
    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private var isStaleRecordingState: Bool {
        guard let s = currentStatus else { return false }
        if s.state == "recording" && !WatcherManager.shared.isRunning {
            return true
        }
        if s.state == "stopping" {
            guard let updated = s.updatedDate else { return true }
            return Date().timeIntervalSince(updated) > 45
        }
        return false
    }

    private func notifyIfRecordingSaved(previous: RecorderStatus?, current: RecorderStatus?) {
        guard let current,
              current.state == "waiting",
              let path = current.lastRecordingPath,
              path != lastNotifiedRecordingPath,
              WatcherManager.shared.isAppManagedWatcherRunning else {
            return
        }
        if previous?.state == "recording" || previous?.state == "stopping" {
            lastNotifiedRecordingPath = path
            sendSavedNotification(path: path, name: current.lastRecordingName)
        }
    }

    private func sendSavedNotification(path: String, name: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Team Recorder"
        content.body = "Saved: \(name ?? URL(fileURLWithPath: path).lastPathComponent)"
        content.sound = .default
        content.userInfo = ["filePath": path]
        let request = UNNotificationRequest(
            identifier: "team-recorder-saved-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[TeamRecorderBar] notification failed: \(error)")
            }
        }
    }

    // MARK: — Setup Guide & Launch at Login

    @objc private func openSetupGuide() {
        SetupWindowController.shared.show()
    }

    /// Update checkmark state and tooltip for "Launch at Login".
    /// Called from refresh() so the state always reflects the actual SMAppService status.
    private func updateLaunchAtLoginItem() {
        let svc = SMAppService.mainApp
        switch svc.status {
        case .enabled:
            launchAtLoginItem.state     = .on
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.toolTip   = nil
        case .requiresApproval:
            // ผู้ใช้ต้องอนุมัติใน System Settings → General → Login Items
            launchAtLoginItem.state     = .mixed
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.toolTip   = "Waiting for approval in System Settings → General → Login Items"
        case .notFound:
            // app ไม่ได้อยู่ใน /Applications/ — SMAppService ต้องการ path นี้เพื่อ register
            launchAtLoginItem.state     = .off
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.toolTip   = "Move TeamRecorderBar.app to /Applications/ to enable this"
        default:
            launchAtLoginItem.state     = .off
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.toolTip   = nil
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
            } else {
                try svc.register()
            }
        } catch {
            // แสดง alert แทน log เพราะผู้ใช้ทีมไม่ได้เปิด Terminal
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = svc.status == .notFound
                ? "Move TeamRecorderBar.app to /Applications/ first, then try again."
                : "Could not update Login Item:\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateLaunchAtLoginItem()
    }

    // MARK: — Double-click feedback

    /// Brief icon dimming to confirm the app is already running when double-clicked.
    func flashIcon() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            button.appearsDisabled = false
        }
    }

    // MARK: — icalBuddy status helpers

    fileprivate func icalBuddyMenuTitle() -> String {
        let verified = UserDefaults.standard.bool(forKey: "icalBuddyVerified")
        return verified ? "icalBuddy: Verified ✓" : "icalBuddy: No Access ⚠"
    }
}

// MARK: — NSMenuDelegate helper (probe icalBuddy on Permissions submenu open)
// StatusBarController doesn't inherit NSObject, so delegate is a thin helper.

private class PermSubmenuDelegate: NSObject, NSMenuDelegate {
    weak var controller: StatusBarController?

    func menuWillOpen(_ menu: NSMenu) {
        guard let c = controller, !c.icalBuddyProbeInFlight else { return }
        c.icalBuddyProbeInFlight = true
        PermissionChecker.primeIcalBuddyCalendar(
            projectDirectory: WatcherManager.shared.projectDirectory
        ) { [weak c] ok, _ in
            DispatchQueue.main.async {
                guard let c else { return }
                c.icalBuddyProbeInFlight = false
                UserDefaults.standard.set(ok, forKey: "icalBuddyVerified")
                c.icalBuddyStatusItem.title = c.icalBuddyMenuTitle()
            }
        }
    }
}
