import AVFoundation
import CoreGraphics
import EventKit
import Foundation

/// Permission status for a single system resource.
enum PermissionStatus { case granted, denied, undetermined }

/// Static helpers to check and request macOS permissions needed by Team Recorder.
/// All request functions call back on the main thread.
struct PermissionChecker {

    // MARK: — Synchronous checks (safe on any thread)

    /// Screen Recording status via CGPreflightScreenCaptureAccess().
    /// macOS has no .undetermined state for screen capture — it's granted or not.
    static func screenRecording() -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Microphone authorization status. Does NOT request access.
    static func microphone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:                 return .granted
        case .denied, .restricted:        return .denied
        case .notDetermined:              return .undetermined
        @unknown default:                 return .undetermined
        }
    }

    /// Calendar authorization status. Does NOT request access.
    /// Handles macOS 14 .fullAccess / .writeOnly with #available guard.
    static func calendar() -> PermissionStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:              return .granted
            case .writeOnly:              return .denied   // write-only cannot read event titles
            case .authorized:             return .granted  // deprecated alias; same raw value as .fullAccess
            case .denied, .restricted:    return .denied
            case .notDetermined:          return .undetermined
            @unknown default:             return .undetermined
            }
        } else {
            switch status {
            case .authorized:             return .granted
            case .denied, .restricted:    return .denied
            case .notDetermined:          return .undetermined
            default:                      return .undetermined  // .fullAccess/.writeOnly won't appear on macOS 13
            }
        }
    }

    // MARK: — Permission requests

    /// Trigger the Screen Recording permission dialog.
    /// macOS will NOT add the app to the System Settings Screen Recording list
    /// until this is called at least once — the toggle is invisible without it.
    /// Fire-and-forget (synchronous call, result observed via screenRecording()).
    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: — Async requests (completion always called on main thread)

    /// Trigger the system microphone permission dialog.
    /// Completion is called immediately if already determined.
    static func requestMicrophone(completion: @escaping (PermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }

    /// Trigger the system calendar permission dialog.
    /// Uses requestFullAccessToEvents on macOS 14+; requestAccess(to:) on macOS 13.
    static func requestCalendar(completion: @escaping (PermissionStatus) -> Void) {
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    completion(granted ? .granted : .denied)
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    completion(granted ? .granted : .denied)
                }
            }
        }
    }

    /// Trigger the icalBuddy Calendar permission during setup.
    /// The Python watcher reads Calendar through icalBuddy, so the menu-bar app's
    /// own EventKit grant is not enough to prevent a second prompt in a meeting.
    static func primeIcalBuddyCalendar(projectDirectory: URL?,
                                       completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let binary = findIcalBuddy(projectDirectory: projectDirectory) else {
                DispatchQueue.main.async {
                    completion(false, "icalBuddy not found")
                }
                return
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = ["-f", "-nc", "-iep", "title,datetime", "-b", "||",
                           "-tf", "%H:%M", "-nrd", "eventsToday"]
            p.currentDirectoryURL = projectDirectory

            let stdout = Pipe()
            let stderr = Pipe()
            p.standardOutput = stdout
            p.standardError = stderr

            do {
                try p.run()
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
                return
            }

            let deadline = Date().addingTimeInterval(8)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if p.isRunning {
                p.terminate()
                DispatchQueue.main.async {
                    completion(false, "icalBuddy timed out")
                }
                return
            }

            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            let combined = (out + "\n" + err).lowercased()
            let denied = combined.contains("not authorized")
                || combined.contains("permission")
                || combined.contains("operation not permitted")
                || combined.contains("no calendars")
            DispatchQueue.main.async {
                completion(!denied, denied ? (err.isEmpty ? out : err) : "icalBuddy calendar access ready")
            }
        }
    }

    private static func findIcalBuddy(projectDirectory: URL?) -> String? {
        if let projectDirectory {
            let envFile = projectDirectory.appendingPathComponent(".env")
            if let content = try? String(contentsOf: envFile, encoding: .utf8) {
                for raw in content.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix("ICAL_BUDDY_PATH=") else { continue }
                    let value = String(line.dropFirst("ICAL_BUDDY_PATH=".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        let expanded = NSString(string: value).expandingTildeInPath
                        if FileManager.default.isExecutableFile(atPath: expanded) {
                            return expanded
                        }
                    }
                }
            }
        }

        if let env = ProcessInfo.processInfo.environment["ICAL_BUDDY_PATH"], !env.isEmpty {
            let expanded = NSString(string: env).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["icalBuddy"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        if (try? which.run()) != nil {
            which.waitUntilExit()
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                              encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty {
                return path
            }
        }

        let fallback = "/opt/homebrew/bin/icalBuddy"
        return FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
    }
}
