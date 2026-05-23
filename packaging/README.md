# Team Recorder — Distribution Guide

## Current state (Phase 3D)

`make dist` creates `dist/TeamRecorder.zip` for the **developer's own machine only**.

The zip contains `TeamRecorderBar.app` which is **not portable** — it embeds an
absolute path to `teams_recorder_v2.py` on the build machine (written into
`TeamRecorderBar.app/Contents/Resources/watcher_path.txt` by `make menu-bar`).

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
