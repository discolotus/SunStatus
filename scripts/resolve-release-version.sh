#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 && -n "${1:-}" ]]; then
    echo "$1"
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/project.yml"

if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "project.yml is missing; pass an explicit release version." >&2
    exit 1
fi

versions="$(
    sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?[[:space:]]*$/\1/p' "$PROJECT_FILE" \
        | sort -u
)"
version_count="$(printf '%s\n' "$versions" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$version_count" -ne 1 ]]; then
    echo "Expected exactly one MARKETING_VERSION in project.yml, found: ${versions:-none}" >&2
    exit 1
fi

version="$(printf '%s\n' "$versions" | sed '/^$/d' | head -1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release version must look like 1.2.3, got: $version" >&2
    exit 1
fi

echo "$version"
