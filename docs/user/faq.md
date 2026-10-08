# Team Recorder — FAQ

---

**Why does macOS block the app the first time I open it?**

macOS Gatekeeper blocks apps that aren't from the Mac App Store or an Apple-notarized developer. Team Recorder is signed with the project's own certificate but not notarized (this avoids a $99/year developer fee). The standard one-time bypass is: try to open the app, then go to System Settings → Privacy & Security, scroll to *"TeamRecorderBar was blocked"* and click **Open Anyway**. After that, you can double-click normally.

---

**Where are my recordings saved?**

By default: `~/Documents/Teams Recording/`

To change it: right-click the menu bar icon → **Open Team Recorder…** → **General** → Recordings folder → **Change…**<br>
The app restarts the watcher automatically and remembers your choice. (Not available while a recording is in progress.)

Rename and delete files in Finder — the app deliberately has no file manager.

---

**Why does the app need Calendar permission?**

Team Recorder reads your calendar to name the recording after the meeting title. Without it, the app falls back to reading the title off the Teams call window on screen (needs Screen Recording); if that also fails, recordings are named "Teams Meeting" plus the time.

When you grant **Full Access**, the app writes today's events to a private file (`~/Library/Application Support/Team Recorder/events-today.json`). The recorder reads that file — there are no extra Calendar prompts during recording.

---

**My organization blocked Calendar sync — why did meeting names stop working?**

Some organizations disable Exchange account sync to Apple Calendar, and separately lock Outlook's calendar-sharing feature to "free/busy only" (no meeting titles, even if you try to publish your own calendar). This is a deliberate policy set by your IT admin — there's no setting on your Mac that fixes it.

Team Recorder handles this automatically (since v1.2.0): when Calendar has no title, it reads the meeting name directly off the Teams call window on screen instead (this only needs Screen Recording permission, which the app already uses to capture system audio). Nothing is sent anywhere — it reads your own screen locally, the same way the app already captures your meeting audio.

If you'd still rather have proper calendar naming, ask your IT admin whether calendar sharing can be set to "titles and locations" instead of "free/busy only" — that's the setting that's blocked, not anything Team Recorder can control.

---

**What does the red or orange menu bar icon mean?**

| Icon | Meaning |
|------|---------|
| ○ grey waveform | Idle — waiting for a Teams meeting |
| ● red dot | Recording in progress |
| ⚠ orange | Error — click the icon to see the reason |

If the icon stays red after a meeting ends, left-click it and use **Recover Recorder…** in the popover to clear the stale state.

---

**Do I need to install anything before running the app?**

No. The `.dmg` (or `.zip`) download from GitHub Releases is self-contained — no Homebrew, no Python setup, no Terminal required. Just download, drag to Applications, and use **Open Anyway** the first time.

The only system requirement is **macOS 15 (Sequoia) or later**.

---

**The recording is named "Teams Meeting" — what's wrong?**

Try these in order:

1. Right-click the menu bar icon → **Setup Guide…** → go to the Calendar step and grant **Full Access**
2. If Open Team Recorder… → Permissions shows Calendar as granted, the bridge file may be stale — click **Refresh events** in the Calendars tab, or quit and reopen the app
3. If the meeting had no corresponding calendar event within ±5 minutes of the recording, the app tries reading the title off the Teams call window instead — check Screen Recording is granted, and that the Teams window wasn't minimized during the meeting
4. If your organization blocks Calendar entirely, see "My organization blocked Calendar sync" above — the screen-reading fallback should still work as long as Screen Recording is granted
5. If none of the above apply, the fallback name is expected

---

**The Setup Guide shows "App bundle is corrupted" — what do I do?**

This means `watcher.pyz` or the `recorder` binary is missing from the downloaded app. This can happen from a partial download or an interrupted unzip.

1. Delete `TeamRecorderBar.app` from `/Applications/`
2. Re-download the .dmg (or .zip) from [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
3. Drag the fresh copy to `/Applications/`

---

**Why are recordings smaller than before?**

Recording files are optimised for AI transcription (NotebookLM, Whisper). Audio is captured at 16 kHz mono — the same sample rate those tools use internally — so the file is roughly **3× smaller** with no loss in transcript quality. A 1-hour meeting is about 14 MB instead of ~43 MB.

If you re-listen to the recording and the audio sounds compressed, that is expected and normal. The quality is identical for transcription purposes.

---

**Why is the recording single-track instead of dual-track?**

Since v1.2.4, recordings are automatically merged into a single mono audio track after each meeting. This is because NotebookLM and other AI transcription tools read only the first audio track — if you were using an older version, your recordings had both system audio and your microphone on separate tracks, but only the meeting speakers' voices were transcribed, not yours.

The merge happens automatically after you stop recording. If a recording fails to merge (rare), the original dual-track file is kept as a backup. You can also manually re-merge any older recording by opening Terminal and running: `recorder --mixdown <path/to/file.m4a>` (replace the path with your actual recording file). Developers who want to keep the two tracks can set `SKIP_MIXDOWN=1` in the app's `.env`.

---

**Can I use this on macOS 14 Sonoma or earlier?**

Not with version 2.x — it requires macOS 15 (Sequoia) or later. On macOS 14 use **v1.2.4** from [GitHub Releases](https://github.com/cjarit/team-recorder/releases); the 1.2.x line only receives bug fixes. macOS 13 and earlier are not supported by either line.

---

**Do I have to grant permissions again every time I upgrade?**

No. From 2.0 on, every build is signed with the same certificate (**Team Recorder Signing**), so macOS recognizes each new version as the same app and keeps Screen Recording, Microphone and Calendar. Upgrading from 1.2.4 to 2.0 needs one last re-grant: macOS keeps the old TeamRecorderBar row ticked but it no longer works. In System Settings → Privacy & Security → Screen Recording, select that row, click **−**, then **+** and add `/Applications/TeamRecorderBar.app` (the Setup Guide shows these steps by itself). Your settings and recordings are not affected.

---

**macOS shows a dialog saying Team Recorder can access my computer's screen and audio — is that normal?**

Yes. Since macOS 15 Sequoia, macOS itself periodically asks you to re-confirm apps that have Screen Recording permission (about once a month). It is a system prompt, not something Team Recorder can switch off or change. Confirm it so recording keeps working; you may never see it.

---

**Why do I hear the other person twice, or an echo, in some recordings?**

Two different things. (1) In versions before 2.0 the two audio tracks slowly drifted apart, which sounded like "the same sentence, a second later". That is fixed in 2.0. (2) If you use laptop speakers, the other side's voice also reaches your microphone. The app detects this when it merges the tracks and lowers your mic while the other side is talking (so very short interjections of yours in that moment are quieter). The cleanest result always comes from **headphones**.

---

**What is "My mic" / "Record my voice"?**

In the popover, **Others** and **My mic** are two live level bars while recording: the people on the call, and your own microphone. In **Open Team Recorder… → General → Audio** you can pick which microphone is used (Auto = the system default) and switch **Record my voice** off to record only the other side (the bar then shows "off").

---

**Where did my recording go? There is an `Empty` folder.**

A recording of **3 minutes or longer** that contains no speech at all is moved (never deleted) to an `Empty/` subfolder of the recordings folder, with a notification. Shorter calls ("Teams Call (Short)") are not moved. If a real recording ended up there, drag it back out in Finder.

---

**How do I uninstall?**

Right-click the menu bar icon → **Uninstall Team Recorder…** → confirm. The app is moved to the Trash and the watcher stopped; your recordings and settings are kept. macOS permissions stay listed in System Settings → Privacy & Security until you remove them yourself.

---

**Is it legal to record meetings with this tool?**

That depends on your jurisdiction and the nature of the meeting. Recording consent requirements vary by country and context — in Thailand, the Personal Data Protection Act (PDPA B.E. 2562) treats voice recordings of identifiable individuals as personal data and requires a lawful basis (typically explicit consent) before collection. Microsoft's Terms of Service also require you to inform and obtain consent from all participants before recording a Teams call.

**You are responsible for obtaining consent from all meeting participants before recording.** A common practice is to state at the start of the meeting that it will be recorded and confirm no one objects. The authors of this software accept no liability for recordings made without proper consent.
