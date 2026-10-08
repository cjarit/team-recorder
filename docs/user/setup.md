# Team Recorder — Setup Guide

> For new users. Step-by-step installation and first-run setup.
> Requires **macOS 15 (Sequoia) or later**. On macOS 14, see "Older macOS (14)" at the end.

---

## Path A — Download from GitHub Releases (Recommended)

> No Terminal, no Homebrew required.

### Step 1 — Download and install

1. Go to [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
2. Download **TeamRecorderBar-v2.0.0.dmg** (or **TeamRecorderBar-v2.0.0.zip** if you prefer a zip)
3. Open the .dmg and drag **TeamRecorderBar.app** onto the **Applications** shortcut in the same window. (With the zip: double-click to extract, then drag the app to Applications)

### Upgrading from an earlier version

1. **Quit TeamRecorderBar first** (right-click the menu bar icon → Quit) — don't replace the app while it's running
2. Follow Step 1 above; when Finder asks to replace the existing app, confirm
3. Reopen the app. There is no in-place auto-update — download the new release and replace the `.app`. To see whether a newer version exists: **Open Team Recorder… → Status → Check for Updates** (it opens the release page; it never installs anything)
4. The app tidies up after itself on the first launch of a new version (it stops the old watcher). **Your settings and recordings are kept.**

**Permissions after upgrading:**

- Every build since 2.0 is signed with the same certificate (**Team Recorder Signing**). Grant Screen Recording, Microphone and Calendar **once** and later upgrades keep them.
- **Moving from 1.2.4 to 2.0 needs one last re-grant.** macOS keeps the old TeamRecorderBar row in the list, still ticked, but it no longer works. In System Settings → Privacy & Security → Screen Recording, select the existing TeamRecorderBar row, click **−**, then click **+** and choose `/Applications/TeamRecorderBar.app`. The Setup Guide shows these steps automatically when it detects this case.

### Step 2 — Open for the first time

macOS will block the app on first open because it is not notarized by Apple.

1. Try to open the app (it will be blocked)
2. Go to **System Settings → Privacy & Security**
3. Scroll down to *"TeamRecorderBar was blocked"* and click **Open Anyway** → enter your password

You only need to do this once.

> Why does this happen? Team Recorder is signed with the project's own certificate but not notarized through Apple (avoids a $99/year fee). "Open Anyway" is the standard one-time bypass.

### Step 3 — Grant permissions (Setup Guide)

The Setup Guide opens automatically on first launch. Follow the three steps:

| Step | Permission | Why |
|------|------------|-----|
| 1 | **Screen Recording** | Captures system audio from Teams; also lets the app read the meeting title off the Teams call window when Calendar can't provide one |
| 2 | **Microphone** | Records your voice |
| 3 | **Calendar** | Names recordings after the meeting title |

**Screen Recording note:** macOS requires a relaunch after granting this permission. The Setup Guide will show a "Relaunch App" button — click it, then reopen the app and proceed.

**Calendar note:** Choose **Full Access** (not Write Only) when prompted. The app writes today's events to a file; the recorder reads it without a second permission prompt. If your organization blocks Calendar entirely (some do — Exchange sync disabled, calendar sharing locked to free/busy only), skip this step: recordings will be named from the Teams call window instead, as long as Screen Recording is granted. You can change this later in **Open Team Recorder… → Permissions**.

**Tracked Calendars:** After setup you can choose which calendars are scanned for meeting names. Right-click the menu bar icon → **Open Team Recorder…** → **Calendars** tab, and check or uncheck individual calendars (**Select All** and **Refresh events** are there too). Unchecked calendars are excluded from matching — useful if personal or holiday calendars pollute recording names. Default is all calendars tracked. This is a per-user setting saved locally.

### Step 4 — Click Finish

The watcher starts automatically. You'll see the grey waveform icon in your menu bar — you're ready to record.

---

## Path B — Developer Install (Terminal)

> For contributors or anyone who wants to build from source.

### Prerequisites

- macOS 15 (Sequoia) or later
- Xcode Command Line Tools: `xcode-select --install`
- [Homebrew](https://brew.sh)

### Install

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
make setup              # install Python deps + create .env
make cert               # once per Mac: create the "Team Recorder Signing" certificate
make menu-bar-install   # build + copy to /Applications/ + launch
```

After `make cert`, run this once yourself in Terminal (it asks for your Mac login password, so type it there, never in a chat or a script) so `codesign` can use the key without prompting on every build:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

`make menu-bar` stops with `run: make cert` if the certificate is missing; it never falls back to ad-hoc signing (an ad-hoc build makes macOS forget the permissions on every rebuild).

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

Screen Recording and Microphone are required for full functionality. Calendar is optional — if denied, skipped, or blocked by your organization, recordings are named from the Teams call window instead (needs Screen Recording), falling back to "Teams Meeting" only if that also fails.

---

## After Setup

- Your recordings are saved to `~/Documents/Teams Recording/` by default
- To change the folder: right-click the menu bar icon → **Open Team Recorder…** → **General** → Recordings folder → **Change…**
- To enable auto-start on login: same window → **General** → **Launch at Login**

See [daily-use.md](daily-use.md) for the full daily workflow.

---

## Older macOS (14)

Version 2.x needs macOS 15 or later. On macOS 14 (Sonoma) use **v1.2.4** from [GitHub Releases](https://github.com/cjarit/team-recorder/releases). The 1.2.x line only receives bug fixes (branch `release/1.x`).
