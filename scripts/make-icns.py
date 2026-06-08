#!/usr/bin/env python3
import struct
import sys
from pathlib import Path


ICON_TYPES = {
    "icon_16x16.png": "icp4",
    "icon_16x16@2x.png": "icp5",
    "icon_32x32.png": "icp5",
    "icon_32x32@2x.png": "icp6",
    "icon_128x128.png": "ic07",
    "icon_128x128@2x.png": "ic08",
    "icon_256x256.png": "ic08",
    "icon_256x256@2x.png": "ic09",
    "icon_512x512.png": "ic09",
    "icon_512x512@2x.png": "ic10",
}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: make-icns.py <iconset-dir> <output.icns>", file=sys.stderr)
        return 2

    iconset_dir = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    chunks = []

    # Prefer the higher-resolution representation when duplicate ICNS slots exist.
    for filename in (
        "icon_16x16.png",
        "icon_16x16@2x.png",
        "icon_32x32@2x.png",
        "icon_128x128.png",
        "icon_128x128@2x.png",
        "icon_256x256@2x.png",
        "icon_512x512@2x.png",
    ):
        data = (iconset_dir / filename).read_bytes()
        icon_type = ICON_TYPES[filename].encode("ascii")
        chunks.append(icon_type + struct.pack(">I", len(data) + 8) + data)

    total_size = 8 + sum(len(chunk) for chunk in chunks)
    output_path.write_bytes(b"icns" + struct.pack(">I", total_size) + b"".join(chunks))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
