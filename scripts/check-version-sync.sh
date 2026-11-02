#!/usr/bin/env bash
# Fails if AppVersion.NAME differs from faBolus's MARKETING_VERSION, or if the build commit has crept
# into committed source.
#
#   ./scripts/check-version-sync.sh [faBolus checkout]    # default: $FABOLUS, else ../faBolus
#
# The watch app has no version of its own: it ships with the phone app, so source/app/AppVersion.mc's
# NAME mirrors faBolus's Config.xcconfig MARKETING_VERSION. It is compared with faBolus at the commit in
# contract/PIN, the phone app this watch app is built against, whatever that checkout has checked out.
# A missing checkout or pin fails rather than skips: the scripts/check.sh contract gate runs this, and
# CI checks faBolus out at the pin.
#
# The other half of the Details row, the build commit, is written per build by
# scripts/stamp-revision.sh into the git-ignored source/generated/AppRevision.mc. A committed hash could
# only ever be an earlier commit's, so this also fails if the stamp is tracked or AppVersion.mc declares
# a revision constant. Whether the stamp on disk is fresh is stamp-revision.sh --check, which
# build-and-test.sh runs before compiling.
#
# Exit codes: 0 = in sync, 1 = drift, 2 = can't check.
set -euo pipefail
cd "$(dirname "$0")/.."

FABOLUS="${1:-${FABOLUS:-../faBolus}}"
SRC="source/app/AppVersion.mc"
STAMP="source/generated/AppRevision.mc"

[ -f "$SRC" ] || { echo "❌ $SRC not found" >&2; exit 2; }
code_name=$(grep -oE 'const[[:space:]]+NAME[[:space:]]*=[[:space:]]*"[^"]+"' "$SRC" \
            | grep -oE '"[^"]+"' | tr -d '"' | head -1 || true)
[ -n "$code_name" ] || { echo "❌ could not read NAME from $SRC" >&2; exit 2; }

if grep -qE 'const[[:space:]]+(BUILD|SHORT|REVISION|COMMIT|SHA|HASH)[[:space:]]*=' "$SRC"; then
  echo "❌ $SRC declares a build or revision constant; the build commit comes from $STAMP" >&2
  exit 1
fi
# source/generated/.gitignore keeps the stamp out, but `git add -f` would get past it.
if git ls-files --error-unmatch "$STAMP" >/dev/null 2>&1; then
  echo "❌ $STAMP is tracked; it's written per build. Fix: git rm --cached $STAMP" >&2
  exit 1
fi

[ -f contract/PIN ] || { echo "❌ contract/PIN is missing" >&2; exit 2; }
PIN="$(tr -d '[:space:]' < contract/PIN)"
[[ "$PIN" =~ ^[0-9a-f]{40}$ ]] || { echo "❌ contract/PIN isn't a full commit hash: $PIN" >&2; exit 2; }
git -C "$FABOLUS" cat-file -e "$PIN^{commit}" 2>/dev/null \
  || { echo "❌ faBolus checkout at $FABOLUS doesn't have $PIN (fetch it, or set FABOLUS)" >&2; exit 2; }
app_name=$(git -C "$FABOLUS" show "$PIN:Config.xcconfig" \
           | grep -oE '^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*[^[:space:]]+' \
           | tail -1 | sed -E 's/.*=[[:space:]]*//' || true)
[ -n "$app_name" ] || { echo "❌ could not read MARKETING_VERSION from faBolus $PIN:Config.xcconfig" >&2; exit 2; }

if [ "$code_name" != "$app_name" ]; then
  echo "❌ AppVersion.NAME is $code_name, but faBolus $PIN has MARKETING_VERSION $app_name." >&2
  echo "   Set NAME = \"$app_name\" in $SRC, or sync contract/PIN to the faBolus release." >&2
  exit 1
fi
echo "✅ version $code_name matches faBolus MARKETING_VERSION at $PIN"
