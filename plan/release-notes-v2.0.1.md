# Team Recorder v2.0.1

Bug-fix release for v2.0.0. Requirements and install steps are unchanged — see [v2.0.0](https://github.com/cjarit/team-recorder/releases/tag/v2.0.0). macOS 14 users stay on [v1.2.4](https://github.com/cjarit/team-recorder/releases/tag/v1.2.4).

## Fixed

- **Meetings not recorded after Teams was restarted.** If you quit and reopened Teams while Team Recorder was running, the next meeting was never detected. The watcher now picks up Teams' call helper process whenever it appears.

## Updating from v2.0.0

Quit TeamRecorderBar, replace the app in `/Applications`, open it. Permissions are kept.

If you cannot update yet: after reopening Teams, right-click the menu bar icon → **Pause Watching**, then **Start Watching**.

## SHA256

```
7203f6dc87ad16609ed3e29a164dde308232fc72cf4323207f3c4d13f1900d45  TeamRecorderBar-v2.0.1.dmg
8e83c72f60aeca28daa555b504460d1c81273ef23eeaf949bdfe2d786cbddece  TeamRecorderBar-v2.0.1.zip
```
