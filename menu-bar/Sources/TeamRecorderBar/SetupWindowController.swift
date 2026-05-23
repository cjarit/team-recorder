import AppKit
import CoreGraphics

/// Step-by-step permission onboarding window. Singleton — call show() to present.
/// Floats above other windows. Idempotent: calling show() again brings it to front.
final class SetupWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SetupWindowController()

    private var currentStep = 0
    /// ป้องกัน recursion: windowWillClose → completeSetupAndStartWatcher → close → windowWillClose
    private var completingSetup = false

    // UI refs — set in buildUI(), safe to use after init
    private var stepLabel:        NSTextField!
    private var iconLabel:        NSTextField!
    private var titleLabel:       NSTextField!
    private var descLabel:        NSTextField!
    private var instructionsBox:  NSView!
    private var instructionsLabel: NSTextField!
    private var statusDot:        NSTextField!
    private var statusText:       NSTextField!
    private var primaryButton:    NSButton!   // single action; title/action change by step+state
    private var relaunchButton:   NSButton!   // step 0 only: "Relaunch App"
    private var checkLink:        NSButton!   // recessed "↺ Check Again"
    private var skipButton:       NSButton!   // bottom-left "Skip for Now"
    private var continueButton:   NSButton!   // bottom-right "Continue →" / "Finish"

    // MARK: — Step data

    private struct StepInfo {
        let icon:         String
        let title:        String
        let desc:         String
        let pane:         String
        let instructions: String   // shown in tinted instructions box
        let grantsInApp:  Bool     // true = mic/calendar can show in-app dialog
    }

    private let steps: [StepInfo] = [
        StepInfo(
            icon: "🖥",
            title: "Screen Recording",
            desc: "Required to capture system audio from Microsoft Teams.",
            pane: "Privacy_ScreenCapture",
            instructions: "1. Click \"Add Team Recorder to Screen Recording\" below\n"
                        + "2. macOS will open System Settings — turn on the toggle\n"
                        + "3. Come back here and click \"Relaunch App\"\n"
                        + "   (macOS requires a relaunch after enabling this permission)",
            grantsInApp: false
        ),
        StepInfo(
            icon: "🎙",
            title: "Microphone",
            desc: "Required to record your own voice during meetings.",
            pane: "Privacy_Microphone",
            instructions: "Click \"Grant Access\" — macOS will show a popup.\n"
                        + "Click Allow in the popup.",
            grantsInApp: true
        ),
        StepInfo(
            icon: "📅",
            title: "Calendar Access",
            desc: "Used to name recordings after the meeting title.",
            pane: "Privacy_Calendars",
            instructions: "Click \"Grant Access\" — choose Full Access in the popup.\n"
                        + "(Write Only is not enough — recordings will be named \"Teams Meeting\")",
            grantsInApp: true
        ),
    ]

    // MARK: — Init

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
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

    /// Fallback for the red-close-button path — starts watcher so the app isn't stuck idle.
    /// `completingSetup` guard prevents re-entry when we call close() ourselves.
    func windowWillClose(_ notification: Notification) {
        // คืน activation policy กลับเป็น .accessory (ซ่อนจาก Dock) ก่อนเสมอ
        NSApp.setActivationPolicy(.accessory)
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            completeSetupAndStartWatcher(closeWindow: false)   // already closing
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
        // ชั่วคราว switch เป็น .regular เพื่อให้ window ขึ้น front ได้
        // (.accessory ไม่สามารถ steal focus จาก app อื่นได้)
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: — Exit helper (single path for all completion/skip routes)

    /// ทุก path ที่ออกจาก Setup ใช้ helper นี้เท่านั้น — ป้องกัน recursion และ duplicate watcher start
    private func completeSetupAndStartWatcher(closeWindow: Bool = true) {
        guard !completingSetup else { return }
        completingSetup = true
        UserDefaults.standard.set(true, forKey: "setupCompleted")
        WatcherManager.shared.autoStartIfNeeded()
        if closeWindow {
            window?.close()   // triggers windowWillClose — guard prevents re-entry
        }
        completingSetup = false
    }

    // MARK: — UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let pad: CGFloat = 24

        // Header labels
        stepLabel  = makeLabel("",  size: 11, color: .secondaryLabelColor)
        iconLabel  = makeLabel("",  size: 28)
        titleLabel = makeLabel("",  size: 15, bold: true)
        descLabel  = makeLabel("",  size: 13, color: .secondaryLabelColor)
        descLabel.maximumNumberOfLines = 3
        descLabel.lineBreakMode        = .byWordWrapping

        // Instructions box — tinted background for visual hierarchy
        instructionsBox = NSView()
        instructionsBox.wantsLayer                    = true
        instructionsBox.layer?.backgroundColor        = NSColor.controlBackgroundColor.cgColor
        instructionsBox.layer?.cornerRadius           = 8

        instructionsLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
        instructionsLabel.maximumNumberOfLines        = 6
        instructionsLabel.lineBreakMode               = .byWordWrapping
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionsBox.addSubview(instructionsLabel)
        NSLayoutConstraint.activate([
            instructionsLabel.topAnchor.constraint(equalTo: instructionsBox.topAnchor,      constant: 10),
            instructionsLabel.leadingAnchor.constraint(equalTo: instructionsBox.leadingAnchor, constant: 12),
            instructionsLabel.trailingAnchor.constraint(equalTo: instructionsBox.trailingAnchor, constant: -12),
            instructionsLabel.bottomAnchor.constraint(equalTo: instructionsBox.bottomAnchor, constant: -10),
        ])

        // Status row
        statusDot  = makeLabel("○", size: 13)
        statusText = makeLabel("",  size: 13, color: .secondaryLabelColor)

        // Action buttons
        primaryButton  = makeButton("", action: #selector(primaryTapped))
        relaunchButton = makeButton("Relaunch App", action: #selector(relaunchApp))
        checkLink      = NSButton(title: "↺ Check Again", target: self, action: #selector(checkAgain))
        checkLink.bezelStyle = .recessed
        checkLink.isBordered = true

        // Bottom row
        skipButton     = makeButton("Skip for Now", action: #selector(skipTapped))
        continueButton = makeButton("Continue →",   action: #selector(continueTapped))
        continueButton.keyEquivalent = "\r"

        // Layout groups
        let headerRow  = hstack([iconLabel, titleLabel], spacing: 8)
        let statusRow  = hstack([statusDot, statusText], spacing: 6)
        let actionRow  = hstack([primaryButton, relaunchButton], spacing: 8)

        // Separator
        let sep = NSBox(); sep.boxType = .separator

        // Bottom bar: skip left, continue right
        let skipContainer = NSView()
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipContainer.addSubview(skipButton)
        NSLayoutConstraint.activate([
            skipButton.leadingAnchor.constraint(equalTo: skipContainer.leadingAnchor),
            skipButton.topAnchor.constraint(equalTo: skipContainer.topAnchor),
            skipButton.bottomAnchor.constraint(equalTo: skipContainer.bottomAnchor),
        ])

        let continueContainer = NSView()
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueContainer.addSubview(continueButton)
        NSLayoutConstraint.activate([
            continueButton.trailingAnchor.constraint(equalTo: continueContainer.trailingAnchor),
            continueButton.topAnchor.constraint(equalTo: continueContainer.topAnchor),
            continueButton.bottomAnchor.constraint(equalTo: continueContainer.bottomAnchor),
        ])

        let bottomRow = hstack([skipContainer, continueContainer], spacing: 0)
        bottomRow.distribution = .fillEqually

        // Main vertical stack
        let mainStack = vstack([
            stepLabel,
            headerRow,
            descLabel,
            instructionsBox,
            statusRow,
            actionRow,
            checkLink,
            sep,
            bottomRow,
        ], spacing: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: content.topAnchor,         constant:  pad),
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor,  constant:  pad),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            mainStack.bottomAnchor.constraint(equalTo: content.bottomAnchor,   constant: -pad),
        ])

        // Stretch full-width views
        for v in [descLabel, instructionsBox, sep, bottomRow] as [NSView] {
            v.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
        }
    }

    // MARK: — Step rendering

    private func refreshStep() {
        let info   = steps[currentStep]
        let isLast = currentStep == steps.count - 1

        stepLabel.stringValue         = "Step \(currentStep + 1) of \(steps.count)"
        iconLabel.stringValue         = info.icon
        titleLabel.stringValue        = info.title
        descLabel.stringValue         = info.desc
        instructionsLabel.stringValue = info.instructions
        continueButton.title          = isLast ? "Finish" : "Continue →"

        // relaunchButton — step 0 only
        relaunchButton.isHidden = (currentStep != 0)

        refreshStatus()
    }

    private func refreshStatus() {
        let info   = steps[currentStep]
        let status = currentPermissionStatus()

        // Status dot
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

        // primaryButton — single action, title/target changes by step+state
        if status == .granted {
            primaryButton.isHidden = true
        } else {
            primaryButton.isHidden = false
            if currentStep == 0 {
                // Step 0: CTA that explains what happens — requestScreenRecording() + open Settings
                primaryButton.title = "Add Team Recorder to Screen Recording"
            } else if info.grantsInApp && status == .undetermined {
                // Mic/Calendar undetermined: show in-app dialog
                primaryButton.title = "Grant Access"
            } else {
                // Mic/Calendar denied
                primaryButton.title = "Open System Settings"
            }
        }

        // relaunchButton — step 0 only, hidden once granted
        if currentStep == 0 {
            relaunchButton.isHidden = (status == .granted)
        }
    }

    private func currentPermissionStatus() -> PermissionStatus {
        switch currentStep {
        case 0:  return PermissionChecker.screenRecording()
        case 1:  return PermissionChecker.microphone()
        default: return PermissionChecker.calendar()
        }
    }

    // MARK: — Actions

    @objc private func primaryTapped() {
        let info   = steps[currentStep]
        let status = currentPermissionStatus()

        if currentStep == 0 {
            // ต้อง call requestScreenRecording() ก่อน open Settings —
            // ถ้าไม่ call macOS จะไม่เพิ่ม app เข้า Screen Recording list เลย
            PermissionChecker.requestScreenRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openSettings()
            }
        } else if info.grantsInApp && status == .undetermined {
            grantAccess()
        } else {
            openSettings()
        }
    }

    private func grantAccess() {
        switch currentStep {
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

    private func openSettings() {
        let pane = steps[currentStep].pane
        let url  = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    @objc private func relaunchApp() {
        // เปิด instance ใหม่หลังจากอันนี้ terminate แล้ว — ส่ง path เป็น env var แยก
        // ไม่ใช้ string interpolation โดยตรงใน shell command เพื่อ handle paths ที่มีช่องว่าง
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // sleep ก่อนแล้วค่อย open — ให้ process นี้ terminate เสร็จก่อน
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$APP_PATH\""]
        task.environment = ProcessInfo.processInfo.environment.merging(["APP_PATH": path]) { $1 }
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            // ถ้า spawn ล้มเหลว — แจ้ง user แทนการ terminate โดยเงียบ
            let alert = NSAlert()
            alert.messageText     = "Could not relaunch automatically"
            alert.informativeText = "Please quit Team Recorder and reopen it manually.\n\n(\(error.localizedDescription))"
            alert.alertStyle      = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func checkAgain() {
        refreshStatus()
    }

    @objc private func skipTapped() {
        completeSetupAndStartWatcher(closeWindow: true)
    }

    @objc private func continueTapped() {
        if currentStep < steps.count - 1 {
            currentStep += 1
            refreshStep()
        } else {
            // กด Finish — ออกจาก setup, เริ่ม watcher
            completeSetupAndStartWatcher(closeWindow: true)
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
