# Team Recorder — Setup Guide

> For new users. Step-by-step installation and first-run setup.

---

## Path A — Download from GitHub Releases (Recommended)

> No Terminal, no Homebrew required.

### Step 1 — Download and install

1. Go to [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
2. Download **TeamRecorderBar-v1.0.0.zip**
3. Double-click the zip to extract it
4. Drag **TeamRecorderBar.app** to your **Applications** folder

### Step 2 — Open for the first time

macOS will block the app on first open because it is not from the Mac App Store.

**Right-click → Open → Open** to bypass this warning. You only need to do this once.

> Why does this happen? Team Recorder is code-signed but not notarized through Apple.<br>
> Right-click → Open is the standard one-time bypass. After the first open, double-clicking works normally.

### Step 3 — Grant permissions (Setup Guide)

The Setup Guide opens automatically on first launch. Follow the three steps:

| Step | Permission | Why |
|------|------------|-----|
| 1 | **Screen Recording** | Captures system audio from Teams |
| 2 | **Microphone** | Records your voice |
| 3 | **Calendar** | Names recordings after the meeting title |

**Screen Recording note:** macOS requires a relaunch after granting this permission. The Setup Guide will show a "Relaunch App" button — click it, then reopen the app and proceed.

**Calendar note:** Choose **Full Access** (not Write Only) when prompted. The app writes today's events to a file; the recorder reads it without a second permission prompt.

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
| Screen Recording | System Settings → Privacy & Security → Screen Recording | Captures system audio from Teams |
| Microphone | System Settings → Privacy & Security → Microphone | Records your voice |
| Calendar — Full Access | System Settings → Privacy & Security → Calendars | Names recordings after meeting title |

All three are required for full functionality. Calendar is optional — if denied, recordings are named "Teams Meeting" instead of the meeting title.

---

## After Setup

- Your recordings are saved to `~/Documents/Teams Recording/` by default
- To change the folder: menu bar icon → 📁 Recordings Folder → Change Folder…
- To enable auto-start on login: menu bar icon → Launch at Login

See [daily-use.md](daily-use.md) for the full daily workflow.
