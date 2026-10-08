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

