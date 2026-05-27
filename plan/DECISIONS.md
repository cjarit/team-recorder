# Decisions — Team Recorder

Architectural and product decisions with rationale. Add new entries chronologically.

---

## 2026-05-26 — v1.0 release decisions

### Code signing: ad-hoc (not Apple Developer ID)
- **Decision:** Sign the .app with ad-hoc (`codesign -s -`). README documents the right-click → Open Gatekeeper bypass.
- **Rationale:** Avoids $99/yr Apple Developer Program cost. Users are internal Thai design team + trusted collaborators who can follow a one-time bypass.
- **Trade-off:** Users see a Gatekeeper warning on first open. Documented clearly in README.

### Minimum macOS: 14 Sonoma
- **Decision:** Bump both `Package.swift` platform targets from `.v13` to `.v14`.
- **Rationale:** Resolves SMAppService 13.0/13.1 ambiguity. EKEventStore full-access API requires 14. Aligns with team's actual hardware.
- **Trade-off:** macOS 13 Ventura users cannot run the app. Not a known user segment.

### Python bundling: Plan A = zipapp + system Python 3
- **Decision:** Bundle `teams_recorder_v2.py` + `dotenv` into `watcher.pyz` via `zipapp`. Use system `/usr/bin/python3` (ships with macOS 14 at 3.9.6).
- **Rationale:** Lightweight (~50KB bundle vs ~30MB PyInstaller), no notarization complications, no additional toolchain required.
- **Fallback (Plan B):** If `/usr/bin/python3` is absent or below 3.9 on Sonoma (must verify on real Sonoma device — open question in requirements spec), switch to PyInstaller `--onefile`. Activate by documenting here and updating `make watcher-pyz`.
- **Implementation note:** `psutil` is NOT a dependency — stdlib + `python-dotenv` only. No native C extensions, no arch-specific wheels needed.

### Template adoption: workspace-doctor structural adoption (with documented deviations)
- **Decision:** Migrate from `docs/dev/` + `docs/plans/` layout to `project-context/` + `plan/` per `~/Documents/Claude/Template/_meta/modules.yml`. This is a structural adoption — all folder modules are aligned, but several file-level items in the template's `core` module are deliberately omitted.
- **Rationale:** Consistency with all other Claude/AI projects on this machine.
- **Deliberate deviations from template `core` module** (not oversights):
  - `.mcp.json` — no MCP servers are project-specific for this repo; all MCP config is in the user's global settings
  - `CLAUDE.local.md.example` — CLAUDE.md is already the full context file; a local example adds no value for this single-maintainer project
  - `.claude/settings.json` (committed) — settings are machine-specific and gitignored intentionally; shared settings are not needed
- **Skipped optional modules:** wiki/, memory/, inbox/, design/, deliverables/, plan/SPEC.md — not needed for this project type.

### No commits until Phase 6
- **Decision:** All work stays as local file edits. GitHub `main` stays untouched until Phase 6 release commit.
- **Rationale:** Current GitHub version is usable by developers via `make setup`. Don't risk breaking it mid-work.
