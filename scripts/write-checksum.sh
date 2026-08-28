#!/bin/bash
set -euo pipefail

FILE="${1:?file path is required}"
DIR="$(cd "$(dirname "$FILE")" && pwd)"
NAME="$(basename "$FILE")"

cd "$DIR"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$NAME" > "$NAME.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$NAME" > "$NAME.sha256"
else
  printf '%s\n' "No SHA-256 utility found." >&2
  exit 127
fi
