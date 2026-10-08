# Repo Structure

See root `CLAUDE.md` for the canonical file map.
This file describes folder conventions so contributors do not reorganise without reading it first.

## Runtime files (do not move)

- `teams_recorder_v2.py` — Python watcher brain; Makefile + watcher_path.txt reference it here
- `recorder/` — Swift capture binary + source
- `menu-bar/` — Swift menu bar app

## User-facing docs

- `docs/user/` — setup, daily-use, troubleshooting, faq

## Developer context

- `project-context/` — architecture, tech stack, stakeholders, glossary, repo-structure, release-checklist
- `plan/` — NOW.md (current work), DECISIONS.md, LESSONS.md, CHANGELOG.md
- `plan/archive/` — completed phase plans, historical docs

## Support folders

- `scripts/` — build helpers (`make_icon.py`, `make-cert.sh`), measurement tools (`xcorr.py`, `speech_ratio.py`) and gate scripts (`tcc-persist-test.sh`, `phase2-upgrade-check.sh`, `phase5-bt-gate.sh`)
- `packaging/` — removed; content archived to plan/archive/packaging-phase-3e-roadmap.md
- `dist/` — generated artifacts; gitignored; produced by `make release` / `make dmg` (zip and dmg)

## Release lines

- `main` — v2.x (macOS 15+)
- `release/1.x` — v1.2.x (macOS 14), bug fixes only; v1.2.4 stays on GitHub Releases

## Removed in v2.0

- `Setup.command` and `Start Recorder.command` (legacy double-click launchers) — use the app, or `make run` for developers
