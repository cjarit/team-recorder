import SwiftUI

/// Everything the popover shows, built by StatusBarController from status.json + live checks.
/// Plain data only — the view never reads WatcherManager or PermissionChecker itself.
struct PopoverSnapshot {
    enum Phase { case recording, stopping, waiting, paused, error, stale, launchFailed }

    var phase: Phase
    var meetingName: String?
    var startedAt: Date?
    var errorText: String?
    var watcherConfigured: Bool
    var lastRecordingName: String?
    var lastSavedTime: String?
    var lastFallbackReason: String?
    var canOpenLastRecording: Bool
    var screenRecording: PermissionStatus
    var microphone: PermissionStatus
    var calendar: PermissionStatus
}

enum PermissionPane: String {
    case screenRecording = "Privacy_ScreenCapture"
    case microphone      = "Privacy_Microphone"
    case calendar        = "Privacy_Calendars"
}

struct PopoverActions {
    var startRecording: () -> Void
    var stopRecording: () -> Void
    var toggleWatcher: () -> Void
    var recover: () -> Void
    var showLaunchError: () -> Void
    var openLastRecording: () -> Void
    var openFolder: () -> Void
    var openPermission: (PermissionPane) -> Void
    var showFullMenu: () -> Void
    var quit: () -> Void
}

struct PopoverView: View {
    let snapshot: PopoverSnapshot
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusCard
            Divider().padding(.vertical, 4)
            sectionLabel("Last Recording")
            lastRecordingRow
            Divider().padding(.vertical, 4)
            sectionLabel("Permissions")
            permissionRow("Screen Recording", snapshot.screenRecording, .screenRecording)
            permissionRow("Microphone", snapshot.microphone, .microphone)
            permissionRow("Calendar", snapshot.calendar, .calendar)
            Divider().padding(.vertical, 4)
            MenuRow(action: actions.openFolder) { Text("Open Recordings Folder") }
            MenuRow(action: actions.showFullMenu) { Text("More…") }
            MenuRow(action: actions.quit) {
                Text("Quit Team Recorder")
                Spacer()
                Text("⌘Q").foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .frame(width: 300)
        .font(.system(size: 13))
    }

    @ViewBuilder
    private var statusCard: some View {
        switch snapshot.phase {
        case .recording:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusDot(color: .red)
                    Text("Recording").fontWeight(.semibold)
                    Spacer()
                    if let started = snapshot.startedAt {
                        Text(started, style: .timer)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Text(snapshot.meetingName ?? "Teams Meeting")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Button(action: actions.stopRecording) {
                    Text("Stop Recording").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(8)

        case .stopping:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Saving Recording…").fontWeight(.semibold)
            }
            .padding(8)

        case .waiting:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusDot(color: .green)
                    Text("Ready").fontWeight(.semibold)
                }
                Text("Recording starts when you join a Teams meeting.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Recording Now", action: actions.startRecording)
                    .padding(.top, 2)
            }
            .padding(8)

        case .paused:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusDot(color: .gray)
                    Text("Paused").fontWeight(.semibold)
                }
                Text("Meetings won't be recorded.")
                    .foregroundStyle(.secondary)
                Button(action: actions.toggleWatcher) {
                    Text(snapshot.watcherConfigured ? "Start Watching" : "Watcher Not Configured")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!snapshot.watcherConfigured)
                .padding(.top, 4)
            }
            .padding(8)

        case .error:
            WarningCard(
                title: "Recorder Error",
                message: snapshot.errorText ?? "Something went wrong with the recorder.",
                buttonTitle: "Recover Recorder…",
                action: actions.recover
            )

        case .stale:
            WarningCard(
                title: "Recorder Stopped Responding",
                message: "The status is out of date. Recover to catch the next meeting — the current file may be incomplete.",
                buttonTitle: "Recover Recorder…",
                action: actions.recover
            )

        case .launchFailed:
            WarningCard(
                title: "Can't Start Watcher",
                message: "Meetings won't be recorded until this is fixed.",
                buttonTitle: "Show Details…",
                action: actions.showLaunchError
            )
        }
    }

    @ViewBuilder
    private var lastRecordingRow: some View {
        if let name = snapshot.lastRecordingName {
            MenuRow(action: actions.openLastRecording) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).lineLimit(1).truncationMode(.middle)
                    if let reason = snapshot.lastFallbackReason, !reason.isEmpty {
                        Text("Named “Teams Meeting” — \(reason)")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if let time = snapshot.lastSavedTime {
                    Text(time).foregroundStyle(.secondary)
                }
            }
            .disabled(!snapshot.canOpenLastRecording)
        } else {
            Text("No recordings yet")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func permissionRow(_ title: String, _ status: PermissionStatus, _ pane: PermissionPane) -> some View {
        MenuRow(action: { actions.openPermission(pane) }) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? Color.green : Color.orange)
                .frame(width: 16)
            Text(title)
            Spacer()
            if status != .granted {
                Text("Allow…").foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

private struct WarningCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(2)
    }
}

/// Full-width row that highlights on hover, like a native menu item.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
