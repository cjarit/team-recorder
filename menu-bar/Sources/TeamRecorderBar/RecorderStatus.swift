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
    /// Set by the watcher when the recording fell back to the "Teams Meeting" name.
    /// Plain-English reason, e.g. "calendar access denied", "no events on calendar".
    var lastFallbackReason: String?
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

/// Mirrors levels.json written by the recorder once per second while recording.
struct RecorderLevels: Codable {
    static let staleAfterSeconds: TimeInterval = 3

    var ts: String
    var sysRms: Double
    var micRms: Double
    var micAlive: Bool
    var micDevice: String?
    var micEnabled: Bool?

    static var fileURL: URL {
        RecorderStatus.statusFileURL.deletingLastPathComponent().appendingPathComponent("levels.json")
    }

    static func load() -> RecorderLevels? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RecorderLevels.self, from: data)
    }

    var isStale: Bool {
        guard let date = DateFormatter.teamRecorderStatus.date(from: ts) else { return true }
        return Date().timeIntervalSince(date) > Self.staleAfterSeconds
    }
}

/// Mirrors <recording>.meta.json written by `recorder --mixdown` after a recording is saved.
struct RecordingMeta: Codable {
    var speechRatio: Double
    var durationSec: Double
    var mixedAt: String

    static func load(forRecording path: String) -> RecordingMeta? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path + ".meta.json")) else { return nil }
        return try? JSONDecoder().decode(RecordingMeta.self, from: data)
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
