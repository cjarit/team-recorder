# Lessons — Team Recorder

Post-release lessons captured here.

---

## v1.0.0 — 2026-05-27

### What worked well

- **zipapp + system Python** was the right call. No native extensions needed (psutil was never a real dependency), so the entire watcher bundle is 208 KB. No arch-specific wheels, no PyInstaller complexity.
- **Incremental EARS spec first** (Phase 3) meant Phase 4 implementation had zero ambiguous requirements. Every Swift and Python change had a matching FR/AC to verify against.
- **Keeping `TEAM_RECORDER_APP` over introducing a new env var** — the bridge reader already existed and already used that flag. Adding a second flag (`TEAM_RECORDER_LAUNCH_MODE`) would have created drift with no benefit.
- **Phased QA gates** caught real bugs: empty `RECORDING_DIR` bootstrap (P1), stale PID detection for `watcher.pyz` (P2), trailing whitespace in docs (P2). Each was caught before the commit gate.

### What was harder than expected

- **`BASE_DIR` inside a `.pyz`** — `os.path.dirname(os.path.abspath(__file__))` resolves to the `.pyz` archive path, not a directory. The fix (set `RECORDER_BIN` from WatcherManager) was clean, but this wasn't obvious from reading the code.
- **The `dist:` target warning was wrong for two phases** — it said the zip was "LOCAL MACHINE ONLY" throughout Phase 4 even after the absolute-path writes were removed, until Phase 6 cleanup. A single-source-of-truth for "is this zip portable" would have caught it earlier.
- **Sonoma device unavailability** — the smoke test deferred from Phase 2 remained deferred through all phases. For future releases, establish a Sonoma VM (UTM + macOS 14 IPSW) as part of the release infrastructure before starting the release cycle.

### Architecture notes for next release

- **Universal binary** (`lipo -create arm64 x86_64 -output recorder`) would eliminate the arch-specific release problem. Requires building on both arch machines or using a cross-compilation CI setup.
- **Notarization** — as the app gains more external users, the right-click bypass friction will increase. Apple Developer Program ($99/yr) + `xcrun notarytool` is the path. Gatekeeper policy tightens with each macOS version.
- **Auto-update** — no mechanism exists. Users must re-download from Releases. Sparkle framework is the standard macOS approach if this becomes a priority.

---

## v1.2.4 — 2026-09-29 (stop/start hang on Bluetooth switch)

Each item: principle / case / trigger / action / scope.

1. **A PoC gate must include the failure condition itself, not just the happy path.**
   - Case: fragmented writing (`movieFragmentInterval`) passed a kill -9 test with a healthy mic. In production the mic was dead, and AVAssetWriter stopped fragmenting after ~220s (seen in the atom list of `rec_14-00_29-09-2026.m4a`: 21 moof, then one 23 MB mdat).
   - Trigger: a fix is meant to protect against condition X, and the gate test doesn't create X.
   - Action: write the gate as "reproduce X, then check the output", and run it past any known thresholds (here: 6 min > 220s, verified by decoding the full length, not ffprobe's header).
   - Scope: any agent work.

2. **Validate a recovery or repair tool on a known answer before handing its output over.**
   - Case: untrunc's "(recovered)" 09-28 file passed ffprobe and decoded with 0 errors, but it had assigned packets between the 2 tracks by strict alternation, while the writer uses runs of about 8 packets. The result was chopped speech, which the user found through NotebookLM.
   - Trigger: a tool reconstructs structure (tracks, indexes, tables) and we only checked the structure is valid.
   - Action: run the tool on a healthy sample with the answer stripped, and compare against the truth (here: per-packet `stream_index`) before delivering.
   - Scope: any agent work.

3. **An AI critique of an artifact is a list of claims, and each one gets checked separately.**
   - Case: NotebookLM's audio report mixed a real defect (chopped audio from the recovery) with false positives: VAD (we have none), fillers, cross-talk. Checking each claim also surfaced that NotebookLM reads only track 1.
   - Trigger: a pasted AI review or QA list.
   - Action: for each item, name the measurement that settles it (volumedetect, silencedetect, packet runs) and classify it as real, false positive or open.
   - Scope: any agent work.

4. **When the root cause is a class, fix every call site of the class in the same round.**
   - Case: round 1 bounded the AVAudioEngine call on the **stop** path. The next day the same class (an AVAudioEngine call on the control thread during a BT HFP switch) blocked **start** for 59 min, and a meeting was lost.
   - Trigger: the root cause is worded as "X can block/fail", and X is called from more than one place.
   - Action: grep every call of X, and fix or bound them all (here: all of them onto `micQ`, and `start`/`stop` never wait unbounded).
   - Scope: any agent work.

5. **Derive the test setup from the incident log, not from intuition.**
   - Case: I told the user to set the BT headset as the system input. That pre-engages HFP, so no switch happened in 2 test runs. The incident log showed the real setup: system input = MacBook mic, with Teams picking the headset.
   - Trigger: asking the user to reproduce a field incident.
   - Action: read the device and route state from the incident's system log first, and copy that state into the test steps.
   - Scope: this project, and any hardware-dependent repro.

6. **Review a subagent's diff against the surrounding control flow, not only against its own tests.**
   - Case: the start-timeout rate-limit returned a killed process. On the next loop, the main loop's `proc.poll()` check would have counted that as a crash. The subagent's unit tests passed.
   - Trigger: a subagent changes code called from a loop or state machine.
   - Action: trace one iteration of the caller with the new return values before accepting.
   - Scope: any agent work.

**Strengths (keep doing):**
- Sampling the live stuck process (`sample <pid>`) plus the thread's silence in `log show` turned a hypothesis into proof.
- A 20-line experiment proved that `cancelWriting()` deletes the output file, before we relied on it.
- Asking the user one decisive question with a crafted test file (a 2-track NotebookLM test) settled a product question in 5 minutes.

---

## v2.0 planning — 2026-10-08

Each item: principle / case / trigger / action / scope.

1. **Measure a reported quality complaint against the artifacts you already have before choosing a fix.**
   - Case: "echo" feedback arrived with no file. Cross-correlating system vs mic track on the owner's own dual-track recordings (28–29 Sep) gave max 0.04 — no speaker bleed. That relocated the problem to the reporter's setup (speakers + MacBook mic) instead of a guessed audio-path change. Script: scratchpad `echo/xcorr.py`, to be moved to `scripts/` when Phase 6 runs.
   - Trigger: a user-reported audio/quality complaint, no sample attached.
   - Action: write a ≤40-line measurement on existing recordings first; report the negative result with numbers; only then rank fixes.
   - Scope: any agent work.

2. **When the pain is "we have to re-grant permissions after every install", read the installed artifact's identity before designing installer UX.**
   - Case: `codesign -dr - /Applications/TeamRecorderBar.app` → `designated => cdhash H"…"`, `Signature=adhoc`. The fix is a stable signing identity (D-1), not a smarter setup window. `security find-identity -v -p codesigning` → 0 identities confirmed nothing existed to reuse.
   - Trigger: a request worded as "easier install", "clean reinstall", or "permissions reset again".
   - Action: run `codesign -dr -` and `security find-identity` first; put the output in the plan's evidence table.
   - Scope: this project and any macOS app work.

3. **`git status` is part of orientation on a shared repo — another session may already have built part of the plan.**
   - Case: an uncommitted `PopoverView.swift` + 114-line `StatusBarController` diff from a parallel session was found only because the owner mentioned it; it changed Phase 3 from "build" to "fix two contrast issues on device".
   - Trigger: start of a planning session; working tree not clean.
   - Action: list modified/untracked files and read their purpose before writing phases.
   - Scope: any agent work.

**Strengths (keep doing):**
- One grill question per turn, each with a recommended answer and the tension stated: 7 decisions settled in 6 turns; the owner took 4 recommendations as-is and modified 2 (hybrid popover+window; PoC B inside v2.0). When one answer settles two questions (macOS floor + release line), accept it and move on — don't re-ask.
- Advisor passes before and after the plan each added concrete gate conditions (teammate-Mac cert test, stale TCC row, tools-version 6.0) that the first draft lacked.
