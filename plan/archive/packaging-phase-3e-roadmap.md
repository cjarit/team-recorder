# Team Recorder — Distribution Guide

## Current state (Phase 3D)

`make dist` creates `dist/TeamRecorder.zip` for the **developer's own machine only**.

The zip contains `TeamRecorderBar.app` which is **not portable** — `make menu-bar`
embeds two absolute paths from the build machine into `TeamRecorderBar.app/Contents/Resources/`:

- `watcher_path.txt` — absolute path to `teams_recorder_v2.py`
- `python_path.txt` — absolute path to the Homebrew Python interpreter that has the runtime deps (`python-dotenv`)

Both paths must exist on the target machine, so the bundle works only on the build machine
unless Phase 3E (below) bundles the runtime and pins a portable interpreter.

## How to share with teammates right now

Teammates must clone the repo and build locally:

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
make setup              # install dependencies
make menu-bar-install   # build + copy to /Applications/ + launch
```

## Phase 3E (planned): true teammate distribution

Options under consideration:

- **Bundle runtime inside the `.app`** — copy `teams_recorder_v2.py` + `recorder/recorder`
  into `TeamRecorderBar.app/Contents/Resources/` at build time; update `WatcherManager`
  to find them via `Bundle.main.resourceURL`
- **`.pkg` installer** — install runtime files to `/usr/local/share/team-recorder/`;
  `watcher_path.txt` points there

Until Phase 3E lands, the zip from `make dist` is developer-only.
