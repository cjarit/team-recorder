## adhoc control (expect grants lost) — 2026-10-08 15:04
```
# designated => cdhash H"d8e9b4ede03aeae9c7854e72a126b0827b8a49e3"
Signature=adhoc 
{
  "calendar" : "undetermined",
  "microphone" : "undetermined",
  "screenRecording" : "denied",
  "ts" : "2026-10-08T15:04:23",
  "version" : "2.0.0-dev"
}
```

## cert cycle 1 (before grant) — 2026-10-08 15:04
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "undetermined",
  "microphone" : "undetermined",
  "screenRecording" : "denied",
  "ts" : "2026-10-08T15:04:39",
  "version" : "2.0.0-dev"
}
```

## cert cycle 1 — after grant 2026-10-08 15:06
```
{
  "calendar" : "undetermined",
  "microphone" : "undetermined",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:06:29",
  "version" : "2.0.0-dev"
}```

## cert cycle 2 (rebuild+reinstall, no user action) — 2026-10-08 15:07
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:07:08",
  "version" : "2.0.0-dev"
}
```

## cert cycle 3 (rebuild+reinstall, no user action) — 2026-10-08 15:07
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:07:26",
  "version" : "2.0.0-dev"
}
```

CDHash cycle2: CDHash=719e3a6fc212cad240bc827e0dfab25e4384efe1
CDHash cycle3: CDHash=19c912edbc3506b1f7c4056327213ed084d1f1ed

## teammate condition — cert removed from keychain, new build f1eccd7c installed 2026-10-08 15:08
```
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:08:06",
  "version" : "2.0.0-dev"
}codesign --verify: valid on disk, satisfies its Designated Requirement
```

**Result: PASS** — 3 cert cycles (CDHash 719e3a…, 19c912…, f1eccd…) all granted with no user action; ad-hoc control lost Screen Recording and reset Mic/Calendar.
## Phase 2 upgrade: orphan watcher + first launch of self-heal build — 2026-10-08 15:12
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:12:23",
  "version" : "2.0.0-dev"
}
```

## Phase 2 upgrade retest (after wait-for-exit fix) — 2026-10-08 15:13
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:13:20",
  "version" : "2.0.0-dev"
}
```

## Phase 2 upgrade: orphan watcher + forced version change — 2026-10-08 15:15
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:15:40",
  "version" : "2.0.0-dev"
}
```

## reinstall after Uninstall… (6th cert install) — 2026-10-08 15:32
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:32:18",
  "version" : "2.0.0-dev"
}
```

## Phase 3 build (levels + speech meta) — 2026-10-08 15:51
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:51:50",
  "version" : "2.0.0-dev"
}
```

## Phase 3 build 2 (sys buffer counters) — 2026-10-08 15:57
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:57:13",
  "version" : "2.0.0-dev"
}
```

## Phase 3 build 3 (format diag) — 2026-10-08 15:58
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:58:50",
  "version" : "2.0.0-dev"
}
```

## Phase 3 build 4 (ABL size query) — 2026-10-08 15:59
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T15:59:48",
  "version" : "2.0.0-dev"
}
```

## Phase 3 final build (-45 dBFS cutoff) — 2026-10-08 16:09
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T16:09:22",
  "version" : "2.0.0-dev"
}
```

## Phase 4 build (Settings window, 5-item menu) — 2026-10-08 16:26
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T16:26:49",
  "version" : "2.0.0-dev"
}
```

## Phase 5 build (MIC_PATH=sck available) — 2026-10-08 17:04
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:04:37",
  "version" : "2.0.0-dev"
}
```

## Phase 5 final (SCK mic default) — 2026-10-08 17:22
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:22:16",
  "version" : "2.0.0-dev"
}
```

## Phase 6 (SKIP_MIXDOWN debug flag) — 2026-10-08 17:36
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:36:00",
  "version" : "2.0.0-dev"
}
```

## Phase 6 drift instrumentation — 2026-10-08 17:38
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:38:25",
  "version" : "2.0.0-dev"
}
```

## Phase 6 fix: clock-anchored track positions — 2026-10-08 17:42
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:42:41",
  "version" : "2.0.0-dev"
}
```

## Phase 6b (bleed ducking in mixdown) — 2026-10-08 17:57
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T17:57:21",
  "version" : "2.0.0-dev"
}
```

## v2.0.0 release build installed — 2026-10-08 18:04
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T18:04:41",
  "version" : "2.0.0"
}
```

## v2.0.0 final (popover permissions hidden when OK) — 2026-10-08 18:10
```
designated => identifier "com.team-recorder.menu-bar" and certificate leaf = H"3bc6cab381aa3542ef37b160db93e57400ead745"
Signature size=1680 Authority=Team Recorder Signing 
{
  "calendar" : "granted",
  "microphone" : "granted",
  "screenRecording" : "granted",
  "ts" : "2026-10-08T18:10:39",
  "version" : "2.0.0"
}
```

