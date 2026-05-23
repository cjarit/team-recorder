import AppKit
import CoreGraphics

/// Step-by-step permission onboarding window. Singleton — call show() to present.
/// Floats above other windows. Idempotent: calling show() again brings it to front.
final class SetupWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SetupWindowController()

    private var currentStep = 0

    // UI refs — set in buildUI(), safe to use after init
    private var stepLabel:      NSTextField!
    private var iconLabel:      NSTextField!
    private var titleLabel:     NSTextField!
    private var descLabel:      NSTextField!
    private var statusDot:      NSTextField!
    private var statusText:     NSTextField!
    private var grantButton:    NSButton!
    private var settingsButton: NSButton!
    private var checkButton:    NSButton!
    private var continueButton: NSButton!

    // MARK: — Step data

    private struct StepInfo {
        let icon: String; let title: String; let desc: String; let pane: String
    }

    private let steps: [StepInfo] = [
        StepInfo(icon: "🖥",
                 title: "Screen Recording",
                 desc:  "Required to capture system audio from Microsoft Teams. "
                      + "Without this, no audio will be recorded.",
                 pane:  "Privacy_ScreenCapture"),
        StepInfo(icon: "🎙",
                 title: "Microphone",
                 desc:  "Required to record your own voice during meetings. "
                      + "System audio is still captured if this is skipped.",
                 pane:  "Privacy_Microphone"),
        StepInfo(icon: "📅",
                 title: "Calendar Access",
                 desc:  "Used to name recordings after the meeting title from Apple Calendar. "
                      + "Full Access is required (not Write Only). "
                      + "Recordings are saved as \"Teams Meeting\" if this is skipped.",
                 pane:  "Privacy_Calendars"),
    ]

    // MARK: — Init

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        win.title  = "Team Recorder — Setup"
        win.level  = .floating
        win.isMovableByWindowBackground = true
        super.init(window: win)
        win.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("use SetupWindowController.shared") }

    // MARK: — NSWindowDelegate

    /// ถ้าผู้ใช้กด close button โดยไม่ได้กด Finish — ถือว่า Skip
    /// ตั้งค่า setupCompleted แล้วเริ่ม watcher เพื่อไม่ให้ค้างอยู่โดยไม่ทำงาน
    func windowWillClose(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            UserDefaults.standard.set(true, forKey: "setupCompleted")
            WatcherManager.shared.autoStartIfNeeded()
        }
    }

    // MARK: — Public API

    /// Present the setup window. Brings to front if already visible.
    func show() {
        guard let win = window else { return }
        if win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        currentStep = 0
        win.center()
        refreshStep()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: — UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let pad: CGFloat = 24

        // Labels
        stepLabel   = makeLabel("",   size: 11, color: .secondaryLabelColor)
        iconLabel   = makeLabel("",   size: 28)
        titleLabel  = makeLabel("",   size: 15, bold: true)
        descLabel   = makeLabel("",   size: 13, color: .secondaryLabelColor)
        descLabel.maximumNumberOfLines = 4
        descLabel.lineBreakMode        = .byWordWrapping

        statusDot   = makeLabel("○",  size: 13)
        statusText  = makeLabel("",   size: 13, color: .secondaryLabelColor)

        // Buttons
        grantButton    = makeButton("Grant Access",        action: #selector(grantAccess))
        settingsButton = makeButton("Open System Settings", action: #selector(openSettings))
        checkButton    = makeButton("Check Again",          action: #selector(checkAgain))
        continueButton = makeButton("Continue →",           action: #selector(continueTapped))
        continueButton.keyEquivalent = "\r"

        // Row stacks
        let headerRow = hstack([iconLabel, titleLabel], spacing: 8)
        let statusRow = hstack([statusDot, statusText], spacing: 6)
        let actionRow = hstack([grantButton, settingsButton], spacing: 8)

        // Separator
        let sep = NSBox(); sep.boxType = .separator

        // Continue right-aligned inside a container view
        let continueContainer = NSView()
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueContainer.addSubview(continueButton)
        NSLayoutConstraint.activate([
            continueButton.trailingAnchor.constraint(equalTo: continueContainer.trailingAnchor),
            continueButton.topAnchor.constraint(equalTo: continueContainer.topAnchor),
            continueButton.bottomAnchor.constraint(equalTo: continueContainer.bottomAnchor),
        ])

        // Main vertical stack
        let mainStack = vstack([
            stepLabel,
            headerRow,
            descLabel,
            statusRow,
            actionRow,
            checkButton,
            sep,
            continueContainer,
        ], spacing: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: content.topAnchor,       constant:  pad),
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant:  pad),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            mainStack.bottomAnchor.constraint(equalTo: content.bottomAnchor,  constant: -pad),
        ])

        // Stretch full-width views to fill the stack (leading-aligned by default)
        for v in [descLabel, sep, continueContainer] as [NSView] {
            v.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
        }
    }

    // MARK: — Step rendering

    private func refreshStep() {
        let info   = steps[currentStep]
        let isLast = currentStep == steps.count - 1

        stepLabel.stringValue  = "Step \(currentStep + 1) of \(steps.count)"
        iconLabel.stringValue  = info.icon
        titleLabel.stringValue = info.title
        descLabel.stringValue  = info.desc
        continueButton.title   = isLast ? "Finish" : "Continue →"

        refreshStatus()
    }

    private func refreshStatus() {
        let status = currentPermissionStatus()

        // Status indicator
        switch status {
        case .granted:
            statusDot.textColor    = .systemGreen
            statusDot.stringValue  = "●"
            statusText.stringValue = "Granted"
        case .denied:
            statusDot.textColor    = .systemRed
            statusDot.stringValue  = "●"
            statusText.stringValue = "Not granted — open Settings to allow access"
        case .undetermined:
            statusDot.textColor    = .secondaryLabelColor
            statusDot.stringValue  = "○"
            statusText.stringValue = "Not yet requested"
        }

        // Screen Recording step: "Request Access" triggers the CGRequest dialog
        // Other steps: "Grant Access" only while undetermined; hide once determined
        if currentStep == 0 {
            grantButton.title    = "Request Access"
            grantButton.isHidden = (status == .granted)
        } else {
            grantButton.title    = "Grant Access"
            grantButton.isHidden = (status != .undetermined)
        }

        // "Open System Settings" — hide only when already granted
        settingsButton.isHidden = (status == .granted)
    }

    private func currentPermissionStatus() -> PermissionStatus {
        switch currentStep {
        case 0:  return PermissionChecker.screenRecording()
        case 1:  return PermissionChecker.microphone()
        default: return PermissionChecker.calendar()
        }
    }

    // MARK: — Actions

    @objc private func grantAccess() {
        switch currentStep {
        case 0:
            // CGRequestScreenCaptureAccess is async — re-check after settle time
            // ถ้า macOS แสดง dialog ให้ผู้ใช้อนุญาต ต้องรอสักครู่ก่อน check ผล
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.refreshStatus()
            }
        case 1:
            PermissionChecker.requestMicrophone { [weak self] _ in
                self?.refreshStatus()
            }
        default:
            PermissionChecker.requestCalendar { [weak self] _ in
                self?.refreshStatus()
            }
        }
    }

    @objc private func openSettings() {
        let pane = steps[currentStep].pane
        let url  = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    @objc private func checkAgain() {
        refreshStatus()
    }

    @objc private func continueTapped() {
        if currentStep < steps.count - 1 {
            currentStep += 1
            refreshStep()
        } else {
            // ปิดหน้าต่าง Setup แล้วบันทึกว่าทำเสร็จแล้ว จากนั้นเริ่ม watcher
            UserDefaults.standard.set(true, forKey: "setupCompleted")
            window?.close()
            WatcherManager.shared.autoStartIfNeeded()
        }
    }

    // MARK: — Factory helpers

    private func makeLabel(_ text: String, size: CGFloat,
                            bold: Bool = false,
                            color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font      = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        f.textColor = color
        return f
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func hstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing     = spacing
        s.alignment   = .centerY
        return s
    }

    private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.spacing     = spacing
        s.alignment   = .leading
        return s
    }
}
