#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'portable checksum fixture\n' > "$TMP/example.dmg"
"$ROOT/scripts/write-checksum.sh" "$TMP/example.dmg"

if grep -Fq "$TMP" "$TMP/example.dmg.sha256"; then
  printf '%s\n' "checksum contains a non-portable absolute path" >&2
  exit 1
fi

(
  cd "$TMP"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c example.dmg.sha256
  else
    shasum -a 256 -c example.dmg.sha256
  fi
)

printf '%s\n' "portable checksum test passed"
