import Foundation

/// Mirrors the schema written by write_status() in teams_recorder_v2.py.
/// DO NOT parse from log files — status.json is the canonical data source.
struct RecorderStatus: Codable {
    /// "idle" | "waiting" | "recording" | "stopping" | "error"
    var state: String
    var meetingName: String?
    var recordingPath: String?
    var startedAt: String?
    var lastError: String?
    // Persisted through waiting state so the menu bar can show the last saved file
    var lastRecordingPath: String?
    var lastRecordingName: String?
    var lastSavedAt: String?
    var lastStatus: String?
    var updatedAt: String?

    var updatedDate: Date? {
        guard let updatedAt else { return nil }
        return DateFormatter.teamRecorderStatus.date(from: updatedAt)
    }

    // MARK: — File location (must match APP_SUPPORT_DIR in teams_recorder_v2.py)

    static var statusFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Team Recorder/status.json")
    }

    /// Best-effort load — returns nil if file absent or unparseable.
    static func load() -> RecorderStatus? {
        guard let data = try? Data(contentsOf: statusFileURL) else { return nil }
        return try? JSONDecoder().decode(RecorderStatus.self, from: data)
    }
}

extension DateFormatter {
    static let teamRecorderStatus: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}
