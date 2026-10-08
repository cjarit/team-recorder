import AppKit
import CoreAudio
import EventKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case status, general, calendars, permissions
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(tag: String, url: URL)
    case failed
}

final class SettingsNavigator: ObservableObject {
    @Published var tab: SettingsTab = .status
}

struct CalendarRow: Identifiable {
    let id: String
    let title: String
    let source: String
}

final class SettingsModel: ObservableObject {
    static let diskWarnGB = 0.5
    static let diskAbortGB = 0.2
    static let levelFloorDB = -60.0

    @Published var watcherRunning = false
    @Published var watcherPid: pid_t?
    @Published var launchError: String?
    @Published var status: RecorderStatus?
    @Published var levels: RecorderLevels?
    @Published var binaryLine: String?
    @Published var screen: PermissionStatus = .undetermined
    @Published var mic: PermissionStatus = .undetermined
    @Published var calendar: PermissionStatus = .undetermined
    @Published var diskFreeGB: Double?
    @Published var recordingDir: URL = WatcherManager.shared.recordingDirectory()
    @Published var launchAtLogin = false
    @Published var devices: [(uid: String, name: String)] = []
    @Published var micUID = ""
    @Published var recordMic = true
    @Published var speakers: String?
    @Published var calendars: [CalendarRow] = []
    @Published var trackedIds: [String]?
    @Published var update: UpdateCheckState = .idle

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    var isRecording: Bool { status?.state == "recording" }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .watcherStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard self?.timer != nil else { return }
            self?.refresh()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func startPolling() {
        refresh()
        loadDevices()
        runBinaryCheck()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let watcher = WatcherManager.shared
        watcherRunning = watcher.isRunning
        watcherPid = watcherRunning ? watcher.currentWatcherPid() : nil
        launchError = watcherRunning ? nil : watcher.lastLaunchError?.userDescription
        status = RecorderStatus.load()
        levels = isRecording ? RecorderLevels.load() : nil
        screen = PermissionChecker.screenRecording()
        mic = PermissionChecker.microphone()
        calendar = PermissionChecker.calendar()
        recordingDir = watcher.recordingDirectory()
        diskFreeGB = Self.freeGB(at: recordingDir)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        micUID = watcher.envValue("AUDIO_INPUT_DEVICE_UID") ?? ""
        recordMic = watcher.envValue("RECORD_MIC") != "0"
        speakers = Self.defaultOutputName()
        trackedIds = CalendarEventBridge.shared.trackedCalendarIds
        calendars = CalendarEventBridge.shared.allCalendars().map {
            CalendarRow(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "")
        }
    }

    private func loadDevices() {
        DispatchQueue.global(qos: .utility).async {
            let list = WatcherManager.shared.listInputDevices()
            DispatchQueue.main.async { self.devices = list }
        }
    }

    private func runBinaryCheck() {
        guard let bin = Bundle.main.url(forResource: "recorder", withExtension: nil) else {
            binaryLine = nil
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = bin
            p.arguments = ["--check"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var line = "Could not run"
            if (try? p.run()) != nil {
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let first = out.split(separator: "\n").first.map(String.init) ?? ""
                if p.terminationStatus == 0 {
                    line = first.isEmpty ? "OK" : first
                } else {
                    line = first.isEmpty ? "Failed (exit \(p.terminationStatus))" : first
                }
            }
            DispatchQueue.main.async { self.binaryLine = line }
        }
    }

    func isTracked(_ id: String) -> Bool {
        trackedIds?.contains(id) ?? true
    }

    func setTracked(_ id: String, _ on: Bool) {
        var ids = Set(trackedIds ?? calendars.map(\.id))
        if on { ids.insert(id) } else { ids.remove(id) }
        let all = Set(calendars.map(\.id))
        CalendarEventBridge.shared.setTrackedCalendarIds(all.isSubset(of: ids) ? nil : Array(ids))
        trackedIds = CalendarEventBridge.shared.trackedCalendarIds
    }

    func selectAllCalendars() {
        CalendarEventBridge.shared.setTrackedCalendarIds(nil)
        trackedIds = nil
    }

    func setEnv(_ key: String, _ value: String) {
        WatcherManager.shared.setEnvValue(key, value)
        refresh()
    }

    func setLaunchAtLogin(_ on: Bool) {
        let svc = SMAppService.mainApp
        do {
            if on { try svc.register() } else { try svc.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = svc.status == .notFound
                ? "Move TeamRecorderBar.app to /Applications/ first, then try again."
                : "Could not update Login Item:\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        launchAtLogin = svc.status == .enabled
    }

    func chooseRecordingsFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = recordingDir
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WatcherManager.shared.setRecordingDir(url)
        refresh()
    }

    func toggleWatcher() {
        if watcherRunning { WatcherManager.shared.stop() } else { WatcherManager.shared.start() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func recover() {
        let alert = NSAlert()
        alert.messageText = "Recover Recorder?"
        alert.informativeText = "This will stop any stuck recording process and clear stale menu-bar status. The current file may be incomplete."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WatcherManager.shared.recoverStaleRecordingState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func showLastRecording() {
        guard let path = status?.lastRecordingPath else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func checkForUpdates() {
        update = .checking
        let current = appVersion
        Task { @MainActor in
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/cjarit/team-recorder/releases/latest")!)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let urlString = json["html_url"] as? String,
                  let url = URL(string: urlString),
                  let latest = Self.versionParts(tag),
                  let running = Self.versionParts(current)
            else {
                self.update = .failed
                return
            }
            self.update = Self.isNewer(latest, than: running) ? .available(tag: tag, url: url) : .upToDate
        }
    }

    static func versionParts(_ raw: String) -> [Int]? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") { s.removeFirst() }
        s = s.components(separatedBy: "-").first ?? s
        let parts = s.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func freeGB(at dir: URL) -> Double? {
        var url = dir
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let free = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return free.doubleValue / 1_073_741_824
    }

    static func defaultOutputName() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        addr.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let model = SettingsModel()
    private let navigator = SettingsNavigator()

    private init() {
        UserDefaults.standard.register(defaults: ["notifyOnSave": true])
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Team Recorder"
        win.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: SettingsRootView(model: model, navigator: navigator))
        host.sizingOptions = []
        win.contentViewController = host
        win.setContentSize(NSSize(width: 520, height: 480))
        super.init(window: win)
        win.delegate = self
        if !win.setFrameAutosaveName("TeamRecorderSettingsWindow") { win.center() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(tab: SettingsTab = .status) {
        guard let win = window else { return }
        navigator.tab = tab
        if !win.isVisible { model.startPolling() }
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigator: SettingsNavigator

    var body: some View {
        TabView(selection: $navigator.tab) {
            StatusTab(model: model)
                .tabItem { Label("Status", systemImage: "waveform") }
                .tag(SettingsTab.status)
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            CalendarsTab(model: model, navigator: navigator)
                .tabItem { Label("Calendars", systemImage: "calendar") }
                .tag(SettingsTab.calendars)
            PermissionsTab(model: model)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

private func statusColor(_ s: PermissionStatus) -> Color {
    switch s {
    case .granted: return .green
    case .denied: return .red
    case .undetermined: return .orange
    case .skipped: return .secondary
    }
}

private func statusText(_ s: PermissionStatus) -> String {
    switch s {
    case .granted: return "Granted"
    case .denied: return "Not granted"
    case .undetermined: return "Not asked yet"
    case .skipped: return "Skipped"
    }
}

private struct StatusDot: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

private struct StatusTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Recorder") {
                LabeledContent("Watcher") { watcherText }
                LabeledContent("State") { Text(stateText).multilineTextAlignment(.trailing) }
                if let err = model.status?.lastError, !err.isEmpty {
                    LabeledContent("Last error") {
                        Text(err).foregroundStyle(.red).multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Recorder binary") { binaryText }
                LabeledContent("Disk free") { diskText }
                LabeledContent("Version") { Text(model.appVersion) }
            }
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    StatusDot(text: statusText(model.screen), color: statusColor(model.screen))
                }
                LabeledContent("Microphone") {
                    StatusDot(text: statusText(model.mic), color: statusColor(model.mic))
                }
                LabeledContent("Calendar") {
                    StatusDot(text: statusText(model.calendar), color: statusColor(model.calendar))
                }
            }
            Section("Last recording") {
                LabeledContent("Name") { Text(lastName).multilineTextAlignment(.trailing) }
                LabeledContent("Saved") { Text(lastSaved) }
                Button("Show in Finder") { model.showLastRecording() }
                    .disabled(model.status?.lastRecordingPath == nil)
            }
            if model.isRecording {
                Section("Live levels") {
                    levelRow("System audio", db: model.levels?.sysRms)
                    levelRow("Microphone", db: model.levels?.micRms, off: model.levels?.micEnabled == false)
                }
            }
            Section("Actions") {
                Button(model.watcherRunning ? "Pause Watching" : "Start Watcher") { model.toggleWatcher() }
                Button("Recover Recorder…") { model.recover() }
                Button("Open Setup Guide…") { SetupWindowController.shared.show() }
            }
            Section("Updates") {
                HStack {
                    Button("Check for Updates") { model.checkForUpdates() }
                        .disabled(model.update == .checking)
                    Spacer()
                    updateText
                }
            }
        }
        .formStyle(.grouped)
    }

    private var watcherText: some View {
        Group {
            if model.watcherRunning {
                StatusDot(text: model.watcherPid.map { "Running (pid \($0))" } ?? "Running", color: .green)
            } else if let err = model.launchError {
                Text(err).foregroundStyle(.red).multilineTextAlignment(.trailing)
            } else {
                StatusDot(text: "Not running", color: .secondary)
            }
        }
    }

    private var stateText: String {
        guard let s = model.status else { return "No status yet" }
        if let name = s.meetingName, !name.isEmpty { return "\(s.state) — \(name)" }
        return s.state
    }

    private var binaryText: some View {
        Group {
            if Bundle.main.url(forResource: "recorder", withExtension: nil) == nil {
                StatusDot(text: "Missing from app", color: .red)
            } else if let line = model.binaryLine {
                Text(line).multilineTextAlignment(.trailing)
            } else {
                Text("Checking…").foregroundStyle(.secondary)
            }
        }
    }

    private var diskText: some View {
        Group {
            if let gb = model.diskFreeGB {
                let color: Color = gb < SettingsModel.diskAbortGB ? .red : (gb < SettingsModel.diskWarnGB ? .orange : .green)
                StatusDot(text: String(format: "%.1f GB", gb), color: color)
            } else {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
    }

    private var lastName: String {
        model.status?.lastRecordingName ?? "None yet"
    }

    private var lastSaved: String {
        guard let raw = model.status?.lastSavedAt else { return "—" }
        guard let date = DateFormatter.teamRecorderStatus.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func levelRow(_ title: String, db: Double?, off: Bool = false) -> some View {
        LabeledContent(title) {
            if off {
                Text("Off").foregroundStyle(.secondary)
            } else if let db, let levels = model.levels, !levels.isStale {
                HStack {
                    ProgressView(value: min(max((db - SettingsModel.levelFloorDB) / -SettingsModel.levelFloorDB, 0), 1))
                        .frame(width: 120)
                    Text(String(format: "%.0f dB", db)).monospacedDigit()
                }
            } else {
                Text("No data").foregroundStyle(.secondary)
            }
        }
    }

    private var updateText: some View {
        Group {
            switch model.update {
            case .idle:
                EmptyView()
            case .checking:
                Text("Checking…").foregroundStyle(.secondary)
            case .upToDate:
                Text("Up to date").foregroundStyle(.secondary)
            case .available(let tag, let url):
                HStack {
                    Text("\(tag) available")
                    Button("Download") { NSWorkspace.shared.open(url) }
                }
            case .failed:
                Text("Couldn't check — try later").foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @AppStorage("notifyOnSave") private var notifyOnSave = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Recordings folder") {
                    HStack {
                        Text(model.recordingDir.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { model.chooseRecordingsFolder() }
                            .disabled(model.isRecording)
                    }
                }
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                Toggle("Notify when a recording is saved", isOn: $notifyOnSave)
            } footer: {
                if model.isRecording { Text("Change after the current recording") }
            }
            Section {
                Picker("Microphone", selection: Binding(
                    get: { model.micUID },
                    set: { model.setEnv("AUDIO_INPUT_DEVICE_UID", $0) })) {
                    Text("Auto (system default)").tag("")
                    ForEach(model.devices, id: \.uid) { Text($0.name).tag($0.uid) }
                    if !model.micUID.isEmpty, !model.devices.contains(where: { $0.uid == model.micUID }) {
                        Text("Unavailable device").tag(model.micUID)
                    }
                }
                .disabled(model.isRecording)
                Toggle("Record my voice", isOn: Binding(
                    get: { model.recordMic },
                    set: { model.setEnv("RECORD_MIC", $0 ? "1" : "0") }))
                    .disabled(model.isRecording)
                if let speakers = model.speakers {
                    LabeledContent("Speakers") { Text(speakers).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Audio")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Changing a setting here restarts the watcher.")
                    if model.isRecording { Text("Change after the current recording") }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarsTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigator: SettingsNavigator

    var body: some View {
        Form {
            if model.calendar == .granted {
                Section {
                    ForEach(model.calendars) { cal in
                        Toggle(isOn: Binding(
                            get: { model.isTracked(cal.id) },
                            set: { model.setTracked(cal.id, $0) })) {
                            VStack(alignment: .leading) {
                                Text(cal.title)
                                if !cal.source.isEmpty {
                                    Text(cal.source).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Calendars used to name recordings")
                }
                Section {
                    Button("Select All") { model.selectAllCalendars() }
                    Button("Refresh events") { CalendarEventBridge.shared.writeEventsIfAuthorized() }
                }
            } else {
                Section {
                    Text(model.calendar == .skipped
                         ? "Calendar access is skipped, so recordings are named \"Teams Meeting\"."
                         : "Calendar access is needed to name recordings after your meetings.")
                    Button("Go to Permissions") { navigator.tab = .permissions }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                row("Screen Recording", model.screen, pane: "Privacy_ScreenCapture") {
                    if model.screen != .granted {
                        Button("Request Access") {
                            PermissionChecker.requestScreenRecording()
                            model.refresh()
                        }
                    }
                }
            } footer: {
                Text("Changing this requires relaunching Team Recorder.")
            }
            Section {
                row("Microphone", model.mic, pane: "Privacy_Microphone") {
                    if model.mic == .undetermined {
                        Button("Allow…") { PermissionChecker.requestMicrophone { _ in model.refresh() } }
                    }
                }
            }
            Section {
                row("Calendar", model.calendar, pane: "Privacy_Calendars") {
                    if model.calendar == .undetermined {
                        Button("Allow…") { PermissionChecker.requestCalendar { _ in model.refresh() } }
                    }
                }
                if model.calendar != .granted {
                    Toggle("Skip — my organisation blocks calendar", isOn: Binding(
                        get: { PermissionChecker.calendarSkipped },
                        set: {
                            PermissionChecker.calendarSkipped = $0
                            model.refresh()
                        }))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row<Extra: View>(_ title: String, _ status: PermissionStatus, pane: String,
                                  @ViewBuilder extra: () -> Extra) -> some View {
        LabeledContent(title) {
            HStack {
                StatusDot(text: statusText(status), color: statusColor(status))
                extra()
                Button("Open System Settings…") { PermissionChecker.openPane(pane) }
            }
        }
    }
}
