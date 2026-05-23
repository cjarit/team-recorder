import AppKit
import Foundation

/// Manages the teams_recorder_v2.py watcher process lifecycle.
/// "Wrap, don't rewrite" — Python stays the brain; this class is just a launcher + PID tracker.
class WatcherManager {
    static let shared = WatcherManager()

    /// Absolute path to teams_recorder_v2.py, read from watcher_path.txt in the app bundle.
    private(set) var watcherURL: URL?

    var projectDirectory: URL? {
        watcherURL?.deletingLastPathComponent()
    }

    /// Process started by *this* app instance (nil if watcher was launched externally).
    private var managedProcess: Process?

    private init() {
        // watcher_path.txt is written into Resources/ by `make menu-bar`
        if let url = Bundle.main.url(forResource: "watcher_path", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let path = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                watcherURL = URL(fileURLWithPath: path)
            }
        }
    }

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

    /// Fallback: run `pgrep -f teams_recorder_v2.py` and return the first matching PID.
    /// Returns nil if not found or pgrep fails. Mirrors Python's `_pgrep_watcher_pids()`.
    private func pgrepWatcherPid() -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "teams_recorder_v2.py"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Return the first valid PID found
        return out.split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .first
            .map { pid_t($0) }
    }

    // MARK: — Start / Stop

    /// Start the Python watcher as a child process.
    /// No-ops if already running. Logs an error if watcher_path.txt is missing.
    func start() {
        guard let url = watcherURL else {
            NSLog("[TeamRecorderBar] watcher_path.txt not found in bundle — run `make menu-bar` again")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[TeamRecorderBar] teams_recorder_v2.py not found at: \(url.path)")
            return
        }
        guard !isRunning else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", url.path]
        // Run from the project directory so relative .env lookup works
        p.currentDirectoryURL = url.deletingLastPathComponent()
        p.environment = ProcessInfo.processInfo.environment.merging(["NOTIFY": "0"]) { $1 }
        // stdout/stderr → the existing daily log file the Python watcher manages itself
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.managedProcess = nil
                NotificationCenter.default.post(name: .watcherStateChanged, object: nil)
            }
        }

        do {
            try p.run()
            managedProcess = p
        } catch {
            NSLog("[TeamRecorderBar] Failed to launch watcher: \(error)")
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

    /// Update RECORDING_DIR in the project .env file and restart the watcher.
    /// Writes atomically; preserves all other .env lines.
    func setRecordingDir(_ url: URL) {
        guard let watcherURL else {
            NSLog("[TeamRecorderBar] setRecordingDir: watcherURL not set")
            return
        }
        let envFile = watcherURL.deletingLastPathComponent().appendingPathComponent(".env")
        let tmpFile = watcherURL.deletingLastPathComponent().appendingPathComponent(".env.tmp")

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

    /// Best-effort: parse RECORDING_DIR from the project .env file,
    /// fall back to the default path.
    func recordingDirectory() -> URL {
        if let watcherURL {
            let envFile = watcherURL.deletingLastPathComponent().appendingPathComponent(".env")
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
        guard processCommand(pid: p).contains("teams_recorder_v2.py") else {
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
