#!/usr/bin/env bash
# Checks that contract/ is exactly faBolus's contract at the commit in contract/PIN: nothing edited here,
# nothing missing, nothing extra.
#
#   ./scripts/check-contract.sh [faBolus checkout]    # default: $FABOLUS, else ../faBolus
#
# CI checks out faBolus at the pinned commit and passes its path.
set -euo pipefail
cd "$(dirname "$0")/.."

FABOLUS="${1:-${FABOLUS:-../faBolus}}"
SRC="Packages/RemoteProtocol/contract"
[ -f contract/PIN ] || { echo "❌ contract/PIN is missing" >&2; exit 1; }
PIN="$(tr -d '[:space:]' < contract/PIN)"
[[ "$PIN" =~ ^[0-9a-f]{40}$ ]] || { echo "❌ contract/PIN isn't a full commit hash: $PIN" >&2; exit 1; }
git -C "$FABOLUS" cat-file -e "$PIN^{commit}" 2>/dev/null \
  || { echo "❌ faBolus checkout at $FABOLUS doesn't have $PIN (fetch it, or push it)" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git -C "$FABOLUS" archive "$PIN" "$SRC" | tar -x -C "$WORK" --strip-components=3
echo "$PIN" > "$WORK/PIN"
if ! diff -r "$WORK" contract >/dev/null; then
  echo "❌ contract/ differs from faBolus $PIN:" >&2
  diff -r "$WORK" contract >&2 || true
  echo "Run ./scripts/sync-contract.sh <commit> to update it." >&2
  exit 1
fi
echo "✅ contract/ matches faBolus $PIN ($(find contract/fixtures -name '*.json' | wc -l | tr -d ' ') fixtures)"
