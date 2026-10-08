#!/bin/bash
# สร้าง self-signed code-signing certificate ครั้งเดียว แล้ว import เข้า login keychain
# ใช้ sign ทุก build ให้ identity คงที่ → macOS ไม่ขอสิทธิ์ Screen Recording / Mic / Calendar ซ้ำหลัง upgrade
# private key ไม่เคยถูกเขียนลงใน repo — อยู่ใน temp dir ที่ลบทิ้งตอนจบ
set -euo pipefail

NAME="${1:-Team Recorder Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "  ✓  certificate '$NAME' already exists in login keychain"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
EOF

$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/req.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
$OPENSSL pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:tr

security import "$TMP/id.p12" -k "$KEYCHAIN" -P tr -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# trust สำหรับ code signing ในระดับ user — macOS อาจเด้งถาม authorize หนึ่งครั้ง
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "  ✓  created '$NAME' (10-year, code signing) in login keychain"
security find-identity -v -p codesigning | grep -F "$NAME" || \
  echo "  ⚠  identity not listed as valid yet — run: make cert-check"
