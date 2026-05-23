# Repo Structure

See top-level CLAUDE.md for the canonical file map.
This file describes the folder conventions so agents and developers
do not flatten or reorganise without reading it first.

## Runtime files (do not move)

- `teams_recorder_v2.py` — Python watcher brain; Makefile + watcher_path.txt reference it here
- `recorder/` — Swift capture binary + source
- `menu-bar/` — Swift menu bar app

## Support folders

- `docs/user/` — non-developer help (setup, daily use, troubleshooting)
- `docs/dev/` — architecture notes, protocol docs, release checklists
- `docs/plans/` — completed and in-progress phase plans
- `docs/archive/` — superseded docs
- `packaging/` — distribution instructions (see packaging/README.md)
- `dist/` — generated artifacts; gitignored; created by `make dist`
