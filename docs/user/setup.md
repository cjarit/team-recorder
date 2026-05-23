# Team Recorder — Setup Guide

> For non-developers. Step-by-step installation and first-run setup.

## Requirements

- macOS 13 (Ventura) or later
- [icalBuddy](https://hasseg.org/icalBuddy/) — install via `brew install ical-buddy`

## Installation

### Option A: Developer install (full control)

```bash
make setup              # install dependencies + create .env
make menu-bar-install   # build + copy to /Applications/ + launch
```

> **หมายเหตุ:** ยังไม่มี installer สำเร็จรูป — ปัจจุบันต้อง clone repo และ build เอง
> ดู [packaging/README.md](../../packaging/README.md) สำหรับ roadmap

## First-Run Setup

The app shows a Setup Guide on first launch:

1. **Screen Recording** — click "Open System Settings", enable the toggle, then click "Relaunch App"
2. **Microphone** — click "Grant Access" and allow in the popup
3. **Calendar Access** — click "Grant Access" and choose **Full Access** (not Write Only)
4. Click **Finish** — the recorder starts automatically

## Permissions checklist

| Permission | Where to grant | Why needed |
|------------|----------------|------------|
| Screen Recording | System Settings → Privacy & Security → Screen Recording | Captures system audio from Teams |
| Microphone | System Settings → Privacy & Security → Microphone | Records your voice |
| Calendar | System Settings → Privacy & Security → Calendars | Names recordings after meeting title |
