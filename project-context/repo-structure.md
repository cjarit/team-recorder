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

- `scripts/` — build helpers (make_icon.py)
- `packaging/` — removed; content archived to plan/archive/packaging-phase-3e-roadmap.md
- `dist/` — generated artifacts; gitignored; produced by `make release` (replaces old `make dist`)
