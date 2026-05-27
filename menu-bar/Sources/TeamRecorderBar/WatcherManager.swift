import AppKit
import Foundation

/// Reason the watcher failed to start. Read by StatusBarController to show user-visible details.
enum LaunchError {
    case watcherNotFound
    case pythonNotFound
    case pythonTooOld
    case earlyExit(code: Int32, stderr: String)
    case launchFailed(String)

    var userDescription: String {
        switch self {
        case .watcherNotFound:
            return "watcher.pyz not found in the app bundle.\nRe-download TeamRecorderBar.app from GitHub Releases."
        case .pythonNotFound:
            return "Python 3.9+ required.\nInstall Xcode Command Line Tools:\n  xcode-select --install"
        case .pythonTooOld:
            return "Python 3.9 or later required (found older version).\nInstall Xcode Command Line Tools:\n  xcode-select --install"
        case .earlyExit(let code, let stderr):
            let detail = stderr.isEmpty ? "(no output)" : stderr.prefix(400).description
            return "Watcher crashed immediately (exit \(code)):\n\(detail)"
        case .launchFailed(let reason):
            return "Failed to launch watcher:\n\(reason)"
        }
    }
}

/// Manages the teams_recorder_v2.py watcher process lifecycle.
/// "Wrap, don't rewrite" — Python stays the brain; this class is just a launcher + PID tracker.
class WatcherManager {
    static let shared = WatcherManager()

    /// watcher.pyz bundled inside the .app. nil when the bundle is missing/corrupted.
    var watcherURL: URL? {
        Bundle.main.url(forResource: "watcher", withExtension: "pyz")
    }

    /// No project directory in the portable .app — kept for API compatibility (always nil).
    var projectDirectory: URL? { nil }

    private static let systemPython = URL(fileURLWithPath: "/usr/bin/python3")

    private static var appSupportEnvFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Team Recorder/.env")
    }

    /// Process started by *this* app instance (nil if watcher was launched externally).
    private var managedProcess: Process?

    /// Set when start() fails or the watcher crashes within 3s of launch. Cleared on a new start().
    /// Read by StatusBarController to show a user-visible error indicator.
    private(set) var lastLaunchError: LaunchError?

    private init() {}

    // MARK: — State

    /// True if a watcher is running — checked in order:
    /// 1. Process we started (managedProcess)
    /// 2. PID file written by the Python watcher
    /// 3. pgrep fallback — catches the case where the watcher is running but its PID file is missing/stale
    var isRunning: Bool {
        if managedProcess?.isRunning == true { return true }
        if externalPidIsAlive() { return true }
        return pgrepWatcherPid() != nil
    }

    var isAppManagedWatcherRunning: Bool {
        managedProcess?.isRunning == true
    }

    /// Fallback: pgrep for watcher.pyz (app mode) then teams_recorder_v2.py (make run / Terminal).
    /// Returns nil if not found or pgrep fails. Mirrors Python's `_pgrep_watcher_pids()`.
    private func pgrepWatcherPid() -> pid_t? {
        for pattern in ["watcher.pyz", "teams_recorder_v2.py"] {
            if let pid = pgrepFirst(pattern: pattern) { return pid }
        }
        return nil
    }

    private func pgrepFirst(pattern: String) -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .first
            .map { pid_t($0) }
    }

    // MARK: — Start / Stop

    /// Start the Python watcher as a child process.
    /// No-ops if already running. Sets lastLaunchError and posts watcherStateChanged on failure.
    func start() {
        lastLaunchError = nil  // clear any previous error before attempting

        guard let watcherURL else {
            NSLog("[TeamRecorderBar] watcher.pyz not found in bundle")
            lastLaunchError = .watcherNotFound
            NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            return
        }
        let python = WatcherManager.systemPython
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            NSLog("[TeamRecorderBar] /usr/bin/python3 not found or not executable")
            lastLaunchError = .pythonNotFound
            NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            return
        }
        guard !isRunning else { return }

        let recorderURL = Bundle.main.url(forResource: "recorder", withExtension: nil)
        let envFileURL  = WatcherManager.appSupportEnvFileURL

        let p = Process()
        p.executableURL = python
        p.arguments     = [watcherURL.path]
        var env = ProcessInfo.processInfo.environment
        env["NOTIFY"]              = "0"
        env["TEAM_RECORDER_APP"]   = "1"
        env["ENV_FILE"]            = envFileURL.path
        if let recURL = recorderURL {
            env["RECORDER_BIN"]    = recURL.path
        }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice

        // Capture stderr into a pipe so early crashes produce user-visible detail
        let stderrPipe = Pipe()
        p.standardError = stderrPipe

        let launchedAt = Date()
        p.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            let elapsed = Date().timeIntervalSince(launchedAt)
            // Early crash: read stderr synchronously (pipe is closed, readDataToEndOfFile won't block)
            DispatchQueue.global(qos: .utility).async {
                var stderrStr = ""
                if elapsed < 3 && code != 0 {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stderrStr = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    NSLog("[TeamRecorderBar] watcher early-exit (code \(code)): \(stderrStr)")
                }
                DispatchQueue.main.async {
                    self?.managedProcess = nil
                    if elapsed < 3 && code != 0 {
                        self?.lastLaunchError = .earlyExit(code: code, stderr: stderrStr)
                    }
                    NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
                }
            }
        }

        do {
            try p.run()
            managedProcess = p
            NSLog("[TeamRecorderBar] watcher started (pid \(p.processIdentifier))")
        } catch {
            NSLog("[TeamRecorderBar] Failed to launch watcher: \(error)")
            lastLaunchError = .launchFailed(error.localizedDescription)
            NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
        }
    }

    /// Terminate the watcher gracefully (SIGTERM).
    /// Stops the managed process → PID file → pgrep fallback, in that order.
    /// Used by the "Stop Watcher" menu item.
    func stop() {
        if managedProcess?.isRunning == true {
            managedProcess?.terminate()
            return
        }
        // PID file first, then pgrep fallback
        if let pid = verifiedExternalPid() {
            kill(pid, SIGTERM)
            return
        }
        if let pid = pgrepWatcherPid() {
            kill(pid, SIGTERM)
        }
    }

    /// Stop ONLY the process this app started — never touches external watchers.
    /// Called by applicationWillTerminate so quitting the menu bar app does not
    /// kill a watcher that was started by Start Recorder.command or `make run`.
    func stopManagedOnly() {
        managedProcess?.terminate()
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    /// Start the watcher automatically on app launch — only if nothing is already running.
    /// Called once from applicationDidFinishLaunching.
    func autoStartIfNeeded() {
        guard !isRunning else { return }
        start()
    }

    /// Clear a stale launch error when an external watcher (e.g. `make run`) is confirmed running.
    /// Called by StatusBarController.updateLaunchWarning() so the ⚠ icon auto-clears.
    func clearLaunchErrorIfRunning() {
        guard lastLaunchError != nil, isRunning else { return }
        lastLaunchError = nil
    }

    // MARK: — Manual recording controls (SIGUSR1 / SIGUSR2)

    /// PID of the running watcher — managed process → PID file → pgrep fallback.
    private func watcherPid() -> pid_t? {
        if let p = managedProcess, p.isRunning {
            return pid_t(p.processIdentifier)
        }
        if let pid = verifiedExternalPid() {
            return pid
        }
        return pgrepWatcherPid()
    }

    /// Tell the watcher to start recording immediately (SIGUSR1).
    func startRecording() {
        guard let pid = watcherPid() else {
            NSLog("[TeamRecorderBar] startRecording: watcher not running")
            return
        }
        kill(pid, SIGUSR1)
    }

    /// Tell the watcher to stop the current recording (SIGUSR2).
    func stopRecording() {
        guard let pid = watcherPid() else {
            NSLog("[TeamRecorderBar] stopRecording: watcher not running")
            return
        }
        kill(pid, SIGUSR2)
    }

    // MARK: — Change recordings folder

    /// Update RECORDING_DIR in the App Support .env file and restart the watcher.
    /// Writes atomically; preserves all other .env lines.
    func setRecordingDir(_ url: URL) {
        let envFile = WatcherManager.appSupportEnvFileURL
        let tmpFile = envFile.deletingLastPathComponent().appendingPathComponent(".env.tmp")

        // Read existing lines (ok if file is absent)
        var lines = (try? String(contentsOf: envFile, encoding: .utf8))?
            .components(separatedBy: .newlines) ?? []

        let newLine = "RECORDING_DIR=\(url.path)"
        var replaced = false
        lines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("RECORDING_DIR=") {
                replaced = true
                return newLine
            }
            return line
        }
        if !replaced { lines.append(newLine) }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: tmpFile, atomically: false, encoding: .utf8)
            // replaceItemAt atomically replaces an existing file (unlike moveItem which fails if dest exists)
            _ = try FileManager.default.replaceItemAt(envFile, withItemAt: tmpFile,
                                                      backupItemName: nil, options: [])
        } catch {
            // replaceItemAt fails if envFile doesn't exist yet — fall back to a plain move
            do {
                try FileManager.default.moveItem(at: tmpFile, to: envFile)
            } catch {
                NSLog("[TeamRecorderBar] setRecordingDir write failed: \(error)")
                return
            }
        }

        // Restart watcher so it picks up the new RECORDING_DIR
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.start()
        }
    }

    // MARK: — Recording directory (for "Open Recordings Folder")

    /// Best-effort: parse RECORDING_DIR from the App Support .env file,
    /// fall back to the default path.
    func recordingDirectory() -> URL {
        let envFile = WatcherManager.appSupportEnvFileURL
        if let content = try? String(contentsOf: envFile, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("RECORDING_DIR=") {
                    let value = String(trimmed.dropFirst("RECORDING_DIR=".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty && !value.hasPrefix("#") {
                        return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
                    }
                }
            }
        }
        // Default — must match RECORDING_DIR default in teams_recorder_v2.py
        return URL(fileURLWithPath: NSString("~/Documents/Teams Recording").expandingTildeInPath)
    }

    // MARK: — PID file helpers (must match PID_FILE path in teams_recorder_v2.py)

    private static var pidFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Team Recorder/team-recorder.pid")
    }

    private static var recorderPidFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Team Recorder/recorder.pid")
    }

    private func externalPid() -> Int? {
        guard let content = try? String(contentsOf: WatcherManager.pidFileURL, encoding: .utf8) else {
            return nil
        }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func externalPidIsAlive() -> Bool {
        verifiedExternalPid() != nil
    }

    private func verifiedExternalPid() -> pid_t? {
        guard let pid = externalPid() else { return nil }
        let p = pid_t(pid)
        guard kill(p, 0) == 0 else {
            removeStaleFile(WatcherManager.pidFileURL)
            return nil
        }
        let cmd = processCommand(pid: p)
        guard cmd.contains("teams_recorder_v2.py") || cmd.contains("watcher.pyz") else {
            removeStaleFile(WatcherManager.pidFileURL)
            return nil
        }
        return p
    }

    private func recorderPid() -> pid_t? {
        guard let content = try? String(contentsOf: WatcherManager.recorderPidFileURL, encoding: .utf8),
              let pid = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let p = pid_t(pid)
        guard kill(p, 0) == 0 else {
            removeStaleFile(WatcherManager.recorderPidFileURL)
            return nil
        }
        let cmd = processCommand(pid: p)
        guard cmd.contains("/recorder") || cmd.hasSuffix("recorder") else {
            removeStaleFile(WatcherManager.recorderPidFileURL)
            return nil
        }
        return p
    }

    func recoverStaleRecordingState() {
        if let pid = recorderPid() {
            kill(pid, SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if kill(pid, 0) == 0 {
                    kill(pid, SIGKILL)
                }
                NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            }
            // Python owns the watcher and will detect the recorder child exit,
            // mark the active file incomplete, and reconnect the child if needed.
            NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            return
        }

        if verifiedExternalPid() == nil {
            clearStatusToIdle()
            NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            return
        }

        // No recorder child is available for Python to observe. At this point the
        // safest user-facing recovery is to stop the stuck watcher and clear stale UI.
        if let watcher = verifiedExternalPid() { kill(watcher, SIGTERM) }
        clearStatusToIdle()
        NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
    }

    private func clearStatusToIdle() {
        let url = RecorderStatus.statusFileURL
        let payload: [String: Any?] = [
            "state": "idle",
            "meetingName": nil,
            "recordingPath": nil,
            "startedAt": nil,
            "lastError": "stale recording state cleared from menu bar app",
            "lastRecordingPath": nil,
            "lastRecordingName": nil,
            "lastSavedAt": nil,
            "lastStatus": nil,
            "updatedAt": DateFormatter.teamRecorderStatus.string(from: Date()),
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 },
                                                   options: [.prettyPrinted])
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("[TeamRecorderBar] clearStatusToIdle failed: \(error)")
        }
    }

    private func processCommand(pid: pid_t) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-p", String(pid), "-o", "command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func removeStaleFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension Notification.Name {
    static let watcherStateChanged = Notification.Name("TeamRecorderBarWatcherStateChanged")
}
