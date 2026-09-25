#!/bin/bash
set -euo pipefail

MAX_FILE_BYTES=$((16 * 1024 * 1024))
MAX_DIMENSION=12000

fail() {
  echo "ABORT: invalid wallpaper media: $*" >&2
  exit 65
}

[[ $# -eq 1 ]] || fail "expected exactly one input path"
INPUT=$1
[[ -L "$INPUT" ]] && fail "symlink input is not allowed"
[[ -f "$INPUT" ]] || fail "input is not a regular file"
[[ -r "$INPUT" ]] || fail "input is not readable"

SIZE=$(wc -c < "$INPUT" | tr -d '[:space:]')
[[ "$SIZE" =~ ^[0-9]+$ ]] || fail "could not determine file size"
(( SIZE <= MAX_FILE_BYTES )) || fail "file is larger than ${MAX_FILE_BYTES} bytes"

PYTHON3="$(command -v python3 || true)"
[[ -n "$PYTHON3" ]] || fail "PNG parser runtime python3 is unavailable"

exec "$PYTHON3" - "$INPUT" "$SIZE" "$MAX_FILE_BYTES" "$MAX_DIMENSION" <<'PY'
import binascii
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

path, size_text, max_file_text, max_dimension_text = sys.argv[1:]
size = int(size_text)
max_file_bytes = int(max_file_text)
max_dimension = int(max_dimension_text)

def fail(message):
    print(f"ABORT: invalid wallpaper media: {message}", file=sys.stderr)
    raise SystemExit(65)

try:
    with open(path, "rb") as handle:
        payload = handle.read(max_file_bytes + 1)
except OSError as error:
    fail(f"could not read input: {error}")

if len(payload) != size:
    fail("input changed during validation")
if len(payload) < 33:
    fail("PNG is truncated")
if payload[:8] != b"\x89PNG\r\n\x1a\n":
    fail("PNG signature is missing")

offset = 8
seen_ihdr = False
seen_idat = False
closed_idat = False
seen_iend = False
width = height = 0
idat_parts = []

while offset < size:
    if size - offset < 12:
        fail("PNG chunk header or CRC is truncated")
    chunk_length = struct.unpack_from(">I", payload, offset)[0]
    end = offset + 12 + chunk_length
    if end > size:
        fail("PNG chunk exceeds file bounds")
    chunk_type = payload[offset + 4:offset + 8]
    if len(chunk_type) != 4 or not all(byte in range(65, 91) or byte in range(97, 123) for byte in chunk_type):
        fail("PNG chunk type is malformed")
    chunk_data = payload[offset + 8:offset + 8 + chunk_length]
    expected_crc = struct.unpack_from(">I", payload, offset + 8 + chunk_length)[0]
    actual_crc = binascii.crc32(chunk_type + chunk_data) & 0xffffffff
    if actual_crc != expected_crc:
        fail("PNG chunk CRC mismatch")

    if chunk_type == b"IHDR":
        if offset != 8 or seen_ihdr:
            fail("IHDR must be the first chunk")
        if chunk_length != 13:
            fail("first PNG chunk is not a 13-byte IHDR")
        width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk_data)
        if width == 0 or height == 0:
            fail("PNG dimensions must be non-zero")
        if width > max_dimension or height > max_dimension:
            fail(f"PNG dimensions exceed {max_dimension}px")
        if compression != 0 or filtering != 0 or interlace not in (0, 1):
            fail("PNG IHDR uses unsupported compression, filter, or interlace mode")
        seen_ihdr = True
    elif chunk_type == b"IDAT":
        if not seen_ihdr:
            fail("IDAT appears before IHDR")
        if closed_idat:
            fail("IDAT chunks are not contiguous")
        seen_idat = True
        idat_parts.append(chunk_data)
    elif chunk_type == b"IEND":
        if not seen_ihdr or not seen_idat:
            fail("IEND is missing required image data")
        if chunk_length != 0:
            fail("IEND must have an empty body")
        seen_iend = True
        offset = end
        if offset != size:
            fail("PNG contains trailing bytes after IEND")
        break
    else:
        if not seen_ihdr:
            fail("PNG contains a chunk before IHDR")
        if seen_idat:
            closed_idat = True
    offset = end

if not seen_ihdr or not seen_idat or not idat_parts or not seen_iend:
    fail("PNG is missing required IHDR, IDAT, or IEND structure")

# zlib validates the compressed IDAT stream independently of the native decoder.
# The compressed input is bounded by the 16 MiB file limit; decoded output is
# streamed into a temporary file with an explicit 512 MiB safety ceiling.
decoded_limit = 512 * 1024 * 1024
decoder = zlib.decompressobj()
decoded_bytes = 0
try:
    with tempfile.TemporaryFile() as decoded:
        for part in idat_parts:
            pending = part
            while pending:
                block = decoder.decompress(pending, 1024 * 1024)
                decoded.write(block)
                decoded_bytes += len(block)
                if decoded_bytes > decoded_limit:
                    fail("decoded PNG body exceeds 512 MiB safety limit")
                pending = decoder.unconsumed_tail
                if not pending:
                    break
        tail = decoder.flush()
        decoded.write(tail)
        decoded_bytes += len(tail)
except zlib.error:
    fail("PNG IDAT compressed body is invalid")
if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
    fail("PNG IDAT compressed body is incomplete or has trailing data")
if decoded_bytes == 0:
    fail("PNG IDAT decoded body is empty")

# sips conversion is an actual native decode, not metadata inspection. It is
# bounded to a temporary output and never writes the input.
sips = shutil.which("sips")
if not sips:
    fail("native image decoder sips is unavailable")
with tempfile.TemporaryDirectory(prefix="live-wallpaper-decode-") as directory:
    decoded_path = os.path.join(directory, "decoded.png")
    result = subprocess.run(
        [sips, "-s", "format", "png", path, "--out", decoded_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0 or not os.path.isfile(decoded_path) or os.path.getsize(decoded_path) == 0:
        fail("native image decoder rejected PNG body")

print(f"wallpaper media valid: {width}x{height}, {size} bytes (decoder=sips, idat_decoded={decoded_bytes})")
PY
