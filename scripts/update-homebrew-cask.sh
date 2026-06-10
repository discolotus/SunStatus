#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: scripts/update-homebrew-cask.sh VERSION DMG_SHA256}"
DMG_SHA256="${2:?usage: scripts/update-homebrew-cask.sh VERSION DMG_SHA256}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_PATH="$ROOT_DIR/Casks/sunstatus.rb"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 1.2.3, got: $VERSION" >&2
    exit 1
fi

if [[ ! "$DMG_SHA256" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "DMG SHA-256 must be a 64-character hex string." >&2
    exit 1
fi

python3 - "$CASK_PATH" "$VERSION" "$DMG_SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3].lower()
text = path.read_text()
text = re.sub(r'version "[^"]+"', f'version "{version}"', text, count=1)
text = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha256}"', text, count=1)
path.write_text(text)
PY

echo "Updated $CASK_PATH for v$VERSION"
