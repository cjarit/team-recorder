import AppKit

// SPM executable entry point — cannot use @main with top-level code.
// AppDelegate wires everything up; StatusBarController owns the status item.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // hide Dock icon before delegate runs
let delegate = AppDelegate()
app.delegate = delegate
app.run()
