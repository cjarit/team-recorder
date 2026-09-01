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

Team Recorder reads your calendar to name the recording after the meeting title. Without it, the app falls back to reading the title off the Teams call window on screen (needs Screen Recording); if that also fails, recordings are named "Teams Meeting" plus the time.

When you grant **Full Access**, the app writes today's events to a private file (`~/Library/Application Support/Team Recorder/events-today.json`). The recorder reads that file — there are no extra Calendar prompts during recording.

---

**My organization blocked Calendar sync — why did meeting names stop working?**

Some organizations disable Exchange account sync to Apple Calendar, and separately lock Outlook's calendar-sharing feature to "free/busy only" (no meeting titles, even if you try to publish your own calendar). This is a deliberate policy set by your IT admin — there's no setting on your Mac that fixes it.

Team Recorder handles this automatically as of v1.2.0: when Calendar has no title, it reads the meeting name directly off the Teams call window on screen instead (this only needs Screen Recording permission, which the app already uses to capture system audio). Nothing is sent anywhere — it reads your own screen locally, the same way the app already captures your meeting audio.

If you'd still rather have proper calendar naming, ask your IT admin whether calendar sharing can be set to "titles and locations" instead of "free/busy only" — that's the setting that's blocked, not anything Team Recorder can control.

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

Try these in order:

1. Click the menu bar icon → **Setup Guide…** → go to the Calendar step and grant **Full Access**
2. If it shows "Calendar: OK" in Permissions, the bridge file may be stale — quit and reopen the app to refresh it
3. If the meeting had no corresponding calendar event within ±5 minutes of the recording, the app tries reading the title off the Teams call window instead — check Screen Recording is granted, and that the Teams window wasn't minimized during the meeting
4. If your organization blocks Calendar entirely, see "My organization blocked Calendar sync" above — the screen-reading fallback should still work as long as Screen Recording is granted
5. If none of the above apply, the fallback name is expected

---

**The Setup Guide shows "App bundle is corrupted" — what do I do?**

This means `watcher.pyz` or the `recorder` binary is missing from the downloaded app. This can happen from a partial download or an interrupted unzip.

1. Delete `TeamRecorderBar.app` from `/Applications/`
2. Re-download the zip from [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
3. Unzip and drag the fresh copy to `/Applications/`

---

**Why are recordings smaller than before?**

Recording files are optimised for AI transcription (NotebookLM, Whisper). Audio is captured at 16 kHz mono — the same sample rate those tools use internally — so the file is roughly **3× smaller** with no loss in transcript quality. A 1-hour meeting is about 14 MB instead of ~43 MB.

If you re-listen to the recording and the audio sounds compressed, that is expected and normal. The quality is identical for transcription purposes.

---

**Can I use this on macOS 13 Ventura or earlier?**

No. Team Recorder requires macOS 14 (Sonoma) or later. This is a hard requirement — the app uses Calendar APIs (EKEventStore full access) that are only stable on macOS 14+.

---

**Is it legal to record meetings with this tool?**

That depends on your jurisdiction and the nature of the meeting. Recording consent requirements vary by country and context — in Thailand, the Personal Data Protection Act (PDPA B.E. 2562) treats voice recordings of identifiable individuals as personal data and requires a lawful basis (typically explicit consent) before collection. Microsoft's Terms of Service also require you to inform and obtain consent from all participants before recording a Teams call.

**You are responsible for obtaining consent from all meeting participants before recording.** A common practice is to state at the start of the meeting that it will be recorded and confirm no one objects. The authors of this software accept no liability for recordings made without proper consent.
