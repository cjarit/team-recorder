# Team Recorder — Setup Guide

> For new users. Step-by-step installation and first-run setup.

---

## Path A — Download from GitHub Releases (Recommended)

> No Terminal, no Homebrew required.

### Step 1 — Download and install

1. Go to [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
2. Download **TeamRecorderBar-v1.2.0.zip**
3. Double-click the zip to extract it
4. Drag **TeamRecorderBar.app** to your **Applications** folder — if you already have an older version installed, macOS will ask to replace it; confirm

### Upgrading from an earlier version

1. **Quit TeamRecorderBar first** (menu bar icon → Quit) — don't replace the app while it's running
2. Follow Step 1 above; when Finder asks to replace the existing app, confirm
3. Reopen the app. There is no in-place auto-update — always re-download and replace the `.app`
4. If macOS re-prompts for Screen Recording, Microphone, or Calendar permission after the upgrade, that's expected — grant them again the same way as first-time setup (Step 3 below)

### Step 2 — Open for the first time

macOS will block the app on first open because it is not from the Mac App Store.

**Right-click → Open → Open** to bypass this warning. You only need to do this once.

> Why does this happen? Team Recorder is code-signed but not notarized through Apple.<br>
> Right-click → Open is the standard one-time bypass. After the first open, double-clicking works normally.

### Step 3 — Grant permissions (Setup Guide)

The Setup Guide opens automatically on first launch. Follow the three steps:

| Step | Permission | Why |
|------|------------|-----|
| 1 | **Screen Recording** | Captures system audio from Teams; also lets the app read the meeting title off the Teams call window when Calendar can't provide one |
| 2 | **Microphone** | Records your voice |
| 3 | **Calendar** | Names recordings after the meeting title |

**Screen Recording note:** macOS requires a relaunch after granting this permission. The Setup Guide will show a "Relaunch App" button — click it, then reopen the app and proceed.

**Calendar note:** Choose **Full Access** (not Write Only) when prompted. The app writes today's events to a file; the recorder reads it without a second permission prompt. If your organization blocks Calendar entirely (some do — Exchange sync disabled, calendar sharing locked to free/busy only), you can skip this step: recordings will be named from the Teams call window instead, as long as Screen Recording is granted.

**Tracked Calendars:** After setup, you can choose which calendars are scanned for meeting names. Click the menu bar icon → **Tracked Calendars** and check or uncheck individual calendars. Unchecked calendars are excluded from matching — useful if personal or holiday calendars pollute recording names. Default is all calendars tracked. This is a per-user setting saved locally.

### Step 4 — Click Finish

The watcher starts automatically. You'll see the grey waveform icon in your menu bar — you're ready to record.

---

## Path B — Developer Install (Terminal)

> For contributors or anyone who wants to build from source.

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools: `xcode-select --install`
- [Homebrew](https://brew.sh)

### Install

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
make setup              # install Python deps + create .env
make menu-bar-install   # build + copy to /Applications/ + launch
```

The app opens automatically. If the Setup Guide does not appear, run:

```bash
make reset-setup
```

Then reopen the app from `/Applications/`.

---

## Permissions Checklist

| Permission | Where to grant | Why needed |
|------------|----------------|------------|
| Screen Recording | System Settings → Privacy & Security → Screen Recording | Captures system audio from Teams; also reads the meeting title off the Teams call window if Calendar can't |
| Microphone | System Settings → Privacy & Security → Microphone | Records your voice |
| Calendar — Full Access | System Settings → Privacy & Security → Calendars | Names recordings after meeting title |

Screen Recording and Microphone are required for full functionality. Calendar is optional — if denied or blocked by your organization, recordings are named from the Teams call window instead (needs Screen Recording), falling back to "Teams Meeting" only if that also fails.

---

## After Setup

- Your recordings are saved to `~/Documents/Teams Recording/` by default
- To change the folder: menu bar icon → 📁 Recordings Folder → Change Folder…
- To enable auto-start on login: menu bar icon → Launch at Login

See [daily-use.md](daily-use.md) for the full daily workflow.
