# Teams Auto-Recorder

บันทึกเสียง Microsoft Teams meeting อัตโนมัติ — ไม่ต้องใช้ OBS

เมื่อเข้า Teams call → เริ่มอัดเอง  
เมื่อออกจาก call → หยุดอัด ตั้งชื่อไฟล์ตาม calendar อัตโนมัติ

---

## Requirements

- macOS 13 (Ventura) ขึ้นไป
- Python 3.11+
- [icalBuddy](https://hasseg.org/icalBuddy/) (`brew install ical-buddy`)
- สิทธิ์ **Screen Recording** ให้ Terminal (ตั้งครั้งเดียว)

---

## Quick Start

```bash
# 1. ติดตั้ง dependencies
make setup

# 2. Build และติดตั้ง menu bar app ไปที่ /Applications/ (แนะนำ)
make menu-bar-install
# แอปจะเปิดขึ้นอัตโนมัติ และแสดง Setup Guide ครั้งแรก
# → ทำตามขั้นตอน: Screen Recording → Microphone → Calendar → Finish
```

**หรือ** build แบบ local (ไม่ copy ไป /Applications/):
```bash
make menu-bar
# จากนั้นดับเบิลคลิก Start Recorder.command
```

> **หมายเหตุ:** ถ้าย้ายโฟลเดอร์โปรเจกต์ ให้รัน `make menu-bar` หรือ `make menu-bar-install` อีกครั้งเพื่ออัปเดต path

---

### วิธีใช้ Terminal (ไม่ผ่าน menu bar)

```bash
# เปิดสิทธิ์ Screen Recording ให้ Terminal ก่อน (ทำครั้งเดียว)
# System Settings → Privacy & Security → Screen Recording → Terminal ✓

make run
```

---

## Menu Bar App

เมื่อ TeamRecorderBar.app เปิดอยู่ จะเห็น icon ที่ menu bar ด้านขวาบน:

| Icon | ความหมาย |
|------|-----------|
| ○ waveform (grey) | Idle / รอ Teams meeting |
| ● record.circle (red) | กำลังบันทึก |
| ⚠ ! (orange) | Error |

**เมนู:**

| รายการ | ทำอะไร |
|--------|---------|
| ▶ Start Recording | เริ่มบันทึกทันที (ไม่ต้องรอ Teams) |
| ■ Stop Recording | หยุดบันทึก |
| Stop / Start Watcher | เปิด/ปิด watcher process |
| 📁 Recordings Folder ▶ | ดู path ปัจจุบัน, Open Folder, **Change Folder…** |
| Last: … | คลิกเพื่อเปิดไฟล์ล่าสุดใน Finder |
| Permissions ▶ | เปิด System Settings → Screen Recording / Microphone / Calendar |
| Setup Guide… | เปิดหน้าต่าง setup step-by-step อีกครั้ง |
| Launch at Login | เปิด/ปิดการเริ่มต้นอัตโนมัติเมื่อ login |

**Change Folder…** จะอัปเดต `RECORDING_DIR` ใน `.env` แล้ว restart watcher อัตโนมัติ
(ปุ่มนี้จะ disable ขณะกำลังบันทึก)

**Setup Guide** — เปิดขึ้นอัตโนมัติครั้งแรกที่รันแอป แนะนำการให้สิทธิ์ทีละขั้นตอน:
Screen Recording → Microphone → Calendar
เมื่อกด Finish แอปจะเริ่ม watcher ให้เลย

**Launch at Login** — ต้องติดตั้งแอปไว้ที่ `/Applications/` ก่อน (ใช้ `make menu-bar-install`)
ถ้ากดแล้วไม่ work จะมี alert แจ้ง

---

## Output

ไฟล์บันทึกจะอยู่ที่ `~/Documents/Teams Recording/` (แก้ได้จาก menu bar → 📁 Recordings Folder → Change Folder… หรือใน `.env`)

ชื่อไฟล์ตัวอย่าง:
```
Sprint Planning - 10-00_21-05-2026.m4a
Teams Meeting - 14-30_21-05-2026.m4a        ← ไม่พบ calendar event
Teams Call (Short) - 09-15_21-05-2026.m4a   ← call < 3 นาที
```

**Format:** `.m4a` container, AAC 96kbps, mono — system audio + microphone รวมกัน

---

## Configuration (`.env`)

> ไฟล์ `.env` อยู่ในโฟลเดอร์โปรเจกต์นี้ (สร้างโดย `make setup`)


```bash
RECORDING_DIR=~/Documents/Teams Recording   # โฟลเดอร์บันทึก
ICAL_BUDDY_PATH=                             # path ถ้า icalBuddy ไม่อยู่ใน PATH
RECORDER_BIN=                                # override path ของ binary (ปกติไม่ต้องกำหนด)
AUDIO_INPUT_DEVICE_UID=                      # UID ของ mic พิเศษ (headset, external mic)
```

ดู UID ของ mic ทั้งหมด:
```bash
recorder/recorder --list-devices
```

---

## Commands

| Command | Description |
|---------|-------------|
| `make run` | เริ่ม recorder — กด `1` เริ่มบันทึกเอง, `2` หยุด, `Q` ออก (ต้อง focus Terminal) |
| `make setup` | ติดตั้ง dependencies + ตั้งค่า `.env` |
| `make doctor` | ตรวจความพร้อมระบบ (permission, disk, binary) แบบ read-only |
| `make permissions` | เปิดหน้า System Settings สำหรับให้สิทธิ์ที่จำเป็น |
| `make stop` | หยุด watcher ที่กำลังทำงานอยู่ (อ่านจาก PID file) |
| `make index` | สร้าง `index.html` รวมรายการ recording ทั้งหมด |
| `make test` | รัน unit tests |
| `make build-recorder` | rebuild Swift binary (ต้องมี Xcode CLT) |
| `make menu-bar` | build menu bar app → `menu-bar/.build/TeamRecorderBar.app` (ครั้งแรก หรือย้าย repo) |
| `make menu-bar-install` | build + copy ไปที่ `/Applications/TeamRecorderBar.app` |

**Log & status:** บันทึก log รายวันที่ `~/Library/Logs/Team Recorder/` และเขียน
สถานะปัจจุบัน (`status.json`) ที่ `~/Library/Application Support/Team Recorder/`

---

## Rebuild Swift Binary

Binary (`recorder/recorder`) committed ไว้ใน repo แล้ว — ปกติไม่ต้อง build ใหม่

ต้อง rebuild เมื่อ: แก้ Swift source หรือ binary ไม่รันบนเครื่องนี้ (wrong arch)

```bash
# ต้องการ Xcode Command Line Tools
xcode-select --install   # ถ้ายังไม่ได้ติดตั้ง

make build-recorder
```

---

## How It Works

```
Teams meeting detected (UDP connections ≥ 4)
    ↓
Swift binary (recorder) เริ่มอัด system audio + mic ผ่าน ScreenCaptureKit
    ↓
ดึงชื่อ meeting จาก Apple Calendar ผ่าน icalBuddy
    ↓
[meeting in progress...]
    ↓
UDP drops → รอ 8s ยืนยัน (ป้องกัน false stop)
    ↓
หยุดอัด → ตั้งชื่อไฟล์ → บันทึกเป็น .m4a
```

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| ไม่เริ่มอัด | ตรวจสอบ Screen Recording permission ใน System Settings |
| ชื่อไฟล์เป็น "Teams Meeting" | Terminal ยังไม่ได้รับสิทธิ์ Calendar → System Settings → Privacy & Security → Calendars |
| `recorder binary เป็น arch ผิด` | รัน `make build-recorder` แล้ว commit `recorder/recorder` |
| เสียงไม่มี mic | ตรวจสอบ `AUDIO_INPUT_DEVICE_UID` ใน `.env` หรือลองใช้ default |
