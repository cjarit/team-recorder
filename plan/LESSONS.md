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
