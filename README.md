# Teams Auto-Recorder

บันทึกเสียง Microsoft Teams meeting อัตโนมัติ — ไม่ต้องกด Record เอง

เมื่อเข้า Teams call → เริ่มอัดเอง<br>
เมื่อออกจาก call → หยุดอัด ตั้งชื่อไฟล์ตามชื่อ meeting อัตโนมัติ (จาก calendar หรืออ่านจากหน้าจอ Teams ถ้า calendar ไม่มีชื่อให้)

---

## Requirements

- macOS 15 (Sequoia) ขึ้นไป
- สิทธิ์ **Screen Recording / Microphone / Calendar** — Setup Guide จะแนะนำทีละขั้นตอน (Calendar ข้ามได้ ถ้าองค์กรบล็อก calendar)
- **Architecture:** release build เป็น arm64 (Apple Silicon) หรือ x86_64 (Intel) ตาม build machine — ดาวน์โหลดให้ตรง arch ของเครื่อง

> **Older macOS (14 Sonoma):** v2.x ไม่รองรับ macOS 14 — ใช้ **v1.2.4** จาก [GitHub Releases](https://github.com/cjarit/team-recorder/releases) (สาย 1.2.x แก้เฉพาะ bug, branch `release/1.x`)

---

## การติดตั้ง

### วิธีที่ 1 — ดาวน์โหลดจาก GitHub Releases (แนะนำ)

> ไม่ต้องใช้ Terminal ไม่ต้อง Homebrew

1. ดาวน์โหลด **TeamRecorderBar-v2.0.0.dmg** จาก [GitHub Releases](https://github.com/cjarit/team-recorder/releases) (หรือ **TeamRecorderBar-v2.0.0.zip** ถ้าต้องการไฟล์ zip)
2. เปิดไฟล์ .dmg แล้ว **ลาก `TeamRecorderBar.app` ไปที่โฟลเดอร์ Applications** ในหน้าต่างเดียวกัน
3. เปิดครั้งแรก — macOS จะบล็อกแอป ให้ทำดังนี้
   1. พยายามเปิดแอป (จะถูกบล็อก)
   2. ไปที่ **System Settings → Privacy & Security**
   3. เลื่อนลงมา จะเห็น *"TeamRecorderBar was blocked"*
   4. กด **Open Anyway** → ใส่รหัสผ่าน

   > แอปนี้เซ็นด้วย certificate ของโปรเจกต์เอง แต่ไม่ได้ผ่าน Apple notarization (หลีกเลี่ยงค่า $99/ปี) — ขั้นตอนข้างต้นเป็น bypass มาตรฐานของ macOS ทำครั้งเดียว

4. **Setup Guide** จะขึ้นอัตโนมัติ — ให้สิทธิ์ตามขั้นตอน แล้วกด Finish

แอปพร้อมใช้งาน — มองหา icon ที่ **menu bar มุมขวาบนของจอ**

### อัปเกรดจากเวอร์ชันก่อนหน้า

- ทุก build เซ็นด้วย certificate คงที่ชื่อ **Team Recorder Signing** → ให้สิทธิ์ Screen Recording / Microphone / Calendar **ครั้งเดียว** แล้วอัปเกรดครั้งต่อ ๆ ไปสิทธิ์ยังอยู่
- แอปจัดการตัวเองตอนเปิดครั้งแรกหลังอัปเกรด (หยุด watcher ตัวเก่า) — **ตั้งค่าและไฟล์บันทึกไม่หาย**
- **จาก 1.2.4 → 2.0 ต้องให้สิทธิ์ใหม่อีก 1 ครั้งสุดท้าย:** macOS ยังแสดงแถว TeamRecorderBar เดิมในรายการ Screen Recording และติ๊กไว้ แต่ใช้งานไม่ได้แล้ว ให้ลบแถวนั้นด้วยปุ่ม **−** ใน System Settings → Privacy & Security → Screen Recording แล้วเพิ่มแอปกลับเข้าไปใหม่ (Setup Guide จะแสดงขั้นตอนนี้ให้เองอัตโนมัติ)

---

### วิธีที่ 2 — สำหรับ Developer (clone + build)

> ต้องการ Terminal + Homebrew + Xcode Command Line Tools

```bash
git clone https://github.com/cjarit/team-recorder
cd team-recorder
make setup
make cert                # ครั้งเดียวต่อเครื่อง: สร้าง certificate "Team Recorder Signing"
make menu-bar-install
```

หลัง `make cert` ให้รันคำสั่งนี้หนึ่งครั้ง (จะถามรหัสผ่าน login ของเครื่อง — พิมพ์เองใน Terminal) เพื่อให้ `codesign` ใช้ key ได้โดยไม่เด้งถามทุก build:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

> `make menu-bar` จะหยุดพร้อมข้อความ `run: make cert` ถ้ายังไม่มี certificate — ไม่ fallback ไป ad-hoc (ad-hoc ทำให้สิทธิ์หายทุก build)<br>
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

### คลิกซ้ายที่ icon = Popover (ใช้ประจำวัน)

Popover มี 4 สถานะ:

| สถานะ | เห็นอะไร | ทำอะไรได้ |
|-------|----------|-----------|
| **Recording** | ชื่อ meeting, เวลาที่อัดไปแล้ว, แถบระดับเสียงสด 2 แถบ — **Others** (เสียงอีกฝั่ง) และ **My mic** (เสียงเรา) | **Stop Recording** |
| **Ready** | "Recording starts when you join a Teams meeting." | **Start Recording Now** (เริ่มทันทีโดยไม่รอ Teams) |
| **Paused** | "Meetings won't be recorded." | **Start Watching** |
| **Error** | สาเหตุของ error (หรือ "Recorder Stopped Responding" เมื่อสถานะค้าง) | **Recover Recorder…** |

ด้านล่างของ Popover: **Last Recording** (คลิกเพื่อเปิดไฟล์ล่าสุดใน Finder), แถวสถานะ **Permissions** ทั้ง 3 (คลิก **Allow…** เพื่อไปให้สิทธิ์), **Open Recordings Folder**, **Open Team Recorder…**, **Quit Team Recorder**

ถ้าแถบ **My mic** ขึ้น "off" แปลว่าปิด *Record my voice* ไว้ใน General (ดูด้านล่าง) และถ้าไมค์ไม่ถูกบันทึกต่อเนื่อง 60 วินาทีระหว่างอัด จะมี notification แจ้ง

### คลิกขวาที่ icon = เมนู 5 รายการ

| รายการ | ทำอะไร |
|--------|---------|
| Open Team Recorder… | เปิดหน้าต่างหลัก (ดูด้านล่าง) |
| Pause Watching / Start Watching | หยุด/เริ่ม watcher (ระหว่าง Pause จะไม่อัด meeting) |
| Setup Guide… | เปิดหน้าต่าง setup step-by-step อีกครั้ง |
| Uninstall Team Recorder… | ถอนการติดตั้ง (ดูหัวข้อ Uninstall) |
| Quit | ปิดแอป |

### หน้าต่าง Team Recorder (Open Team Recorder…)

| Tab | มีอะไร |
|-----|--------|
| **Status** | ตรวจสถานะเหมือน `make doctor`: watcher, สถานะ, error ล่าสุด, recorder binary, พื้นที่ดิสก์ที่เหลือ, สิทธิ์ทั้ง 3, ไฟล์บันทึกล่าสุด (Show in Finder), เวอร์ชัน, ปุ่ม **Check for Updates** (ไม่โหลดเอง ไม่อัปเดตอัตโนมัติ — เปิดหน้า Release ให้) และปุ่ม Pause Watching / Recover Recorder… / Open Setup Guide… |
| **General** | โฟลเดอร์บันทึก (**Change…**), **Launch at Login**, แจ้งเตือนเมื่อบันทึกเสร็จ, กลุ่ม **Audio**: **Microphone** (Auto หรือเลือกไมค์เอง), สวิตช์ **Record my voice**, และลำโพงที่ใช้อยู่ (แสดงอย่างเดียว) |
| **Calendars** | เลือกว่าจะใช้ calendar ไหนตั้งชื่อ recording (**Select All**, **Refresh events**) |
| **Permissions** | สถานะ Screen Recording / Microphone / Calendar พร้อมปุ่มเปิด System Settings และสวิตช์ข้าม Calendar |

เปลี่ยนค่าใน Audio แล้ว watcher จะ restart ให้ — เปลี่ยนไมค์/สวิตช์ และโฟลเดอร์ไม่ได้ขณะกำลังบันทึก

**จัดการไฟล์ (เปลี่ยนชื่อ ลบ) ทำใน Finder** — แอปไม่มีรายการไฟล์ในตัวโดยตั้งใจ

**Setup Guide** — เปิดขึ้นอัตโนมัติครั้งแรกที่รันแอป แนะนำการให้สิทธิ์ทีละขั้นตอน:<br>
Screen Recording → Microphone → Calendar (ข้ามได้ ถ้าองค์กรบล็อก calendar — ชื่อไฟล์จะอ่านจากหน้าต่าง Teams แทน)<br>
เมื่อกด Finish แอปจะเริ่ม watcher ให้เลย

Screen Recording ต้อง relaunch แอปหลังเปิดสิทธิ์ตามข้อกำหนดของ macOS

**Launch at Login** — ต้องติดตั้งแอปไว้ที่ `/Applications/` ก่อน (`make menu-bar-install` สำหรับ developer)<br>
ถ้ากดแล้วไม่ work จะมี alert แจ้ง

---

## Output

ไฟล์บันทึกจะอยู่ที่ `~/Documents/Teams Recording/`<br>
(แก้ได้จาก Open Team Recorder… → General → Recordings folder → Change…)

ชื่อไฟล์ตัวอย่าง:
```
Sprint Planning - 10-00_21-05-2026.m4a
DX Lead Discuss & Operations - 11-00_21-05-2026.m4a  ← ไม่พบ calendar event แต่อ่านชื่อจากหน้าจอ Teams ได้
Teams Meeting - 14-30_21-05-2026.m4a        ← ไม่พบทั้ง calendar event และชื่อจากหน้าจอ
Teams Call (Short) - 09-15_21-05-2026.m4a   ← call < 3 นาที
```

**ลำดับการหาชื่อ meeting:** Calendar ก่อน → ถ้าไม่มีชื่อ ลองอ่านชื่อจากหน้าต่าง Teams ที่กำลัง call อยู่ (ต้องเห็น toolbar ของ meeting บนหน้าจอ ไม่ minimize) → ถ้ายังไม่มี ใช้ "Teams Meeting"

**Format:** `.m4a` container, AAC 32 kbps / 16 kHz, mono — system audio + microphone รวมกันเป็น track เดียวหลังจบแต่ละ meeting (~14 MB/ชั่วโมง, optimised สำหรับ NotebookLM / Whisper)

**เสียงของเรา (microphone):** เวอร์ชัน 2.0 อัดไมค์ผ่าน ScreenCaptureKit (ผ่าน stream เดียวกับ system audio) จึงไม่ค้างเมื่อใช้ headset Bluetooth สลับโหมดตอนเข้า/ออก call และตำแหน่งของเสียงสองฝั่งอ้างอิงนาฬิกาจริง ไม่เพี้ยนสะสมจนฟังเป็นเสียงสะท้อน ถ้าใช้ลำโพง เสียงอีกฝั่งอาจเล็ดเข้าไมค์ — ตอนรวม track แอปตรวจเจอและลดเสียงไมค์ลงในช่วงที่อีกฝั่งพูด (คำพูดแทรกสั้น ๆ ของเราในช่วงนั้นจะเบาลง) ใช้หูฟังจะได้ผลดีที่สุด

**ไฟล์ที่ไม่มีเสียงพูด:** ไฟล์ที่ยาว **3 นาทีขึ้นไป** และตรวจแล้วไม่มีเสียงพูดเลย จะถูก **ย้าย** (ไม่ลบ) ไปโฟลเดอร์ย่อย `Empty/` ในโฟลเดอร์บันทึก พร้อม notification "No speech detected — moved to Empty" ถ้าย้ายผิด ลากไฟล์กลับออกมาจาก `Empty/` ใน Finder ได้เลย ไฟล์ call สั้นกว่า 3 นาที ("Teams Call (Short)") ไม่ถูกย้าย

ข้าง ๆ ไฟล์เสียงอาจเห็นไฟล์ `.meta.json` — เป็นข้อมูลภายในของแอปที่ใช้ตัดสินเรื่องด้านบน

---

## Configuration

> **สำหรับผู้ใช้ทั่วไป:** แก้โฟลเดอร์บันทึก ไมค์ และ Record my voice ได้จาก Open Team Recorder… → General ไม่ต้องแก้ไฟล์โดยตรง

ไฟล์ config (`~/Library/Application Support/Team Recorder/.env`) สร้างอัตโนมัติตอน setup

```bash
RECORDING_DIR=~/Documents/Teams Recording   # โฟลเดอร์บันทึก
ICAL_BUDDY_PATH=                             # path ถ้า icalBuddy ไม่อยู่ใน PATH (developer path เท่านั้น)
RECORDER_BIN=                                # override path ของ binary (ปกติไม่ต้องกำหนด)
AUDIO_INPUT_DEVICE_UID=                      # UID ของ mic พิเศษ (headset, external mic) — ตั้งจาก General → Microphone ได้
RECORD_MIC=1                                 # 0 = อัดเฉพาะ system audio (ตรงกับสวิตช์ Record my voice)
MIC_PATH=                                    # engine = กลับไปใช้ AVAudioEngine แบบเดิมของ v1.2.x (เก็บไว้อีก 1 release)
SKIP_MIXDOWN=                                # 1 = เก็บไฟล์ 2 track ไว้ ไม่รวมเป็น track เดียว (สำหรับ debug)
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
| `make cert` | ครั้งเดียวต่อเครื่อง: สร้าง certificate "Team Recorder Signing" ใน login keychain (idempotent) |
| `make cert-check` | ตรวจว่ามี signing identity แล้ว |
| `make build-recorder` | rebuild Swift binary (ต้องมี Xcode CLT) แล้ว sign ด้วย identity เดียวกัน |
| `make menu-bar` | build menu bar app → `menu-bar/.build/TeamRecorderBar.app` (หยุดถ้ายังไม่มี certificate) |
| `make menu-bar-install` | build + copy ไปที่ `/Applications/TeamRecorderBar.app` |
| `make dmg` | สร้าง `dist/TeamRecorderBar-v$(VERSION).dmg` (app + ลิงก์ Applications) |
| `make release` | สร้างทั้ง `.zip` และ `.dmg` ใน `dist/` พร้อม SHA256 (สำหรับ GitHub Release) |
| `make uninstall` | ถอนการติดตั้งผ่าน Terminal: หยุด watcher, ลบ app, ล้าง preferences + runtime state |
| `make clean-reinstall` | uninstall แล้ว menu-bar-install ใหม่ในขั้นตอนเดียว |

**Log & status:** บันทึก log รายวันที่ `~/Library/Logs/Team Recorder/` และเขียนสถานะปัจจุบัน (`status.json`) รวมถึง PID watcher/recorder ที่ `~/Library/Application Support/Team Recorder/`

---

## How It Works

```
Teams meeting detected (UDP connections ≥ 4)
    ↓
Swift binary (recorder) เริ่มอัด system audio + mic ผ่าน ScreenCaptureKit (stream เดียว)
    ↓
ดึงชื่อ meeting จาก Apple Calendar ผ่าน CalendarEventBridge
    ↓
[meeting in progress...]
    ↓
UDP drops → รอ 8s ยืนยัน (ป้องกัน false stop)
    ↓
หยุดอัด → ตั้งชื่อไฟล์ → รวม track เป็นเสียงเดียว → บันทึกเป็น .m4a
```

---

## Uninstall

**สำหรับผู้ใช้ทั่วไป (ไม่มี Terminal):**

1. คลิกขวาที่ menu bar icon → **Uninstall Team Recorder…** → กดยืนยัน
2. แอปจะหยุด watcher, เปิดโฟลเดอร์บันทึกใน Finder, ย้ายตัวแอปไปถังขยะ แล้วปิดตัวเอง — **ไฟล์บันทึกและการตั้งค่าไม่ถูกลบ**
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
| อัปเกรดจาก 1.2.x แล้ว Screen Recording ยังติ๊กอยู่แต่ไม่อัด | แถว TeamRecorderBar เดิมใช้ไม่ได้แล้ว: System Settings → Privacy & Security → Screen Recording → เลือกแถว TeamRecorderBar → กด **−** → กด **+** เลือก `/Applications/TeamRecorderBar.app` → เปิดสวิตช์ → Relaunch App (ทำครั้งเดียว) |
| Setup Guide ไม่ขึ้น | คลิกขวาที่ menu bar icon → Setup Guide… |
| ไฟล์หายไปจากโฟลเดอร์บันทึก | เช็คโฟลเดอร์ย่อย `Empty/` — ไฟล์ยาว ≥ 3 นาทีที่ไม่มีเสียงพูดจะถูกย้ายไปที่นั่น (ไม่ลบ) ลากกลับออกมาได้ |
| แถบ My mic ใน Popover ขึ้น "off" | ปิด Record my voice ไว้: Open Team Recorder… → General → เปิดสวิตช์ Record my voice |
| ชื่อไฟล์เป็น "Teams Meeting" | Team Recorder ยังไม่ได้รับสิทธิ์ Calendar → เปิด Setup Guide… แล้วให้สิทธิ์ Calendar / Full Access. ถ้าองค์กรบล็อกการ sync/publish calendar (ไม่มีสิทธิ์ Calendar ให้ตั้งค่า) — เช็คว่า Screen Recording permission เปิดอยู่ และหน้าต่าง Teams meeting ไม่ได้ minimize ตอนอัด (ระบบจะลองอ่านชื่อจากหน้าจอแทน) |
| icon แดงค้าง / Stop แล้วนิ่ง | คลิกซ้ายที่ menu bar icon → Recover Recorder… แล้วเริ่ม watcher ใหม่ |
| macOS แจ้งเตือน "ไม่รู้จักผู้พัฒนา" หรือ "TeamRecorderBar was blocked" | System Settings → Privacy & Security → Open Anyway |
| Setup แจ้ง "App bundle is corrupted" | ลบแอปแล้ว re-download จาก GitHub Releases อีกครั้ง |
| Setup แจ้ง "Python 3.9+ required" | เปิด Terminal แล้วรัน `xcode-select --install` |

ดูรายละเอียดเพิ่มเติม: [docs/user/troubleshooting.md](docs/user/troubleshooting.md)<br>
คำถามที่พบบ่อย: [docs/user/faq.md](docs/user/faq.md)

---

## Legal & Consent Notice

**Recording consent is your responsibility.**

This tool records system audio from your device. In most jurisdictions — including Thailand under the Personal Data Protection Act B.E. 2562 (PDPA) — recording a conversation that includes other participants requires their prior consent. Recording without consent may violate the PDPA, the Computer Crimes Act B.E. 2550, your organisation's policies, and Microsoft's Terms of Service.

Before using this tool to record any meeting:

1. Inform all participants that the meeting will be recorded.
2. Obtain their consent before recording begins.
3. Store and handle recordings in accordance with applicable data protection law.

The authors of this software accept no liability for recordings made without proper consent.

---

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by Microsoft Corporation. "Microsoft Teams" is a trademark of Microsoft Corporation.
