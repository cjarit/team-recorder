# Team Recorder — Setup Guide

> For non-developers. Step-by-step installation and first-run setup.

## Prerequisites (ทำครั้งเดียว สำหรับเครื่องใหม่)

### 1. Xcode Command Line Tools

```bash
xcode-select --install
```

กด **Install** ในหน้าต่างที่ขึ้นมา รอจนเสร็จ (~5–10 นาที)

### 2. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

ทำตามคำแนะนำที่แสดง — บน Apple Silicon อาจต้องรันบรรทัดนี้เพิ่มหลังติดตั้ง:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

> `make setup` จะติดตั้ง Python และ icalBuddy ผ่าน Homebrew ให้อัตโนมัติ

---

## Requirements

- macOS 13 (Ventura) or later
- [icalBuddy](https://hasseg.org/icalBuddy/) — install via `brew install ical-buddy`

## Installation

### Installation

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
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
