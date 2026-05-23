#!/bin/bash
# Double-click ไฟล์นี้เพื่อเริ่ม Teams Auto-Recorder
#
# เปิด menu bar app → app จะ start watcher อัตโนมัติ
# 'open' เป็น idempotent — ถ้า app รันอยู่แล้วจะไม่เปิดซ้ำ

# ไปยัง folder จริงของ script — รองรับ symlink บน Desktop
SOURCE="$0"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# ลอง /Applications/ ก่อน แล้ว fallback ไป build folder ใน repo
if [ -d "/Applications/TeamRecorderBar.app" ]; then
    open /Applications/TeamRecorderBar.app
elif [ -d "$SCRIPT_DIR/menu-bar/.build/TeamRecorderBar.app" ]; then
    open "$SCRIPT_DIR/menu-bar/.build/TeamRecorderBar.app"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  ยังไม่ได้ build menu bar app"
    echo "   เปิด Terminal แล้วรัน:  make menu-bar"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -r -p "กด Enter เพื่อปิด..."
fi
