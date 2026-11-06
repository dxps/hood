#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
staging=$(mktemp -d /tmp/hood-icon.XXXXXX)
trap 'rm -rf "$staging"' EXIT
clang -fobjc-arc -framework AppKit scripts/make_icon.m -o "$staging/make-icon"
"$staging/make-icon" "$staging"
python3 - "$staging" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
entries = [('icp4',16,1), ('icp5',32,1), ('ic07',128,1), ('ic08',256,1), ('ic09',512,1),
           ('ic11',16,2), ('ic12',32,2), ('ic13',128,2), ('ic14',256,2), ('ic10',512,2)]
chunks = []
for kind, size, scale in entries:
    data = (root / f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png').read_bytes()
    chunks.append(kind.encode() + struct.pack('>I', len(data)+8) + data)
payload = b''.join(chunks)
pathlib.Path('source/assets/Hood.icns').write_bytes(b'icns' + struct.pack('>I',len(payload)+8) + payload)
pathlib.Path('source/assets/Hood.png').write_bytes((root/'icon_512x512@2x.png').read_bytes())
PY
