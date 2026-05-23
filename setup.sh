#!/bin/bash
# setup-v2.sh — Teams Recorder v2 built-in recorder setup
# รัน: bash v2/setup-v2.sh  หรือ  make setup-v2

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC}  $1"; }
info() { echo -e "${BLUE}  →${NC}  $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC}  $1"; }
fail() { echo -e "${RED}  ✗${NC}  $1"; }
step() { echo -e "\n${BOLD}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
RECORDER_BIN="$SCRIPT_DIR/recorder/recorder"
ENV_FILE="$SCRIPT_DIR/.env"

echo ""
echo -e "${BOLD}=================================================${NC}"
echo -e "${BOLD}  Teams Recorder v2 — Setup${NC}"
echo -e "${BOLD}=================================================${NC}"
echo ""

# ─── 1/6  macOS ───────────────────────────────────────────────
step "1/6  ตรวจสอบ macOS"
if [[ "$(uname)" != "Darwin" ]]; then
  fail "สคริปต์นี้รองรับเฉพาะ macOS เท่านั้น"
  exit 1
fi

MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 13 ]]; then
  fail "ต้องการ macOS 13 (Ventura) ขึ้นไป — เครื่องนี้ใช้ macOS $MACOS_VER"
  exit 1
fi
ok "macOS $MACOS_VER"

# ─── 2/6  Homebrew ────────────────────────────────────────────
step "2/6  ตรวจสอบ Homebrew"
if ! command -v brew &>/dev/null; then
  fail "Homebrew ยังไม่ได้ติดตั้ง — ติดตั้งก่อนด้วย https://brew.sh แล้วรัน setup-v2 อีกครั้ง"
  exit 1
fi
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ─── 3/6  Dependencies ────────────────────────────────────────
step "3/6  ติดตั้ง dependencies (python, ical-buddy)"
for pkg in python ical-buddy; do
  if brew list "$pkg" &>/dev/null; then
    ok "$pkg (มีอยู่แล้ว)"
  else
    info "กำลังติดตั้ง $pkg..."
    brew install "$pkg"
    ok "$pkg"
  fi
done

PYTHON_BIN=$(brew --prefix python)/bin/python3
if [[ ! -f "$PYTHON_BIN" ]]; then
  PYTHON_BIN=python3
fi

info "ติดตั้ง Python packages..."
"$PYTHON_BIN" -m pip install -q --break-system-packages python-dotenv pytest 2>&1 \
  | grep -v "WARNING: Cache entry" || true
ok "python-dotenv, pytest (Python $("$PYTHON_BIN" --version | awk '{print $2}'))"

# ─── 4/6  recorder binary ─────────────────────────────────────
step "4/6  ตรวจสอบ recorder binary"
NEED_BUILD=0
if [[ ! -x "$RECORDER_BIN" ]]; then
  warn "ไม่พบ recorder binary: $RECORDER_BIN"
  NEED_BUILD=1
else
  MACHINE="$(uname -m)"
  if ! file "$RECORDER_BIN" | grep -q "$MACHINE"; then
    warn "recorder binary arch ไม่ตรงกับเครื่องนี้ ($MACHINE)"
    NEED_BUILD=1
  elif ! "$RECORDER_BIN" --check >/dev/null 2>&1; then
    warn "recorder --check ไม่ผ่าน"
    NEED_BUILD=1
  else
    ok "recorder binary พร้อมใช้งาน ($MACHINE)"
  fi
fi

if [[ "$NEED_BUILD" -eq 1 ]]; then
  if ! command -v swift &>/dev/null; then
    fail "ไม่พบ Swift compiler — ติดตั้ง Xcode Command Line Tools: xcode-select --install"
    exit 1
  fi
  info "กำลัง build recorder..."
  (cd "$ROOT_DIR" && make build-recorder)
  ok "recorder rebuilt"
fi

# ─── 5/6  v2/.env ─────────────────────────────────────────────
step "5/6  ตั้งค่า v2/.env"

# Helper: write a key=value into ENV_FILE (replaces existing line)
set_env_key() {
  local key="$1" val="$2"
  # Use python to do safe in-place replacement (avoids sed escaping issues)
  "$PYTHON_BIN" - "$ENV_FILE" "$key" "$val" <<'PYEOF'
import sys, re
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
text = re.sub(r'^' + re.escape(key) + r'=.*', key + '=' + val, text, flags=re.MULTILINE)
open(path, 'w').write(text)
PYEOF
}

if [[ -f "$ENV_FILE" ]]; then
  warn "v2/.env มีอยู่แล้ว — เข้าสู่โหมดแก้ไข"
else
  cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "สร้าง v2/.env แล้ว"
fi

# ── โฟลเดอร์บันทึก ──────────────────────────────────────────
echo ""
CURRENT_DIR=$(grep '^RECORDING_DIR=' "$ENV_FILE" | cut -d= -f2-)
DEFAULT_DIR="${CURRENT_DIR:-$HOME/Documents/Teams Recording}"
echo -e "  ${BOLD}โฟลเดอร์บันทึกไฟล์${NC}"
echo "  ปัจจุบัน: $DEFAULT_DIR"
echo -n "  พิมพ์ path ใหม่หรือกด Enter เพื่อใช้ค่าเดิม: "
# flush stdin ก่อน read เพื่อป้องกัน buffered input จาก pip
while read -r -t 0 _; do :; done
IFS= read -r REC_DIR </dev/tty
REC_DIR="${REC_DIR:-$DEFAULT_DIR}"
# ขยาย ~ เป็น path จริง
REC_DIR="${REC_DIR/#\~/$HOME}"
mkdir -p "$REC_DIR"
set_env_key "RECORDING_DIR" "$REC_DIR"
ok "RECORDING_DIR → $REC_DIR"

# ── Mic device ──────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Microphone input device${NC}"
echo "  กำลังโหลด device list..."

# อ่าน input-only devices จาก --list-devices
DEVICE_LINES=()
while IFS= read -r line; do
  if [[ "$line" == *"[input"* ]]; then
    DEVICE_LINES+=("$line")
  fi
done < <("$RECORDER_BIN" --list-devices 2>/dev/null)

echo ""
echo "  0)  ใช้ default mic ของเครื่อง"
for i in "${!DEVICE_LINES[@]}"; do
  # แสดงเฉพาะชื่อ (ตัด UID ออก) ให้อ่านง่าย
  DISPLAY_NAME=$(echo "${DEVICE_LINES[$i]}" | cut -f2-)
  printf "  %d)  %s\n" "$((i+1))" "$DISPLAY_NAME"
done

echo ""
echo -n "  เลือกหมายเลข [0]: "
while read -r -t 0 _; do :; done
IFS= read -r CHOICE </dev/tty
CHOICE="${CHOICE:-0}"

if [[ "$CHOICE" == "0" ]] || [[ -z "$CHOICE" ]]; then
  set_env_key "AUDIO_INPUT_DEVICE_UID" ""
  ok "ใช้ default mic"
elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [[ "$CHOICE" -ge 1 ]] && [[ "$CHOICE" -le "${#DEVICE_LINES[@]}" ]]; then
  SELECTED_LINE="${DEVICE_LINES[$((CHOICE-1))]}"
  SELECTED_UID=$(echo "$SELECTED_LINE" | cut -f1)
  SELECTED_NAME=$(echo "$SELECTED_LINE" | cut -f2-)
  set_env_key "AUDIO_INPUT_DEVICE_UID" "$SELECTED_UID"
  ok "Mic → $SELECTED_NAME"
else
  warn "ตัวเลขไม่ถูกต้อง — ใช้ default mic"
  set_env_key "AUDIO_INPUT_DEVICE_UID" ""
fi

# ─── 6/6  Screen Recording permission ────────────────────────
step "6/6  Screen Recording permission"

# ตรวจว่า Terminal มีสิทธิ์แล้วหรือยัง (ลอง SCK แบบ quick check)
if "$RECORDER_BIN" --check >/dev/null 2>&1; then
  PERM_OK=$("$RECORDER_BIN" --request-permission 2>&1 || true)
fi

warn "ตรวจสอบว่าได้เปิดสิทธิ์ Screen Recording ให้ Terminal แล้ว"
echo "  System Settings → Privacy & Security → Screen Recording → Terminal ✓"
echo "  ถ้าเพิ่งเปิดสิทธิ์ ให้ปิด/เปิด Terminal ใหม่ก่อนรัน v2"

# ─── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ══════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Setup v2 เสร็จแล้ว ✓${NC}"
echo -e "${GREEN}${BOLD}  ══════════════════════════════════════${NC}"
echo ""
echo "  รัน v2:    make run"
echo "  ทดสอบ:    make test"
echo "  แก้ config: $ENV_FILE"
echo ""
