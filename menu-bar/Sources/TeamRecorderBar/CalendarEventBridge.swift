import EventKit
import Foundation

final class CalendarEventBridge {
    static let shared = CalendarEventBridge()
    private let store = EKEventStore()
    private var observations: [NSObjectProtocol] = []
    private var timers: [Timer] = []
    private var isObserving = false

    private static let trackedCalendarIdsKey = "trackedCalendarIds"

    static var eventsFileURL: URL {
        RecorderStatus.statusFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("events-today.json")
    }

    private init() {}

    // All event calendars sorted by title — consumed by the Tracked Calendars submenu.
    func allCalendars() -> [EKCalendar] {
        guard PermissionChecker.calendar() == .granted else { return [] }
        return store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    // nil = no allowlist (track all calendars).
    var trackedCalendarIds: [String]? {
        UserDefaults.standard.stringArray(forKey: Self.trackedCalendarIdsKey)
    }

    // Persists the allowlist and triggers an immediate bridge-file update.
    // Pass nil to reset to "track all".
    func setTrackedCalendarIds(_ ids: [String]?) {
        if let ids {
            UserDefaults.standard.set(ids, forKey: Self.trackedCalendarIdsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.trackedCalendarIdsKey)
        }
        writeEventsIfAuthorized()
    }

    func writeEventsIfAuthorized() {
        guard PermissionChecker.calendar() == .granted else {
            writeJSON(["date": todayString(), "authorized": false] as [String: Any])
            return
        }

        // Resolve calendar filter. Stale IDs (deleted/unavailable calendars) are silently
        // ignored — never written back to UserDefaults here to avoid falsely clearing
        // the allowlist during transient account sync outages.
        // nil   = track all (no allowlist set)
        // []    = user explicitly unchecked everything → write empty events (Python falls back to "Teams Meeting")
        // [ids] = filter; if all IDs are stale, fall back to allCals (transient unavailability guard)
        let allCals = store.calendars(for: .event)
        let filteredCals: [EKCalendar]
        if let storedIds = UserDefaults.standard.stringArray(forKey: Self.trackedCalendarIdsKey) {
            guard !storedIds.isEmpty else {
                writeJSON([
                    "date":      todayString(),
                    "updatedAt": DateFormatter.teamRecorderStatus.string(from: Date()),
                    "events":    [[String: String]](),
                ] as [String: Any])
                return
            }
            let valid = allCals.filter { storedIds.contains($0.calendarIdentifier) }
            filteredCals = valid.isEmpty ? allCals : valid
        } else {
            filteredCals = allCals
        }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let pred = store.predicateForEvents(withStart: startOfDay, end: endOfDay,
                                            calendars: filteredCals)
        let events = store.events(matching: pred)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm"
        let eventDicts: [[String: String]] = events
            .filter { !$0.isAllDay }
            .compactMap { e in
                guard let title = e.title, !title.isEmpty else { return nil }
                var d: [String: String] = [
                    "title":      title,
                    "start":      fmt.string(from: e.startDate),
                    "calendar":   e.calendar?.title ?? "",
                    "calendarId": e.calendar?.calendarIdentifier ?? "",
                ]
                if let endDate = e.endDate {
                    d["end"] = fmt.string(from: endDate)
                }
                return d
            }
        writeJSON([
            "date":      todayString(),
            "updatedAt": DateFormatter.teamRecorderStatus.string(from: Date()),
            "events":    eventDicts,
        ] as [String: Any])
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let obs = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.writeEventsIfAuthorized()
        }
        observations.append(obs)
        scheduleTimers()
    }

    private func scheduleTimers() {
        for t in timers { t.invalidate() }
        timers.removeAll()
        let repeat10 = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.writeEventsIfAuthorized()
        }
        timers.append(repeat10)
        let midnightTimer = Timer(fire: nextMidnight(), interval: 0, repeats: false) { [weak self] _ in
            self?.writeEventsIfAuthorized()
            self?.scheduleTimers()
        }
        RunLoop.main.add(midnightTimer, forMode: .common)
        timers.append(midnightTimer)
    }

    private func nextMidnight() -> Date {
        Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func writeJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else { return }
        let url = Self.eventsFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
