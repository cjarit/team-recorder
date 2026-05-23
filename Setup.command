#!/bin/bash
# Setup.command — ดับเบิ้ลคลิกเพื่อติดตั้ง Teams Auto-Recorder
# ไม่ต้องพิมพ์คำสั่งใน Terminal — คลิกไฟล์นี้แล้วรอ

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

bash setup.sh

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  กด Enter เพื่อปิดหน้าต่างนี้"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read
