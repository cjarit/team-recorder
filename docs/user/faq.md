# Team Recorder — FAQ

---

**Why do I have to right-click → Open the first time?**

macOS Gatekeeper blocks apps that aren't from the Mac App Store or an Apple-notarized developer. Team Recorder is code-signed but not notarized (this avoids a $99/year developer fee). Right-clicking → Open is the standard one-time bypass Apple provides for trusted apps. After that first open, you can double-click normally.

---

**Where are my recordings saved?**

By default: `~/Documents/Teams Recording/`

To change it: click the menu bar icon → 📁 Recordings Folder → **Change Folder…**<br>
The app restarts the watcher automatically and remembers your choice.

---

**Why does the app need Calendar permission?**

Team Recorder reads your calendar to name the recording after the meeting title. Without it, every recording is named "Teams Meeting" plus the time.

When you grant **Full Access**, the app writes today's events to a private file (`~/Library/Application Support/Team Recorder/events-today.json`). The recorder reads that file — there are no extra Calendar prompts during recording.

---

**What does the red or orange menu bar icon mean?**

| Icon | Meaning |
|------|---------|
| ○ grey waveform | Idle — waiting for a Teams meeting |
| ● red dot | Recording in progress |
| ⚠ orange | Error — click the icon to see the reason |

If the icon stays red after a meeting ends, click **Recover Recorder…** in the menu to clear the stale state.

---

**Do I need to install anything before running the app?**

No. The `.app` download from GitHub Releases is self-contained — no Homebrew, no Python setup, no Terminal required. Just download, drag to Applications, and right-click Open.

The only system requirement is **macOS 14 (Sonoma) or later**.

---

**The recording is named "Teams Meeting" — what's wrong?**

Usually a Calendar permission issue. Try these in order:

1. Click the menu bar icon → **Setup Guide…** → go to the Calendar step and grant **Full Access**
2. If it shows "Calendar: OK" in Permissions, the bridge file may be stale — quit and reopen the app to refresh it
3. If the meeting had no corresponding calendar event within ±5 minutes of the recording, the fallback name is expected

---

**The Setup Guide shows "App bundle is corrupted" — what do I do?**

This means `watcher.pyz` or the `recorder` binary is missing from the downloaded app. This can happen from a partial download or an interrupted unzip.

1. Delete `TeamRecorderBar.app` from `/Applications/`
2. Re-download the zip from [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
3. Unzip and drag the fresh copy to `/Applications/`

---

**Can I use this on macOS 13 Ventura or earlier?**

No. Team Recorder requires macOS 14 (Sonoma) or later. This is a hard requirement — the app uses Calendar APIs (EKEventStore full access) that are only stable on macOS 14+.
