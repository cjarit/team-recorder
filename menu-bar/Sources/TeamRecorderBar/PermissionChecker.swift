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
                DispatchQueue.main.async { completion(false, "icalBuddy not found") }
                return
            }
            // One retry: if the first attempt fails with an ambiguous (non-permission) error,
            // wait briefly and try once more — handles transient TCC daemon delays.
            runIcalBuddyProbe(binary: binary, projectDirectory: projectDirectory) { ok, detail, explicitlyDenied in
                if ok || explicitlyDenied {
                    DispatchQueue.main.async { completion(ok, detail) }
                    return
                }
                // Ambiguous result — retry once after a short pause
                Thread.sleep(forTimeInterval: 0.5)
                runIcalBuddyProbe(binary: binary, projectDirectory: projectDirectory) { ok2, detail2, _ in
                    DispatchQueue.main.async { completion(ok2, detail2) }
                }
            }
        }
    }

    private static func runIcalBuddyProbe(binary: String,
                                          projectDirectory: URL?,
                                          completion: (Bool, String, Bool) -> Void) {
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
            completion(false, error.localizedDescription, false)
            return
        }

        let deadline = Date().addingTimeInterval(4)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if p.isRunning {
            p.terminate()
            completion(false, "icalBuddy timed out", false)
            return
        }

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""

        // Trust exit code as the primary signal.
        // exit 0  → granted (even "no events today" is valid).
        // non-zero + permission keywords → explicitly denied.
        // non-zero, no keywords → ambiguous; caller decides whether to retry.
        if p.terminationStatus == 0 {
            completion(true, "icalBuddy calendar access ready", false)
            return
        }
        let combined = (out + "\n" + err).lowercased()
        let explicitlyDenied = combined.contains("not authorized")
            || combined.contains("operation not permitted")
            || combined.contains("no calendars")
        let detail = err.isEmpty ? out : err
        completion(false, explicitlyDenied ? detail : "icalBuddy returned non-zero (\(p.terminationStatus)): \(detail)", explicitlyDenied)
    }

    private static func findIcalBuddy(projectDirectory: URL?) -> String? {
        // Order mirrors Python: process env (including load_dotenv overrides) wins,
        // then the raw .env file, then PATH lookup, then Homebrew fallback.

        // 1. Process environment — already includes anything load_dotenv injected
        if let env = ProcessInfo.processInfo.environment["ICAL_BUDDY_PATH"], !env.isEmpty {
            let expanded = NSString(string: env).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        // 2. Project .env file — only reached if ICAL_BUDDY_PATH was not in the inherited env
        if let projectDirectory {
            let envFile = projectDirectory.appendingPathComponent(".env")
            if let content = try? String(contentsOf: envFile, encoding: .utf8) {
                for raw in content.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix("ICAL_BUDDY_PATH="), !line.hasPrefix("#") else { continue }
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

        // 3. PATH lookup via `which`
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

        // 4. Homebrew fallback
        let fallback = "/opt/homebrew/bin/icalBuddy"
        return FileManager.default.isExecutableFile(atPath: fallback) ? fallback : nil
    }
}
