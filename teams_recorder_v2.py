#!/usr/bin/env python3
"""
Teams Meeting Auto-Recorder v2
ตรวจ Teams meeting ผ่าน UDP → auto start/stop Swift binary (recorder)
ไม่ต้องใช้ OBS — binary อยู่ใน repo แล้ว (recorder/recorder)

Requirements: pip3 install python-dotenv
"""

import atexit
import json
import re
import select
import shutil
import subprocess
import signal
import sys
import os
import termios
import time
import tty
import platform
from datetime import datetime, timedelta
from typing import Optional

from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.expanduser(os.getenv("ENV_FILE", os.path.join(BASE_DIR, ".env")))
load_dotenv(ENV_FILE)

# ─── Config ──────────────────────────────────────────────────
# ค่าเหล่านี้ tuned จากการทดสอบจริง — ห้ามเปลี่ยนโดยไม่มีเหตุผล
RECORDING_DIR   = os.path.expanduser(os.getenv("RECORDING_DIR",
                                                "~/Documents/Teams Recording"))
POLL_INTERVAL   = 3    # วินาที (ลดจาก 5 → detect เร็วขึ้น)
STOP_GRACE      = 8    # วินาทีรอก่อน confirm meeting จบ (ป้องกัน false stop จาก UDP หลุดชั่วคราว)
MIN_DURATION    = 180  # วินาที — ต่ำกว่านี้ = accidental call
UDP_MEET_THRESH = 4    # established UDP ขั้นต่ำที่ถือว่า in meeting
                       # background Teams = 1-2 เส้น, meeting = 4+ (RTP/STUN/TURN)
# Calendar matching tolerance อยู่ใน find_matching_meeting (±5 นาที interval slack)
ICAL_BUDDY = (
    os.getenv("ICAL_BUDDY_PATH")
    or shutil.which("icalBuddy")
    or "/opt/homebrew/bin/icalBuddy"
)
# ─────────────────────────────────────────────────────────────

# OBS_PASSWORD ใน .env ไม่ได้ใช้ใน v2 — แจ้งครั้งเดียวตอนเริ่ม
if os.getenv("OBS_PASSWORD"):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] "
          "[INFO] OBS_PASSWORD ใน .env ไม่ได้ใช้ใน v2 — ข้ามได้")

_pid_cache: str = ""
_meetings_cache: dict = {"date": None, "ts": 0.0, "meetings": []}  # 10-min TTL cache

# ─── Operability paths ───────────────────────────────────────
# log → ~/Library/Logs ; status + pid → ~/Library/Application Support
LOG_DIR         = os.path.expanduser("~/Library/Logs/Team Recorder")
APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/Team Recorder")
STATUS_FILE     = os.path.join(APP_SUPPORT_DIR, "status.json")
PID_FILE        = os.path.join(APP_SUPPORT_DIR, "team-recorder.pid")
NOTIFY_ENABLED  = False  # main() ตั้งเป็น True — unit test ที่เรียกฟังก์ชันตรง ๆ จะเงียบ

# ─── Signal flags (SIGUSR1 = manual start, SIGUSR2 = manual stop) ────────────
# ตั้งค่าโดย signal handler (async-signal-safe) — main loop อ่านและ clear
_sig_start_requested: bool = False
_sig_stop_requested:  bool = False

# ─── Teams detection ─────────────────────────────────────────
# คัดลอกจาก v1 ทั้งหมด — อย่าแก้ไข

def get_teams_pid() -> str:
    """ดึง PID ของ MSTeams แล้ว cache ไว้ — ไม่ต้อง pgrep ทุกรอบ"""
    global _pid_cache
    if _pid_cache:
        r = subprocess.run(["kill", "-0", _pid_cache], capture_output=True)
        if r.returncode == 0:
            return _pid_cache
    r = subprocess.run(["pgrep", "-x", "MSTeams"], capture_output=True, text=True)
    _pid_cache = r.stdout.strip().split("\n")[0]
    return _pid_cache


def is_teams_in_meeting() -> bool:
    """
    ตรวจ established UDP connections ของ Teams เท่านั้น
    - -nP  : ข้าม DNS + port name lookup (เร็วขึ้นมาก)
    - -a -p: filter เฉพาะ PID นั้น ไม่ต้อง scan ทุก process
    """
    pid = get_teams_pid()
    if not pid:
        return False
    try:
        result = subprocess.run(
            ["lsof", "-nP", "-i", "udp", "-a", "-p", pid],
            capture_output=True, text=True, timeout=5
        )
        count = sum(
            1 for line in result.stdout.splitlines()[1:]  # skip header
            if "*:" not in line  # ไม่ใช่ listening port → established
        )
        return count >= UDP_MEET_THRESH
    except Exception as e:
        log(f"[WARN] Meeting check error: {e}")
        return False


# ─── Calendar helpers ─────────────────────────────────────────
# คัดลอกจาก v1 ทั้งหมด — อย่าแก้ไข

def get_today_meetings() -> list:
    """ดึง meeting วันนี้ผ่าน icalBuddy — อ่าน EventKit store โดยตรง
    ไม่ผ่าน Calendar app → ไม่มีปัญหา -600 / timeout
    Returns: [{"time": datetime, "name": str}, ...]
    """
    import re as _re
    if not os.path.exists(ICAL_BUDDY):
        return []  # U5: ไม่ log ซ้ำ — startup warning เตือนไปแล้ว
    try:
        result = subprocess.run(
            [ICAL_BUDDY, "-f", "-nc", "-iep", "title,datetime",
             "-b", "||", "-tf", "%H:%M", "-nrd", "eventsToday"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0 or not result.stdout.strip():
            log("[INFO] icalBuddy: ไม่มี event วันนี้")
            return []

        meetings = []
        today = datetime.now().date()
        current_name = None

        # strip ANSI color codes (icalBuddy ใส่มาเสมอแม้ใช้ -f)
        ansi_clean = _re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
        for raw in ansi_clean.splitlines():
            line = raw.strip()
            if not line:
                continue
            if line.startswith("||"):
                # บรรทัดชื่อ event
                current_name = line[2:].strip()
            else:
                # บรรทัดเวลา: "10:00 - 11:00" หรือ "10:00"
                m = _re.match(r"(\d{2}:\d{2})(?:\s*-\s*(\d{2}:\d{2}))?", line)
                if m and current_name:
                    start_t = datetime.strptime(m.group(1), "%H:%M")
                    end_t   = datetime.strptime(m.group(2), "%H:%M") if m.group(2) else None
                    meetings.append({
                        "start": datetime.combine(today, start_t.time()),
                        "end":   datetime.combine(today, end_t.time()) if end_t else None,
                        "name":  current_name,
                    })
                    current_name = None

        log(f"[INFO] icalBuddy: พบ {len(meetings)} event วันนี้")
        return meetings

    except subprocess.TimeoutExpired:
        log("[WARN] icalBuddy timeout — ใช้ชื่อ fallback")
        return []
    except Exception as e:
        log(f"[WARN] icalBuddy failed: {e}")
        return []


def _get_today_meetings_cached() -> list:
    """Cache get_today_meetings() with 10-min TTL — stale if meeting renamed/added during day."""
    today = datetime.now().strftime("%Y-%m-%d")
    now   = time.time()
    if (_meetings_cache["date"] == today
            and now - _meetings_cache["ts"] < 600):   # 600 s = 10 min
        return _meetings_cache["meetings"]
    _meetings_cache["date"]     = today
    _meetings_cache["ts"]       = now
    _meetings_cache["meetings"] = get_today_meetings()
    return _meetings_cache["meetings"]


def find_matching_meeting(start_time: datetime, meetings: list) -> "str | None":
    """หา meeting ที่ start_time อยู่ใน event interval (±5 min tolerance)
    ใช้ event end time — รองรับการ join ช้าในการประชุมยาว
    Returns: meeting name หรือ None ถ้าไม่พบ
    """
    best_name  = None
    best_diff  = float("inf")
    tolerance  = timedelta(minutes=5)

    for m in meetings:
        ev_start = m["start"]
        ev_end   = m.get("end") or (ev_start + timedelta(hours=1))  # fallback 1h
        inside   = (ev_start - tolerance) <= start_time <= (ev_end + tolerance)
        diff     = abs((start_time - ev_start).total_seconds())
        if inside and diff < best_diff:
            best_name = m["name"]
            best_diff = diff

    if best_name:
        log(f"[INFO] Calendar match: '{best_name}' (diff {best_diff/60:.1f} min)")
    return best_name


def sanitize_filename(name: str) -> str:
    """ลบ character ที่ใช้ใน filename ไม่ได้ + จำกัดความยาว"""
    name = re.sub(r'[/\\:*?"<>|]', "", name)
    name = name.strip(". ")
    name = name[:80].strip()
    return name or "Teams Meeting"


# ─── Rename helpers ───────────────────────────────────────────

def _rename_as_incomplete(session: dict):
    """Rename recording to INCOMPLETE_* when binary crashes or finishWriting fails.
    Reusable by both the crash path and the STOPPED_ERROR protocol path.
    """
    src           = session.get("recording_path", "")
    recording_dir = session.get("recording_dir", RECORDING_DIR)
    try:
        if os.path.exists(src) and os.path.getsize(src) > 0:
            ts_crash = session["start_time"].strftime("%H-%M_%d-%m-%Y")
            dest = os.path.join(recording_dir, f"INCOMPLETE_{ts_crash}.m4a")
            part = 2
            while os.path.exists(dest) and part <= 99:
                dest = os.path.join(recording_dir,
                                    f"INCOMPLETE_{ts_crash}_part{part}.m4a")
                part += 1
            if os.path.exists(dest):
                # part1-99 all taken — fall back to wall-clock timestamp with collision check
                ts_now = datetime.now().strftime("%H-%M-%S_%d-%m-%Y")
                dest = os.path.join(recording_dir, f"INCOMPLETE_{ts_now}.m4a")
                part = 2
                while os.path.exists(dest) and part <= 99:
                    dest = os.path.join(recording_dir,
                                        f"INCOMPLETE_{ts_now}_part{part}.m4a")
                    part += 1
            os.rename(src, dest)
            log(f"[WARN] บันทึกบางส่วน: {os.path.basename(dest)}")
            return dest
    except Exception as e:
        log(f"[WARN] ย้าย partial file ไม่ได้: {e}")
    return None


def rename_recording(session: dict, duration_secs: float):
    """Rename recording ที่รู้ path แน่นอนแล้วเป็น [Meeting Name] - HH-MM_DD-MM-YYYY.m4a

    สถานการณ์ที่ handle:
    - ✅ มี calendar event ตรงเวลา       → ใช้ชื่อ event
    - ⚡ Recording < MIN_DURATION วินาที → 'Teams Call (Short)' (accidental)
    - ❓ ไม่มี event ตรงเวลา             → 'Teams Meeting' (fallback)
    - 🔄 ชื่อไฟล์ซ้ำ (disconnect/rejoin) → ต่อท้าย _part2, _part3 ...

    Returns: path สุดท้ายของไฟล์ที่ rename แล้ว หรือ None ถ้าล้มเหลว
    """
    try:
        src = session["recording_path"]
        if not os.path.exists(src):
            log(f"[WARN] ไม่พบ recording file: {src}")
            return None

        start_time    = session["start_time"]
        recording_dir = session["recording_dir"]
        _, ext        = os.path.splitext(src)  # .m4a

        # timestamp format: HH-MM_DD-MM-YYYY
        ts = start_time.strftime("%H-%M_%d-%m-%Y")

        # ─── ตัดสินใจชื่อ meeting ─────────────────────────────
        matched = session.get("meeting_name")
        if matched:
            # มีชื่อจาก calendar → ใช้เลย ไม่สนว่า recording จะสั้นแค่ไหน
            meeting_name = matched
            if duration_secs < MIN_DURATION:
                log(f"[INFO] Recording {duration_secs:.0f}s (short) แต่มีชื่อ calendar → ใช้ชื่อ meeting")
        elif duration_secs < MIN_DURATION:
            # ไม่มีชื่อ + สั้น → accidental call
            meeting_name = "Teams Call (Short)"
            log(f"[INFO] Recording {duration_secs:.0f}s < {MIN_DURATION}s → accidental call")
        else:
            meeting_name = "Teams Meeting"
            log("[WARN] ไม่มีชื่อ meeting จาก calendar → ใช้ชื่อ fallback")

        clean_name = sanitize_filename(meeting_name)
        base_name  = f"{clean_name} - {ts}{ext}"
        new_path   = os.path.join(recording_dir, base_name)

        # ─── จัดการ part numbering (disconnect แล้ว rejoin) ──
        # Q1: cap ที่ 99 ป้องกัน infinite loop ถ้าไฟล์เก่าสะสมเยอะมาก
        if os.path.exists(new_path):
            part = 2
            found = False
            while part <= 99:
                candidate = os.path.join(
                    recording_dir, f"{clean_name} - {ts}_part{part}{ext}"
                )
                if not os.path.exists(candidate):
                    new_path = candidate
                    found = True
                    break
                part += 1
            if not found:
                # เกิน 99 parts → ใช้ epoch timestamp เป็น suffix แทน
                suffix = int(time.time())
                new_path = os.path.join(recording_dir,
                                        f"{clean_name} - {ts}_{suffix}{ext}")
                log("[WARN] part numbering เกิน 99 → ใช้ timestamp suffix")
            else:
                log(f"[INFO] ไฟล์ชื่อเดิมมีอยู่แล้ว → บันทึกเป็น part {part}")

        os.rename(src, new_path)
        log(f"💾 บันทึกเป็น: {new_path}")  # P2-D: แสดง full path
        # ไม่มี compress_recording() — binary เขียน AAC 96kbps อยู่แล้ว
        return new_path

    except Exception as e:
        log(f"[ERROR] Rename failed: {e}")
        return None


# ─── Post-recording validation ────────────────────────────────

MIN_VALID_BYTES = 8 * 1024   # ต่ำกว่านี้ = ไฟล์เสีย/ตัดกลางคัน (AAC 96k ≈ 12KB/วินาที)


def read_audio_duration(path: str) -> "float | None":
    """อ่านความยาวเสียง (วินาที) ด้วย afinfo — built-in macOS ไม่ต้องลง dependency
    Returns: วินาที หรือ None ถ้าอ่านไม่ได้ (afinfo หาย / ไฟล์เปิดไม่ได้)
    """
    try:
        r = subprocess.run(["afinfo", path],
                           capture_output=True, text=True, timeout=10)
    except (FileNotFoundError, subprocess.SubprocessError, OSError):
        return None
    if r.returncode != 0:
        return None
    m = re.search(r"estimated duration:\s*([\d.]+)\s*sec", r.stdout)
    return float(m.group(1)) if m else None


def validate_recording(path: str) -> "tuple[bool, str]":
    """ตรวจไฟล์หลัง STOPPED_OK — ไฟล์มีจริง, ขนาดสมเหตุผล, เปิดอ่าน duration ได้
    Returns: (ok, reason). ok=False เฉพาะเมื่อมีหลักฐานว่าไฟล์เสียจริง ๆ —
    ถ้า afinfo เองใช้ไม่ได้จะถือว่าผ่าน (ไม่ false-flag ไฟล์ที่อาจดีอยู่)
    """
    if not os.path.exists(path):
        return False, "ไฟล์หาย"
    size = os.path.getsize(path)
    if size < MIN_VALID_BYTES:
        return False, f"ไฟล์เล็กผิดปกติ ({size} bytes)"
    dur = read_audio_duration(path)
    if dur is None:
        return True, "ข้ามตรวจ duration (afinfo อ่านไม่ได้)"
    if dur < 0.5:
        return False, f"duration ใกล้ศูนย์ ({dur:.2f}s)"
    return True, f"{dur:.0f}s"


def _rename_as_needs_check(path: str, reason: str) -> str:
    """เติม prefix NEEDS_CHECK_ ให้ไฟล์ที่ผ่าน STOPPED_OK แต่ validate ไม่ผ่าน
    ไม่ลบไฟล์ — แค่ mark ไว้ให้ผู้ใช้ตรวจเอง
    Returns: path ใหม่ (หรือ path เดิมถ้าย้ายไม่ได้)
    """
    try:
        d, base = os.path.split(path)
        dest = os.path.join(d, f"NEEDS_CHECK_{base}")
        n = 2
        while os.path.exists(dest) and n <= 99:
            dest = os.path.join(d, f"NEEDS_CHECK_{n}_{base}")
            n += 1
        os.rename(path, dest)
        log(f"[WARN] validate ไม่ผ่าน ({reason}) → {os.path.basename(dest)}")
        return dest
    except Exception as e:
        log(f"[WARN] เปลี่ยนชื่อเป็น NEEDS_CHECK ไม่ได้: {e}")
        return path


# ─── Util ─────────────────────────────────────────────────────

def log(msg: str):
    """พิมพ์ออก stdout + append ลง daily log file (~/Library/Logs/Team Recorder)
    การเขียนไฟล์เป็น best-effort — เขียนไม่ได้ก็ไม่กระทบการทำงาน
    """
    line = f"[{datetime.now().strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        log_path = os.path.join(
            LOG_DIR, f"team-recorder-{datetime.now():%Y-%m-%d}.log")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


# ─── Notifications & status file ──────────────────────────────

def _notify_on() -> bool:
    """NOTIFY env: ปิดได้ด้วย 0/false/no/off — ค่า default = เปิด"""
    return os.getenv("NOTIFY", "1").strip().lower() not in (
        "0", "false", "no", "off", "")


def notify(title: str, message: str):
    """macOS notification ผ่าน osascript — best-effort
    - ส่ง title/message เป็น argv ของ osascript → ไม่มี script injection จากชื่อ meeting
    - มี timeout + กลืน exception ทุกชนิด → ไม่มีทาง block การอัด
    - NOTIFY_ENABLED ตั้งโดย main() เท่านั้น → unit test จะไม่เด้ง notification จริง
    """
    if not NOTIFY_ENABLED or not _notify_on():
        return
    try:
        subprocess.run(
            ["osascript",
             "-e", "on run argv",
             "-e", "display notification (item 1 of argv) "
                   "with title (item 2 of argv)",
             "-e", "end run",
             message, title],
            capture_output=True, timeout=5,
        )
    except Exception:
        pass  # notification ล้มเหลวต้องไม่กระทบการอัด


def write_status(state: str, meeting_name=None, recording_path=None,
                 started_at=None, last_error=None,
                 last_recording_path=None, last_recording_name=None,
                 last_saved_at=None, last_status=None):
    """เขียน status.json แบบ atomic (temp + os.replace) — best-effort
    เป็น data source ของ menu bar app ในอนาคต — app ห้าม parse จาก log file
    state: idle | waiting | recording | stopping | error
    last_recording_* — คงอยู่ใน waiting state เพื่อให้ menu bar app แสดงไฟล์ล่าสุด
    """
    try:
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        payload = {
            "state":              state,
            "meetingName":        meeting_name,
            "recordingPath":      recording_path,
            "startedAt":          started_at,
            "lastError":          last_error,
            "lastRecordingPath":  last_recording_path,
            "lastRecordingName":  last_recording_name,
            "lastSavedAt":        last_saved_at,
            "lastStatus":         last_status,
            "updatedAt":          datetime.now().isoformat(timespec="seconds"),
        }
        tmp = STATUS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp, STATUS_FILE)
    except Exception:
        pass


def write_pid_file():
    """เขียน PID ของ watcher ปัจจุบันลงไฟล์ — ใช้โดย 'make stop'"""
    try:
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass


def remove_pid_file():
    """ลบ PID file เมื่อ watcher จบ — ไม่เป็นไรถ้าไฟล์หายไปแล้ว"""
    try:
        os.remove(PID_FILE)
    except OSError:
        pass


def _process_command(pid: str) -> str:
    """คืน command line ของ PID ที่ระบุ — ว่างถ้าไม่มี process นั้น"""
    try:
        r = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:
        return ""


# ─── Swift binary management ──────────────────────────────────

def find_recorder_binary() -> str:
    """RECORDER_BIN env override → sibling recorder/recorder path."""
    override = os.getenv("RECORDER_BIN")
    if override:
        return os.path.expanduser(override)
    return os.path.join(BASE_DIR, "recorder", "recorder")


def check_recorder_ready() -> bool:
    """ตรวจว่า binary มีอยู่และ arch ตรงกับเครื่อง
    On mismatch: แสดง 'Run: make build-recorder' แล้ว return False
    """
    binary = find_recorder_binary()
    if not os.path.exists(binary):
        log(f"[ERROR] ไม่พบ recorder binary: {binary}")
        log("  → รัน: make build-recorder")
        return False

    # ตรวจ arch ตรงกันไหม
    machine = platform.machine()  # "arm64" หรือ "x86_64"
    try:
        r = subprocess.run(["file", binary], capture_output=True, text=True, timeout=5)
        if machine not in r.stdout:
            log(f"[ERROR] recorder binary เป็น arch ผิด — เครื่องนี้คือ {machine}")
            log(f"  stdout: {r.stdout.strip()}")
            log("  → รัน: make build-recorder  แล้ว commit v2/recorder/recorder")
            return False
    except Exception as e:
        log(f"[WARN] ตรวจ arch ไม่ได้: {e} — ดำเนินการต่อ")

    # รัน --check เพื่อยืนยัน binary ทำงานได้
    try:
        r = subprocess.run([binary, "--check"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode != 0 or not r.stdout.startswith("OK"):
            log(f"[ERROR] recorder --check ล้มเหลว (exit={r.returncode})")
            log(f"  stdout: {r.stdout.strip()}")
            log(f"  stderr: {r.stderr.strip()}")
            return False
    except Exception as e:
        log(f"[ERROR] recorder --check: {e}")
        return False

    log(f"✓  recorder binary: {r.stdout.strip().splitlines()[1] if len(r.stdout.splitlines()) > 1 else 'ok'}")
    return True


DISK_ABORT_MB      = 200  # match kMinFreeBytes ใน Swift binary — ต้องตรงกัน
DISK_WARN_MB       = 500  # warn ล่วงหน้าก่อนถึงขีดหยุด
MAX_CRASH_RESTARTS = 3    # respawn binary ได้สูงสุดกี่ครั้งก่อน abort

def check_disk_space(recording_dir: str) -> bool:
    """ตรวจ disk space ก่อนเริ่ม recording
    < 200MB → หยุด (return False) — ตรงกับ kMinFreeBytes ใน Swift binary
    < 500MB → warn แต่ดำเนินการต่อ (return True)
    """
    try:
        usage = shutil.disk_usage(recording_dir)
        free_mb = usage.free // (1024 * 1024)
        if free_mb < DISK_ABORT_MB:
            log(f"[ERROR] Disk space ต่ำเกินไป: {free_mb}MB (ต้องการ {DISK_ABORT_MB}MB+) — หยุด")
            return False
        if free_mb < DISK_WARN_MB:
            log(f"[WARN] Disk space เหลือน้อย: {free_mb}MB")
    except Exception as e:
        log(f"[WARN] ตรวจ disk space ไม่ได้: {e} — ดำเนินการต่อ")
    return True


# ─── Process management ───────────────────────────────────────

_recorder_proc: "subprocess.Popen | None" = None


def _cleanup_recorder():
    """ยุติ Swift binary เมื่อ Python process จบ (atexit / signal)"""
    global _recorder_proc
    if _recorder_proc and _recorder_proc.poll() is None:
        _recorder_proc.terminate()
        try:
            _recorder_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _recorder_proc.kill()


atexit.register(_cleanup_recorder)


def connect_recorder() -> "subprocess.Popen | None":
    """เปิด Swift binary process (long-lived, stdin/stdout protocol)
    Returns: Popen หรือ None ถ้าล้มเหลว
    """
    global _recorder_proc

    if not check_recorder_ready():
        return None

    # ─── warn ถ้ามี teams_recorder process อื่นทำงานอยู่ ───────
    r = subprocess.run(["pgrep", "-f", "teams_recorder"],
                       capture_output=True, text=True)
    # กรอง PID ของตัวเองออก — pgrep -f จะ match process ปัจจุบันด้วย
    other_pids = [p for p in r.stdout.strip().split("\n")
                  if p.strip() and p.strip() != str(os.getpid())]
    if other_pids:
        for opid in other_pids:
            log(f"[WARN] watcher อื่นกำลังทำงานอยู่: PID {opid} "
                f"— {_process_command(opid)}")
        log("  → ใช้ 'make stop' เพื่อหยุด watcher เดิมก่อนเริ่มใหม่")

    binary = find_recorder_binary()
    cmd = [binary]

    # ส่ง device UID ถ้ามีกำหนดใน .env
    # AUDIO_INPUT_DEVICE_UID — ใช้สำหรับ mic input เท่านั้น, ไม่มีผลกับ system audio
    device_uid = os.getenv("AUDIO_INPUT_DEVICE_UID", "").strip()
    if device_uid:
        cmd += ["--device", device_uid]
        log(f"[INFO] ใช้ mic input device: {device_uid}")

    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,  # unbuffered — ต้องการ immediate response
        )
        _recorder_proc = proc
        log("✓  recorder binary started")
        return proc
    except Exception as e:
        log(f"[ERROR] เปิด recorder binary ไม่ได้: {e}")
        return None


# ─── Recording lifecycle ──────────────────────────────────────

def _readline_timeout(fd, timeout: float) -> str:
    """อ่าน 1 บรรทัดจาก fd พร้อม timeout — return '' ถ้าหมดเวลา"""
    r, _, _ = select.select([fd], [], [], timeout)
    return fd.readline().decode(errors="replace").strip() if r else ""


def _readlines_timeout(fd, timeout: float) -> list:
    """อ่านทุกบรรทัดที่มีอยู่จาก fd ภายใน timeout วินาที
    หยุดเมื่อไม่มีข้อมูลใหม่เข้ามาภายใน 0.2s (drain แล้ว) หรือ timeout รวมหมด
    """
    lines = []
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        r, _, _ = select.select([fd], [], [], min(remaining, 0.2))
        if not r:
            break
        line = fd.readline().decode(errors="replace").strip()
        if line:
            lines.append(line)
    return lines


def start_recording_v2(proc: "subprocess.Popen",
                       recording_dir: str) -> "dict | None":
    """ส่ง 'start <path>' ไปที่ binary แล้วรอ STARTED (timeout 10s)
    Returns: session dict หรือ None ถ้าล้มเหลว
    """
    # S3: makedirs ก่อน check_disk_space — ถ้า dir ยังไม่มี disk_usage จะตรวจ parent แทน (wrong disk!)
    try:
        os.makedirs(recording_dir, exist_ok=True)
    except OSError as e:
        log(f"[ERROR] ไม่สามารถสร้าง recording folder: {e}")
        return None

    if not check_disk_space(recording_dir):
        notify("Team Recorder", "⚠️ พื้นที่ดิสก์ไม่พอ — ไม่เริ่มบันทึก")
        return None
    start_time = datetime.now()
    ts = start_time.strftime("%H-%M_%d-%m-%Y")
    rec_path = os.path.join(recording_dir, f"rec_{ts}.m4a")

    # ─── ส่ง start command ────────────────────────────────────
    try:
        proc.stdin.write(f"start {rec_path}\n".encode())
        proc.stdin.flush()
    except BrokenPipeError:
        log("[ERROR] recorder binary ไม่ตอบสนอง (broken pipe)")
        return None

    # ─── รอ STARTED (timeout 10s) ────────────────────────────
    response = _readline_timeout(proc.stdout, 10.0)
    if response != "STARTED":
        # drain stderr — Swift เขียน hint ก่อน ERROR token (2 บรรทัด)
        err_lines = _readlines_timeout(proc.stderr, 1.0)
        err = " | ".join(err_lines)
        log(f"[ERROR] recorder ไม่ตอบ STARTED — stdout={response!r} stderr={err!r}")
        if any("screen_recording_permission_denied" in ln for ln in err_lines):
            log("━" * 52)
            log("❌  ต้องเปิดสิทธิ์ Screen Recording ก่อนใช้งาน")
            log("   กำลังเปิด System Settings...")
            log("━" * 52)
            subprocess.run(["open",
                "x-apple.systempreferences:com.apple.preference.security"
                "?Privacy_ScreenCapture"])
            notify("Team Recorder",
                   "❌ ต้องเปิดสิทธิ์ Screen Recording ก่อนใช้งาน")
            write_status("error",
                         last_error="screen_recording_permission_denied")
        return None

    # ─── ดึงชื่อ meeting จาก calendar (cached per day) ───────
    meetings = _get_today_meetings_cached()
    meeting_name = find_matching_meeting(start_time, meetings)
    if meeting_name:
        log("📅 Meeting: " + meeting_name)

    log("▶  Recording started")
    write_status("recording", meeting_name=meeting_name,
                 recording_path=rec_path,
                 started_at=start_time.isoformat(timespec="seconds"))
    notify("Team Recorder",
           f"🔴 กำลังบันทึก: {meeting_name}" if meeting_name
           else "🔴 กำลังบันทึก Teams meeting")
    return {
        "start_time":     start_time,
        "recording_path": rec_path,
        "recording_dir":  recording_dir,
        "meeting_name":   meeting_name,
    }


def stop_recording_v2(proc: "subprocess.Popen",
                      session: "dict | None"):
    """ส่ง 'stop' ไปที่ binary แล้วรอ STOPPED (timeout 30s) แล้ว rename"""
    if not session:
        log("[WARN] ไม่มี active recording session → ข้าม")
        return

    start_time    = session["start_time"]
    duration_secs = (datetime.now() - start_time).total_seconds()

    try:
        proc.stdin.write(b"stop\n")
        proc.stdin.flush()
    except BrokenPipeError:
        log("[ERROR] recorder binary ไม่ตอบสนอง (broken pipe) — ข้าม rename")
        write_status("error", last_error="broken pipe ตอนสั่ง stop")
        return

    write_status("stopping", meeting_name=session.get("meeting_name"))

    # รอ STOPPED_OK / STOPPED_ERROR — binary block จนกว่า finishWriting จะเสร็จ
    response = _readline_timeout(proc.stdout, 30.0)
    if response == "STOPPED_OK":
        log("■  Recording stopped")
        final_path = rename_recording(session, duration_secs)
        rec_status = "complete"
        if final_path:
            ok, reason = validate_recording(final_path)
            if not ok:
                final_path = _rename_as_needs_check(final_path, reason)
                rec_status = "needs-check"
                notify("Team Recorder",
                       f"⚠️ บันทึกแล้วแต่ต้องตรวจสอบ: "
                       f"{os.path.basename(final_path)}")
            else:
                notify("Team Recorder",
                       f"✅ บันทึกแล้ว: {os.path.basename(final_path)}")
        write_status(
            "waiting",
            last_recording_path=final_path,
            last_recording_name=os.path.basename(final_path) if final_path else None,
            last_saved_at=datetime.now().isoformat(timespec="seconds"),
            last_status=rec_status if final_path else None,
        )
    elif response and response.startswith("STOPPED_ERROR"):
        reason = response[len("STOPPED_ERROR:"):].strip()
        log(f"[ERROR] finishWriting failed: {reason} — marking as INCOMPLETE")
        _rename_as_incomplete(session)
        notify("Team Recorder", "⚠️ บันทึกไม่สมบูรณ์ (INCOMPLETE)")
        write_status("error", last_error=f"STOPPED_ERROR: {reason}")
    else:
        log(f"[ERROR] ไม่ได้รับ STOPPED_OK (ได้ {response!r}) — ข้าม rename (ไฟล์อาจไม่ครบ)")
        notify("Team Recorder", "⚠️ หยุดบันทึกผิดพลาด — ไฟล์อาจไม่ครบ")
        write_status("error", last_error=f"ไม่ได้รับ STOPPED_OK: {response!r}")


# ─── Subcommands: doctor / permissions / stop / index ────────

def _check(label: str, status: str, detail: str = ""):
    """พิมพ์ 1 บรรทัดผลตรวจของ doctor — status: ok | fail | warn | skip"""
    mark = {"ok": "✓", "fail": "✗", "warn": "?", "skip": "?"}.get(status, "•")
    line = f"  {mark}  {label}"
    if detail:
        line += f"  — {detail}"
    print(line)


def run_doctor() -> int:
    """ตรวจความพร้อมระบบแบบ read-only ไม่ interactive — ไม่ขอ permission ใด ๆ
    ซื่อสัตย์เรื่องสิ่งที่พิสูจน์ไม่ได้: รายงาน '?' แทนการเดาว่าผ่าน/ไม่ผ่าน
    Returns: exit code 0 ถ้าไม่มี hard failure, 1 ถ้ามี
    """
    print("=" * 52)
    print("  Team Recorder — Doctor (ตรวจความพร้อมระบบ)")
    print("=" * 52)
    failures = 0

    # macOS version
    mac_ver = platform.mac_ver()[0]
    try:
        if int(mac_ver.split(".")[0]) >= 13:
            _check(f"macOS {mac_ver}", "ok", "รองรับ ScreenCaptureKit")
        else:
            _check(f"macOS {mac_ver}", "fail", "ต้องการ macOS 13+")
            failures += 1
    except ValueError:
        _check(f"macOS {mac_ver or '?'}", "warn", "ตรวจ version ไม่ได้")

    # recorder binary (มีไฟล์ + arch ตรง + --check ผ่าน)
    if check_recorder_ready():
        _check("recorder binary", "ok", "ผ่าน --check")
    else:
        _check("recorder binary", "fail", "รัน: make build-recorder")
        failures += 1

    # icalBuddy
    if os.path.exists(ICAL_BUDDY):
        _check("icalBuddy", "ok", ICAL_BUDDY)
    else:
        _check("icalBuddy", "warn",
               "ไม่พบ — ชื่อ meeting จะเป็น fallback (brew install ical-buddy)")

    # recording folder เขียนได้ไหม
    try:
        os.makedirs(RECORDING_DIR, exist_ok=True)
        probe = os.path.join(RECORDING_DIR, ".doctor_write_test")
        with open(probe, "w") as f:
            f.write("ok")
        os.remove(probe)
        _check("recording folder เขียนได้", "ok", RECORDING_DIR)
    except OSError as e:
        _check("recording folder", "fail", f"{RECORDING_DIR} — {e}")
        failures += 1

    # disk space
    if check_disk_space(RECORDING_DIR):
        _check("disk space", "ok", "เพียงพอ")
    else:
        _check("disk space", "fail", "ต่ำกว่าขีดหยุด")
        failures += 1

    # mic device UID ที่ตั้งใน .env ยังมองเห็นไหม
    device_uid = os.getenv("AUDIO_INPUT_DEVICE_UID", "").strip()
    if device_uid:
        seen = False
        try:
            r = subprocess.run([find_recorder_binary(), "--list-devices"],
                               capture_output=True, text=True, timeout=10)
            seen = any(ln.split("\t")[0] == device_uid
                       for ln in r.stdout.splitlines() if ln.strip())
        except Exception:
            pass
        if seen:
            _check("mic device UID", "ok", "device ที่ตั้งไว้ยังมองเห็น")
        else:
            _check("mic device UID", "warn",
                   f"ไม่พบ {device_uid} — จะ fallback เป็น default mic")
    else:
        _check("mic device", "ok", "ใช้ default mic")

    # Calendar — พิสูจน์สิทธิ์ไม่ได้แน่ชัดถ้าวันนี้ไม่มี event
    meetings = get_today_meetings()
    if meetings:
        _check("Calendar", "ok", f"อ่าน calendar ได้ ({len(meetings)} event)")
    else:
        _check("Calendar permission", "warn",
               "พิสูจน์ไม่ได้ — วันนี้ไม่มี event หรือยังไม่ได้ให้สิทธิ์ "
               "(ดู: make permissions)")

    # สิ่งที่ตรวจแบบ read-only ไม่ได้ — ซื่อสัตย์ว่ายืนยันไม่ได้
    _check("Screen Recording permission", "skip",
           "ยืนยันไม่ได้จนกว่าจะลองอัดจริง — ถ้าอัดไม่ขึ้น: make permissions")
    _check("Microphone permission", "skip",
           "ยืนยันแบบ read-only ไม่ได้ — ถ้าเสียง mic เงียบ: make permissions")

    print("-" * 52)
    if failures:
        print(f"  ✗  พบปัญหา {failures} จุด — แก้ก่อนใช้งานจริง")
    else:
        print("  ✓  ผ่านการตรวจหลัก — ดูบรรทัด '?' ที่ยืนยันไม่ได้ด้วย")
    print("=" * 52)
    return 1 if failures else 0


def run_permissions() -> int:
    """เปิดหน้า System Settings ที่เกี่ยวข้อง + trigger Screen Recording prompt
    macOS ไม่ยอมให้ app ให้สิทธิ์ตัวเอง — ทำได้แค่พาผู้ใช้ไปหน้าที่ถูกต้อง
    """
    print("กำลังเปิดหน้า System Settings ที่ต้องตั้งค่า...")
    for name, anchor in (("Screen Recording", "Privacy_ScreenCapture"),
                         ("Microphone",       "Privacy_Microphone"),
                         ("Calendars",        "Privacy_Calendars")):
        print(f"  → {name}")
        try:
            subprocess.run(
                ["open", "x-apple.systempreferences:"
                 f"com.apple.preference.security?{anchor}"],
                timeout=10)
        except Exception as e:
            print(f"    เปิดไม่ได้: {e}")
        time.sleep(1)

    binary = find_recorder_binary()
    if os.path.exists(binary):
        print("  → ขอสิทธิ์ Screen Recording (อาจมี dialog เด้ง)")
        try:
            subprocess.run([binary, "--request-permission"],
                           capture_output=True, timeout=15)
        except Exception:
            pass
    print("เปิดสิทธิ์ใน System Settings แล้ว ปิด/เปิด Terminal ใหม่ก่อน make run")
    return 0


def _pgrep_watcher_pids() -> "list[int]":
    """คืน list ของ PID ที่ match teams_recorder_v2.py จาก pgrep — ไม่รวม PID ตัวเอง"""
    try:
        r = subprocess.run(
            ["pgrep", "-f", "teams_recorder_v2.py"],
            capture_output=True, text=True,
        )
        return [
            int(p) for p in r.stdout.strip().splitlines()
            if p.strip() and int(p.strip()) != os.getpid()
        ]
    except Exception:
        return []


def run_stop() -> int:
    """หยุด watcher ที่กำลังทำงาน — อ่าน PID file แล้วยืนยัน command path
    ถ้าไม่มี PID file ให้ fallback ไปใช้ pgrep (รองรับ migration / PID file หาย)
    ไม่ใช้ pkill กว้าง ๆ: ส่ง SIGTERM เฉพาะ process ที่เป็น teams_recorder_v2.py จริง
    """
    if not os.path.exists(PID_FILE):
        pids = _pgrep_watcher_pids()
        if not pids:
            print("ไม่พบ watcher ที่กำลังทำงาน (ไม่มี PID file และไม่พบ process)")
            return 0
        if len(pids) > 1:
            print(f"พบ {len(pids)} processes ที่อาจเป็น watcher — ระบุ PID ไม่ได้ชัดเจน")
            for p in pids:
                print(f"  PID {p}: {_process_command(str(p))}")
            print("ใช้คำสั่ง 'kill <PID>' เพื่อหยุด process ที่ต้องการ")
            return 1
        pid = pids[0]
        cmd = _process_command(str(pid))
        if not cmd or "teams_recorder_v2.py" not in cmd:
            print(f"PID {pid} ไม่ใช่ Team Recorder ({cmd}) — ไม่ส่งสัญญาณ")
            return 1
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"ส่ง SIGTERM ไปยัง watcher PID {pid} (พบผ่าน pgrep) แล้ว")
            return 0
        except OSError as e:
            print(f"หยุด PID {pid} ไม่ได้: {e}")
            return 1
    try:
        pid = int(open(PID_FILE).read().strip())
    except (ValueError, OSError) as e:
        print(f"อ่าน PID file ไม่ได้: {e}")
        return 1
    cmd = _process_command(str(pid))
    if not cmd:
        print(f"PID {pid} ไม่ทำงานแล้ว — ลบ PID file ที่ค้าง")
        remove_pid_file()
        return 0
    if "teams_recorder_v2.py" not in cmd:
        print(f"PID {pid} ไม่ใช่ Team Recorder ({cmd}) — ไม่ส่งสัญญาณ")
        return 1
    try:
        os.kill(pid, signal.SIGTERM)
        print(f"ส่ง SIGTERM ไปยัง watcher PID {pid} แล้ว")
        return 0
    except OSError as e:
        print(f"หยุด PID {pid} ไม่ได้: {e}")
        return 1


def _recording_status(name: str) -> str:
    """เดาสถานะ recording จาก prefix ของชื่อไฟล์"""
    if name.startswith("INCOMPLETE_"):
        return "incomplete"
    if name.startswith("NEEDS_CHECK_"):
        return "needs-check"
    if name.startswith("Teams Call (Short)"):
        return "short"
    return "complete"


def _write_index_html(out_path: str, rows: list):
    """เขียน index.html — ตาราง recording ทั้งหมด เปิดด้วย browser/Finder ได้"""
    import html
    from urllib.parse import quote
    badge = {"complete": "#1a7f37", "short": "#9a6700",
             "incomplete": "#cf222e", "needs-check": "#bc4c00"}
    parts = [
        "<!doctype html><html lang='th'><head><meta charset='utf-8'>",
        "<title>Team Recorder — Index</title><style>",
        "body{font-family:-apple-system,Segoe UI,sans-serif;margin:2rem;"
        "background:#f6f8fa;color:#1f2328}h1{font-size:1.3rem}",
        "table{border-collapse:collapse;width:100%;background:#fff;"
        "box-shadow:0 1px 3px rgba(0,0,0,.1);border-radius:8px;overflow:hidden}",
        "th,td{text-align:left;padding:.6rem .8rem;"
        "border-bottom:1px solid #d0d7de;font-size:.9rem}",
        "th{background:#f6f8fa;font-weight:600}tr:last-child td{border-bottom:none}",
        "a{color:#0969da;text-decoration:none}.muted{color:#656d76;font-size:.8rem}",
        ".badge{padding:.1rem .5rem;border-radius:999px;color:#fff;font-size:.75rem}",
        "</style></head><body>",
        f"<h1>Team Recorder — {len(rows)} recordings</h1>",
        f"<p class='muted'>อัปเดต {datetime.now():%Y-%m-%d %H:%M}</p>",
        "<table><tr><th>วันที่/เวลา</th><th>ชื่อไฟล์</th><th>ความยาว</th>"
        "<th>ขนาด</th><th>สถานะ</th></tr>",
    ]
    for r in rows:
        color = badge.get(r["status"], "#656d76")
        url = "file://" + quote(r["path"])
        parts.append(
            f"<tr><td>{r['mtime']:%Y-%m-%d %H:%M}</td>"
            f"<td><a href=\"{html.escape(url)}\">{html.escape(r['name'])}</a></td>"
            f"<td>{r['dur']}</td><td>{r['size']}</td>"
            f"<td><span class='badge' style='background:{color}'>"
            f"{r['status']}</span></td></tr>")
    if not rows:
        parts.append("<tr><td colspan='5' class='muted'>ยังไม่มี recording</td></tr>")
    parts.append("</table></body></html>")
    try:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("\n".join(parts))
    except OSError as e:
        log(f"[WARN] เขียน index.html ไม่ได้: {e}")


def run_index() -> int:
    """สร้าง index.html รวมรายการ recording ทั้งหมดใน RECORDING_DIR
    สถานะอ่านจาก prefix ของชื่อไฟล์ — เปิดไฟล์อัตโนมัติเมื่อเสร็จ
    """
    if not os.path.isdir(RECORDING_DIR):
        print(f"ไม่พบ recording folder: {RECORDING_DIR}")
        return 1
    rows = []
    for name in os.listdir(RECORDING_DIR):
        if not name.lower().endswith(".m4a"):
            continue
        path = os.path.join(RECORDING_DIR, name)
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(path))
            size_mb = os.path.getsize(path) / (1024 * 1024)
        except OSError:
            continue
        dur = read_audio_duration(path)
        dur_str = (f"{int(dur // 60)}:{int(dur % 60):02d}"
                   if dur else "—")
        rows.append({"name": name, "mtime": mtime, "path": path,
                     "status": _recording_status(name), "dur": dur_str,
                     "size": f"{size_mb:.1f} MB"})
    rows.sort(key=lambda r: r["mtime"], reverse=True)

    out_path = os.path.join(RECORDING_DIR, "index.html")
    _write_index_html(out_path, rows)
    print(f"สร้าง index แล้ว: {out_path} ({len(rows)} ไฟล์)")
    try:
        subprocess.run(["open", out_path], timeout=10)
    except Exception:
        pass
    return 0


# ─── Phase 2A: crash auto-restart ────────────────────────────

def _attempt_crash_restart(
    session: "dict | None",
    in_meeting: bool,
    recording_dir: str,
    crash_count: int,
) -> "tuple[subprocess.Popen, dict | None] | None":
    """พยายาม respawn recorder binary หลัง crash และเริ่ม segment ใหม่ถ้าอยู่ใน meeting
    Returns: (new_proc, new_session) หรือ None ถ้าถึง cap หรือ spawn ล้มเหลว
    new_session อาจเป็น None ถ้า spawn ได้แต่ start recording ล้มเหลว

    Caller ต้องทำ _rename_as_incomplete(session) ก่อนเรียกฟังก์ชันนี้
    """
    if crash_count >= MAX_CRASH_RESTARTS:
        log(f"[ERROR] recorder crash {MAX_CRASH_RESTARTS} ครั้งติดต่อกัน — หยุดถาวร")
        write_status("error",
                     last_error=f"recorder crash {MAX_CRASH_RESTARTS} ครั้งติดต่อกัน")
        notify("Team Recorder",
               f"❌ recorder crash {MAX_CRASH_RESTARTS} ครั้ง — หยุดบันทึกถาวร")
        return None

    notify("Team Recorder",
           f"⚠️ recorder หยุดกะทันหัน — กำลัง restart ({crash_count}/{MAX_CRASH_RESTARTS})")
    write_status("error",
                 last_error=f"recorder crash ครั้งที่ {crash_count} — กำลัง restart")

    new_proc = connect_recorder()
    if not new_proc:
        log("[ERROR] restart recorder ล้มเหลว — หยุด script")
        write_status("error", last_error="restart recorder ล้มเหลว")
        notify("Team Recorder", "❌ restart recorder ล้มเหลว — หยุดบันทึกถาวร")
        return None

    log(f"✓  recorder restarted (segment {crash_count + 1})")
    new_session = None
    if in_meeting:
        new_session = start_recording_v2(new_proc, recording_dir)
        if new_session:
            log(f"▶  Recording segment {crash_count + 1} เริ่มแล้ว")
        else:
            log("[WARN] เริ่ม recording segment ใหม่ไม่ได้ — รอ loop ถัดไป")
            write_status("waiting")
    else:
        write_status("waiting")

    return new_proc, new_session


# ─── Manual start/stop helpers ────────────────────────────────
# ใช้ร่วมกันทั้ง keyboard path (key 1/2) และ signal path (SIGUSR1/2)
# เพื่อให้ logic เหมือนกันทุกกรณี — อย่าแก้ที่เดียวโดยไม่แก้อีกที่

def _do_manual_start(proc, session, recording_dir):
    """
    Start a recording manually — shared by keyboard '1' and SIGUSR1.
    Returns (new_session, recording_started_by) on success; (session, unchanged) if already recording.
    Callers must update in_meeting, recording_started_by, etc. from the return values.
    """
    if session is not None:
        log("[WARN] กำลังบันทึกอยู่แล้ว — หยุดก่อนเริ่มใหม่")
        return session, "manual"
    log("⌨  Manual start")
    new_session = start_recording_v2(proc, recording_dir)
    return new_session, "manual"


def _do_manual_stop(proc, session, active: bool):
    """
    Stop a recording manually — shared by keyboard '2' and SIGUSR2.
    Returns suppress_auto_start flag (True when Teams still active, to prevent immediate restart).
    Callers must nil-out session and reset crash_restart_count after calling.
    """
    if session is None:
        log("[WARN] ไม่มี recording ที่กำลังทำงานอยู่")
        return False
    log("⌨  Manual stop")
    suppress = active  # ป้องกัน auto-restart ถ้า Teams ยังคุยอยู่
    stop_recording_v2(proc, session)
    return suppress


# ─── Signal handlers for SIGUSR1 / SIGUSR2 ───────────────────
# handler ต้องทำแค่ตั้ง flag — ห้ามทำงานหนักใน signal context

def _handle_sigusr1(sig, frame):
    """SIGUSR1 → request manual start recording (sent by menu bar app)"""
    global _sig_start_requested
    _sig_start_requested = True


def _handle_sigusr2(sig, frame):
    """SIGUSR2 → request manual stop recording (sent by menu bar app)"""
    global _sig_stop_requested
    _sig_stop_requested = True


# ─── Main loop ────────────────────────────────────────────────

def main():
    print("=" * 52)
    print("  Teams Auto-Recorder v2 — รอ meeting อยู่...")
    print("  ไม่ต้องใช้ OBS — ใช้ Swift binary แทน")
    print(f"  📁 บันทึกที่: {RECORDING_DIR}")
    print("  ⌨  1 = เริ่มบันทึก  |  2 = หยุดบันทึก  |  Q = ออก")
    print("=" * 52)

    global NOTIFY_ENABLED
    NOTIFY_ENABLED = True
    write_pid_file()
    atexit.register(remove_pid_file)
    write_status("idle")

    # U5: ตรวจ icalBuddy ครั้งเดียวตอนเริ่ม — ไม่ log ซ้ำในทุก poll
    if not os.path.exists(ICAL_BUDDY):
        log("[WARN] icalBuddy ไม่พบ — ชื่อ meeting จะเป็น 'Teams Meeting' เสมอ")
        log("  → ติดตั้งด้วย: brew install ical-buddy")

    # ตรวจ macOS version (ต้องการ 13+ สำหรับ ScreenCaptureKit)
    mac_ver = platform.mac_ver()[0]
    try:
        major = int(mac_ver.split(".")[0])
        if major < 13:
            log(f"[ERROR] macOS {mac_ver} ไม่รองรับ — ต้องการ macOS 13+ (ScreenCaptureKit)")
            sys.exit(1)
    except ValueError:
        pass

    proc = connect_recorder()
    if not proc:
        write_status("error", last_error="recorder binary ไม่พร้อมใช้งาน")
        return
    write_status("waiting")

    in_meeting           = False
    session              = None
    end_pending_at       = 0.0   # เวลาที่ detect meeting จบครั้งแรก (สำหรับ grace period)
    recording_started_by = None  # None | "auto" | "manual"
    suppress_auto_start  = False # True ขณะ Teams UDP ยังสูงหลัง manual stop
    crash_restart_count  = 0     # รีเซ็ตหลัง meeting จบปกติ — ป้องกัน crash loop

    # ─── TTY setup — define restore_tty BEFORE signal handlers ──
    IS_TTY  = sys.stdin.isatty()
    old_tty = None

    def restore_tty():
        if old_tty is not None:
            try:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
            except termios.error:
                pass

    if IS_TTY:
        try:
            old_tty = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
            log("⌨  1 = เริ่มบันทึก  |  2 = หยุดบันทึก  |  Q = ออก  (ต้อง focus Terminal)")
        except termios.error:
            IS_TTY = False
            log("[INFO] ไม่สามารถตั้ง terminal mode — ใช้ auto-detect เท่านั้น")
    else:
        log("[INFO] ไม่ใช่ terminal — ใช้ auto-detect เท่านั้น (ไม่รองรับ 1/2)")

    # ─── Graceful shutdown ────────────────────────────────────
    def handle_exit(sig, frame):
        log("Script หยุดโดย user")
        if session:
            log("กำลัง stop recording...")
            stop_recording_v2(proc, session)
        write_status("idle")
        restore_tty()
        _cleanup_recorder()
        sys.exit(0)

    signal.signal(signal.SIGINT,  handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, handle_exit)
    # SIGUSR1/2 — ส่งมาจาก menu bar app เพื่อ manual start/stop
    signal.signal(signal.SIGUSR1, _handle_sigusr1)
    signal.signal(signal.SIGUSR2, _handle_sigusr2)
    # ──────────────────────────────────────────────────────────

    try:
        while True:
            # ตรวจ binary ยังอยู่ไหม — ถ้าตายให้ respawn แทนที่จะหยุดทั้งหมด
            if proc.poll() is not None:
                crash_restart_count += 1
                log(f"[ERROR] recorder binary จบกะทันหัน "
                    f"(ครั้งที่ {crash_restart_count}/{MAX_CRASH_RESTARTS})")
                if session:
                    _rename_as_incomplete(session)
                    session = None
                result = _attempt_crash_restart(
                    session, in_meeting, RECORDING_DIR, crash_restart_count)
                if result is None:
                    restore_tty()
                    _cleanup_recorder()
                    sys.exit(1)
                proc, session = result
                continue

            active = is_teams_in_meeting()

            # Reset suppress เมื่อ Teams ไม่ได้ active — พร้อม auto-start รอบถัดไป
            if not active and not in_meeting:
                suppress_auto_start = False

            if active and not in_meeting and not suppress_auto_start:
                # Meeting เพิ่งเริ่ม (auto-detect)
                log("📢 ตรวจพบ Teams meeting!")
                new_session = start_recording_v2(proc, RECORDING_DIR)
                if new_session:
                    in_meeting           = True
                    session              = new_session
                    recording_started_by = "auto"
                    end_pending_at       = 0.0
                else:
                    log("[WARN] ยังไม่เริ่ม recording session — จะลองใหม่รอบถัดไป")

            elif not active and in_meeting and recording_started_by == "auto":
                # UDP หายไป — รอ STOP_GRACE วินาทีก่อน confirm ว่าจบจริง (auto only)
                now = time.time()
                if end_pending_at == 0.0:
                    end_pending_at = now
                    log(f"⏳ Meeting อาจจบแล้ว — รอยืนยัน {STOP_GRACE}s...")
                elif now - end_pending_at >= STOP_GRACE:
                    in_meeting           = False
                    end_pending_at       = 0.0
                    recording_started_by = None
                    log("👋 Teams meeting จบแล้ว")
                    stop_recording_v2(proc, session)
                    session = None
                    crash_restart_count = 0  # binary ยังทำงานปกติ

            elif active and end_pending_at > 0:
                # UDP กลับมาระหว่าง grace period → ยกเลิก pending stop
                end_pending_at = 0.0
                log("✓  Meeting ยังอยู่ (connection กลับมา)")

            # ─── Keyboard input ───────────────────────────────────
            # P2-B: ถ้า Teams ไม่ได้เปิด ลด polling 3x → ประหยัด CPU / lsof calls
            sleep_time = POLL_INTERVAL if get_teams_pid() else POLL_INTERVAL * 3

            if IS_TTY:
                try:
                    r, _, _ = select.select([sys.stdin], [], [], sleep_time)
                except (ValueError, OSError):
                    r = []
                if r:
                    # Drain all bytes available right now — handles multi-byte Thai UTF-8
                    # (select woke up so at least 1 byte is ready; os.read is non-blocking)
                    ch = os.read(sys.stdin.fileno(), 8)
                    # Keep draining if more bytes arrived (e.g. the 2nd/3rd byte of ๅ)
                    while True:
                        try:
                            r2, _, _ = select.select([sys.stdin], [], [], 0)
                            if not r2:
                                break
                            ch += os.read(sys.stdin.fileno(), 8)
                        except (ValueError, OSError):
                            break
                    # Layout-independent matching:
                    # EN: 1/r/R=start  2/s/S=stop  q/Q=quit
                    # TH Kedmanee: ๅ(1)=start พ(r)=start | /(2)=stop ห(s)=stop | ๆ(q)=quit
                    # Caps Lock: R/S/Q covered by casefold; ๅ/พ/ห/ๆ are case-invariant
                    try:
                        ch_str = ch.decode("utf-8", errors="replace").casefold()
                    except Exception:
                        ch_str = ""
                    _START = ch_str[:1] in ("1", "r") or ch_str.startswith(("ๅ", "พ"))
                    _STOP  = ch_str[:1] in ("2", "s", "/") or ch_str.startswith("ห")
                    _QUIT  = (ch[:1] in (b'q', b'Q', b'\x03', b'\x1b')
                              or ch_str.startswith("ๆ"))
                    if _START:
                        new_session, _ = _do_manual_start(proc, session, RECORDING_DIR)
                        if new_session and new_session is not session:
                            session              = new_session
                            in_meeting           = True
                            recording_started_by = "manual"
                            suppress_auto_start  = False
                            end_pending_at       = 0.0
                    elif _STOP:
                        suppress = _do_manual_stop(proc, session, active)
                        if session is not None:  # helper only stops when session exists
                            suppress_auto_start  = suppress
                            in_meeting           = False
                            recording_started_by = None
                            end_pending_at       = 0.0
                            session              = None
                            crash_restart_count  = 0
                    elif _QUIT:
                        handle_exit(None, None)
            else:
                time.sleep(sleep_time)

            # ─── Signal-triggered manual controls (SIGUSR1/2 from menu bar app) ──
            global _sig_start_requested, _sig_stop_requested
            if _sig_start_requested:
                _sig_start_requested = False
                new_session, _ = _do_manual_start(proc, session, RECORDING_DIR)
                if new_session and new_session is not session:
                    session              = new_session
                    in_meeting           = True
                    recording_started_by = "manual"
                    suppress_auto_start  = False
                    end_pending_at       = 0.0
            if _sig_stop_requested:
                _sig_stop_requested = False
                suppress = _do_manual_stop(proc, session, active)
                if session is not None:
                    suppress_auto_start  = suppress
                    in_meeting           = False
                    recording_started_by = None
                    end_pending_at       = 0.0
                    session              = None
                    crash_restart_count  = 0

    finally:
        restore_tty()


if __name__ == "__main__":
    _args = sys.argv[1:]
    if "--doctor" in _args:
        sys.exit(run_doctor())
    elif "--permissions" in _args:
        sys.exit(run_permissions())
    elif "--stop" in _args:
        sys.exit(run_stop())
    elif "--index" in _args:
        sys.exit(run_index())
    else:
        main()
