#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/scripts/validate-wallpaper-asset.sh"
FIXTURES="$(mktemp -d "${TMPDIR:-/private/tmp}/live-wallpaper-media-fixtures.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_reject() {
  if "$HELPER" "$1" >/dev/null 2>&1; then
    fail "expected rejection: $2"
  fi
}

[[ -x "$HELPER" ]] || fail "validator is not executable"

# Generated deterministic 1x1 transparent PNG fixture; no user media is read.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' |
  base64 -D > "$FIXTURES/valid.png"
"$HELPER" "$FIXTURES/valid.png" | grep -Fq 'wallpaper media valid: 1x1' ||
  fail "valid generated PNG was not admitted"

VALID_SIZE=$(wc -c < "$FIXTURES/valid.png" | tr -d '[:space:]')

python3 - "$FIXTURES/realistic.png" <<'PY'
import binascii
import struct
import sys
import zlib

path = sys.argv[1]
width, height = 1920, 1080
state = 0x12345678
rows = []
for y in range(height):
    row = bytearray([0])
    for x in range(width):
        state = (state * 1664525 + 1013904223) & 0xffffffff
        row.extend(((state >> 24) & 0xff, (x + y) & 0xff, (x * 3 + y * 5) & 0xff))
    rows.append(bytes(row))

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b''.join(rows), 6))
png += chunk(b'IEND', b'')
open(path, 'wb').write(png)
PY

benchmark_log="$FIXTURES/benchmark.txt"
decode_log="$FIXTURES/decode.txt"
/usr/bin/time -p "$HELPER" "$FIXTURES/realistic.png" >"$decode_log" 2>"$benchmark_log"
grep -Eq '^real [0-9]+(\.[0-9]+)?$' "$benchmark_log" || fail "realistic PNG benchmark did not complete"
grep -Fq 'decoder=sips' "$decode_log" || fail "realistic PNG did not exercise native decode"
cat "$decode_log"
awk '$1 == "real" { print "realistic PNG validation benchmark: " $2 "s" }' "$benchmark_log"

python3 - "$FIXTURES/valid.png" "$FIXTURES/invalid-compressed-valid-crc.png" <<'PY'
import binascii
import struct
import sys

source, target = sys.argv[1:]
payload = open(source, 'rb').read()
output = payload[:8]
offset = 8
while offset < len(payload):
    length = struct.unpack_from('>I', payload, offset)[0]
    kind = payload[offset + 4:offset + 8]
    data = payload[offset + 8:offset + 8 + length]
    if kind == b'IDAT':
        data = b'\x78\x9c\x00'
    output += struct.pack('>I', len(data)) + kind + data
    output += struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)
    offset += length + 12
open(target, 'wb').write(output)
PY
expect_reject "$FIXTURES/invalid-compressed-valid-crc.png" "valid CRC but invalid compressed IDAT"

# The old header-only validator accepted this plausible IHDR with no IDAT/IEND.
head -c 33 "$FIXTURES/valid.png" > "$FIXTURES/ihdr-only.png"
expect_reject "$FIXTURES/ihdr-only.png" "IHDR-only body"

# Cut inside the known IDAT body and independently cut the IEND CRC.
head -c 45 "$FIXTURES/valid.png" > "$FIXTURES/body-truncated.png"
expect_reject "$FIXTURES/body-truncated.png" "truncated IDAT body"
head -c $(( VALID_SIZE - 4 )) "$FIXTURES/valid.png" > "$FIXTURES/end-truncated.png"
expect_reject "$FIXTURES/end-truncated.png" "truncated IEND"

cp "$FIXTURES/valid.png" "$FIXTURES/corrupt-ihdr-crc.png"
printf '%b' '\xff' | dd of="$FIXTURES/corrupt-ihdr-crc.png" bs=1 seek=29 conv=notrunc >/dev/null 2>&1
expect_reject "$FIXTURES/corrupt-ihdr-crc.png" "corrupt IHDR CRC"

cp "$FIXTURES/valid.png" "$FIXTURES/corrupt-idat-body.png"
printf '%b' '\xff' | dd of="$FIXTURES/corrupt-idat-body.png" bs=1 seek=41 conv=notrunc >/dev/null 2>&1
expect_reject "$FIXTURES/corrupt-idat-body.png" "corrupt IDAT body CRC"

cp "$FIXTURES/valid.png" "$FIXTURES/bad-signature.png"
printf 'notpng!' | dd of="$FIXTURES/bad-signature.png" bs=1 seek=0 conv=notrunc >/dev/null 2>&1
expect_reject "$FIXTURES/bad-signature.png" "bad signature"

head -c 20 "$FIXTURES/valid.png" > "$FIXTURES/truncated.png"
expect_reject "$FIXTURES/truncated.png" "truncated IHDR"

cp "$FIXTURES/valid.png" "$FIXTURES/zero-width.png"
printf '%b' '\x00\x00\x00\x00' | dd of="$FIXTURES/zero-width.png" bs=1 seek=16 conv=notrunc >/dev/null 2>&1
expect_reject "$FIXTURES/zero-width.png" "zero width"

cp "$FIXTURES/valid.png" "$FIXTURES/oversized-dimension.png"
printf '%b' '\x00\x00\x2e\xe1' | dd of="$FIXTURES/oversized-dimension.png" bs=1 seek=16 conv=notrunc >/dev/null 2>&1
expect_reject "$FIXTURES/oversized-dimension.png" "oversized width"

truncate -s 16777217 "$FIXTURES/oversized-file.png"
expect_reject "$FIXTURES/oversized-file.png" "oversized file"

ln -s valid.png "$FIXTURES/symlink.png"
expect_reject "$FIXTURES/symlink.png" "symlink input"
expect_reject "$FIXTURES/missing.png" "missing input"

grep -Fq 'validate-wallpaper-asset.sh' "$ROOT/build.command" ||
  fail "build does not invoke media validation"
if grep -Fq '$HOME/Pictures' "$ROOT/Sources/main.swift"; then
  fail "runtime still reads a user-home wallpaper path"
fi

echo "media validation contract PASS"
