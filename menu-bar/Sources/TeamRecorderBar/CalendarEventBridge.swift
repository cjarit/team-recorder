import EventKit
import Foundation

final class CalendarEventBridge {
    static let shared = CalendarEventBridge()
    private let store = EKEventStore()
    private var observations: [NSObjectProtocol] = []
    private var timers: [Timer] = []
    private var isObserving = false

    static var eventsFileURL: URL {
        RecorderStatus.statusFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("events-today.json")
    }

    private init() {}

    func writeEventsIfAuthorized() {
        guard PermissionChecker.calendar() == .granted else {
            writeJSON(["date": todayString(), "authorized": false] as [String: Any])
            return
        }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let pred = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: pred)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm"
        let eventDicts: [[String: String]] = events
            .filter { !$0.isAllDay }
            .compactMap { e in
                guard let title = e.title, !title.isEmpty else { return nil }
                var d: [String: String] = ["title": title, "start": fmt.string(from: e.startDate)]
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
