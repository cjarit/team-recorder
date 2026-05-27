# Teams Auto-Recorder

บันทึกเสียง Microsoft Teams meeting อัตโนมัติ — ไม่ต้องกด Record เอง

เมื่อเข้า Teams call → เริ่มอัดเอง<br>
เมื่อออกจาก call → หยุดอัด ตั้งชื่อไฟล์ตาม calendar อัตโนมัติ

---

## Requirements

- macOS 14 (Sonoma) ขึ้นไป
- สิทธิ์ **Screen Recording / Microphone / Calendar** — Setup Guide จะแนะนำทีละขั้นตอน
- **Architecture:** release build เป็น arm64 (Apple Silicon) หรือ x86_64 (Intel) ตาม build machine — ดาวน์โหลดให้ตรง arch ของเครื่อง

---

## การติดตั้ง

### วิธีที่ 1 — ดาวน์โหลด .app จาก GitHub Releases (แนะนำ)

> ไม่ต้องใช้ Terminal ไม่ต้อง Homebrew

1. ดาวน์โหลด **TeamRecorderBar-v1.0.0.zip** จาก [GitHub Releases](https://github.com/cjarit/team-recorder/releases)
2. แตกไฟล์ zip แล้ว **ลาก `TeamRecorderBar.app` ไปไว้ที่ `/Applications/`**
3. เปิดครั้งแรก — **คลิกขวา → Open** (ไม่ใช่ดับเบิลคลิก)

   > **ทำไมต้องคลิกขวา?** macOS จะแสดงคำเตือน "ไม่รู้จักผู้พัฒนา" เพราะแอปนี้ไม่ได้ผ่าน Apple notarization<br>
   > คลิกขวา → เลือก **Open** → กด **Open** ในหน้าต่างที่ขึ้นมา ทำครั้งเดียว<br>
   > ครั้งต่อไปดับเบิลคลิกได้ตามปกติ

4. **Setup Guide** จะขึ้นอัตโนมัติ — ให้สิทธิ์ทั้ง 3 ขั้นตอน แล้วกด Finish

แอปพร้อมใช้งาน — มองหา icon ที่ **menu bar มุมขวาบนของจอ**

---

### วิธีที่ 2 — สำหรับ Developer (clone + build)

> ต้องการ Terminal + Homebrew

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
make setup
make menu-bar-install
```

> ถ้า Setup Guide ไม่ขึ้น รัน: `make reset-setup` แล้วเปิดแอปใหม่

---

## การใช้งานประจำวัน

1. เปิด **Team Recorder** จาก `/Applications/` (หรือเปิดอัตโนมัติถ้าเปิด Launch at Login)
2. เข้า Teams meeting — การบันทึกเริ่มอัตโนมัติ
3. ออกจาก meeting — ไฟล์จะถูกตั้งชื่อตาม calendar event และบันทึกที่ `~/Documents/Teams Recording/`

ดูรายละเอียดเพิ่มเติม: [docs/user/daily-use.md](docs/user/daily-use.md)

---

## Menu Bar App

เมื่อ **Team Recorder** เปิดอยู่ จะเห็น icon ที่ menu bar ด้านขวาบน:

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
| Recover Recorder… | เคลียร์สถานะค้างเมื่อ watcher/recorder crash |
| Stop / Start Watcher | เปิด/ปิด watcher process |
| 📁 Recordings Folder ▶ | ดู path ปัจจุบัน, Open Folder, **Change Folder…** |
| Last: … | คลิกเพื่อเปิดไฟล์ล่าสุดใน Finder |
| Permissions ▶ | เปิด System Settings → Screen Recording / Microphone / Calendar |
| Setup Guide… | เปิดหน้าต่าง setup step-by-step อีกครั้ง |
| Launch at Login | เปิด/ปิดการเริ่มต้นอัตโนมัติเมื่อ login |

**Change Folder…** จะอัปเดต `RECORDING_DIR` ใน `.env` แล้ว restart watcher อัตโนมัติ<br>
(ปุ่มนี้จะ disable ขณะกำลังบันทึก)

**Setup Guide** — เปิดขึ้นอัตโนมัติครั้งแรกที่รันแอป แนะนำการให้สิทธิ์ทีละขั้นตอน:<br>
Screen Recording → Microphone → Calendar<br>
เมื่อกด Finish แอปจะเริ่ม watcher ให้เลย

Screen Recording ต้อง relaunch แอปหลังเปิดสิทธิ์ตามข้อกำหนดของ macOS

**Launch at Login** — ต้องติดตั้งแอปไว้ที่ `/Applications/` ก่อน (`make menu-bar-install` สำหรับ developer)<br>
ถ้ากดแล้วไม่ work จะมี alert แจ้ง

---

## Output

ไฟล์บันทึกจะอยู่ที่ `~/Documents/Teams Recording/`<br>
(แก้ได้จาก menu bar → 📁 Recordings Folder → Change Folder…)

ชื่อไฟล์ตัวอย่าง:
```
Sprint Planning - 10-00_21-05-2026.m4a
Teams Meeting - 14-30_21-05-2026.m4a        ← ไม่พบ calendar event
Teams Call (Short) - 09-15_21-05-2026.m4a   ← call < 3 นาที
```

**Format:** `.m4a` container, AAC 96kbps, mono — system audio + microphone รวมกัน

---

## Configuration

> **สำหรับผู้ใช้ทั่วไป:** แก้โฟลเดอร์บันทึกได้จาก menu bar → 📁 Recordings Folder → Change Folder… ไม่ต้องแก้ไฟล์โดยตรง

ไฟล์ config (`~/Library/Application Support/Team Recorder/.env`) สร้างอัตโนมัติตอน setup

```bash
RECORDING_DIR=~/Documents/Teams Recording   # โฟลเดอร์บันทึก
ICAL_BUDDY_PATH=                             # path ถ้า icalBuddy ไม่อยู่ใน PATH (developer path เท่านั้น)
RECORDER_BIN=                                # override path ของ binary (ปกติไม่ต้องกำหนด)
AUDIO_INPUT_DEVICE_UID=                      # UID ของ mic พิเศษ (headset, external mic)
```

ดู UID ของ mic ทั้งหมด (สำหรับ developer):
```bash
recorder/recorder --list-devices
```

---

## Commands (Developer)

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
| `make menu-bar` | build menu bar app → `menu-bar/.build/TeamRecorderBar.app` |
| `make menu-bar-install` | build + copy ไปที่ `/Applications/TeamRecorderBar.app` |
| `make release` | สร้าง `dist/TeamRecorderBar-v1.0.0.zip` พร้อม SHA256 (สำหรับ GitHub Release) |
| `make uninstall` | ถอนการติดตั้ง: หยุด watcher, ลบ app, ล้าง preferences + runtime state |
| `make clean-reinstall` | uninstall แล้ว menu-bar-install ใหม่ในขั้นตอนเดียว |

**Log & status:** บันทึก log รายวันที่ `~/Library/Logs/Team Recorder/` และเขียนสถานะปัจจุบัน (`status.json`) รวมถึง PID watcher/recorder ที่ `~/Library/Application Support/Team Recorder/`

---

## How It Works

```
Teams meeting detected (UDP connections ≥ 4)
    ↓
Swift binary (recorder) เริ่มอัด system audio + mic ผ่าน ScreenCaptureKit
    ↓
ดึงชื่อ meeting จาก Apple Calendar ผ่าน CalendarEventBridge
    ↓
[meeting in progress...]
    ↓
UDP drops → รอ 8s ยืนยัน (ป้องกัน false stop)
    ↓
หยุดอัด → ตั้งชื่อไฟล์ → บันทึกเป็น .m4a
```

---

## Uninstall

**สำหรับผู้ใช้ทั่วไป (ไม่มี Terminal):**

1. คลิก menu bar icon → **Quit**
2. ลาก `/Applications/TeamRecorderBar.app` ไปถังขยะ
3. ยกเลิกสิทธิ์ใน System Settings (ดูตารางด้านล่าง)

**สำหรับ developer (ใช้ make):**

```bash
make uninstall
```

ลบ: app, preferences, runtime state (`status.json`, PID files)<br>
**ไม่ลบ:** ไฟล์บันทึกใน `~/Documents/Teams Recording/`

หลัง uninstall ให้ยกเลิกสิทธิ์ใน System Settings ด้วยตัวเอง (macOS ไม่อนุญาตให้ทำโดย API):

| Permission | วิธียกเลิก |
|------------|-----------|
| Screen Recording | System Settings → Privacy & Security → Screen Recording → TeamRecorderBar → click **−** |
| Microphone | System Settings → Privacy & Security → Microphone → TeamRecorderBar → toggle off |
| Calendar | System Settings → Privacy & Security → Calendars → TeamRecorderBar → **None** |

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|-------|---------|
| ไม่เริ่มอัด | เปิด Setup Guide… → Step 1 Screen Recording → ให้สิทธิ์แล้ว Relaunch App |
| Setup Guide ไม่ขึ้น | คลิก menu bar icon → Setup Guide… |
| ชื่อไฟล์เป็น "Teams Meeting" | Team Recorder ยังไม่ได้รับสิทธิ์ Calendar → เปิด Setup Guide… แล้วให้สิทธิ์ Calendar / Full Access |
| icon แดงค้าง / Stop แล้วนิ่ง | คลิก menu bar icon → Recover Recorder… แล้วเริ่ม watcher ใหม่ |
| macOS แจ้งเตือน "ไม่รู้จักผู้พัฒนา" | คลิกขวา → Open → Open (ทำครั้งเดียว) |
| Setup แจ้ง "App bundle is corrupted" | ลบแอปแล้ว re-download จาก GitHub Releases อีกครั้ง |
| Setup แจ้ง "Python 3.9+ required" | เปิด Terminal แล้วรัน `xcode-select --install` |

ดูรายละเอียดเพิ่มเติม: [docs/user/troubleshooting.md](docs/user/troubleshooting.md)<br>
คำถามที่พบบ่อย: [docs/user/faq.md](docs/user/faq.md)
