import AVFoundation
import CoreGraphics
import EventKit

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
}
