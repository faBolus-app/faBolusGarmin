#!/usr/bin/env bash
# Fails if AppVersion.NAME drifts from faBolus's MARKETING_VERSION.
#
# faBolusGarmin ships in lockstep with the app (BRANCHES.md §1.3), so source/app/AppVersion.mc's NAME is
# deliberately NOT independent — it mirrors faBolus/Config.xcconfig's MARKETING_VERSION. A version that
# can silently drift is worse than no version at all: the whole point of the Details row is to identify
# which build is on the wrist, and a stale NAME would identify it WRONGLY, which is harder to catch than
# a missing row. This is that guard.
#
# AppVersion.BUILD is intentionally NOT checked against anything: it is Garmin-local by design and is the
# field that actually distinguishes two watch builds of the same release. It is only sanity-checked here
# (and pinned by tests/AppVersionTest.mc) as a positive integer.
#
# The xcconfig path defaults to ../faBolus/Config.xcconfig (a sibling checkout); override with $XCCONFIG
# or the first argument. Mirrors scripts/check-schema-drift.sh's contract, including its exit codes:
#   0 = in sync (or skipped, when the sibling checkout is absent)   1 = drift   2 = bad invocation
set -euo pipefail
cd "$(dirname "$0")/.."

XCCONFIG="${XCCONFIG:-${1:-../faBolus/Config.xcconfig}}"
SRC="source/app/AppVersion.mc"

if [ ! -f "$SRC" ]; then
  echo "❌ $SRC not found — this script must run from the faBolusGarmin repo."
  exit 2
fi

code_name=$(grep -oE 'const[[:space:]]+NAME[[:space:]]*=[[:space:]]*"[^"]+"' "$SRC" \
            | grep -oE '"[^"]+"' | tr -d '"' | head -1)
code_build=$(grep -oE 'const[[:space:]]+BUILD[[:space:]]*=[[:space:]]*[0-9]+' "$SRC" \
            | grep -oE '[0-9]+' | head -1)

if [ -z "$code_name" ] || [ -z "$code_build" ]; then
  echo "❌ could not parse NAME/BUILD out of $SRC (was the constant renamed or reformatted?)"
  exit 2
fi

# BUILD must be a positive integer — a 0 or a negative would render as a meaningless "App: x.y.z (0)".
if [ "$code_build" -lt 1 ]; then
  echo "DRIFT: AppVersion.BUILD=$code_build — must be a positive integer (bumped per build)."
  exit 1
fi

# The sibling app checkout is optional: a Garmin-only clone must still be able to run its own checks.
# Skipping is reported loudly rather than silently passing, so a CI job that MEANT to check can spot it.
if [ ! -f "$XCCONFIG" ]; then
  echo "⚠️  SKIPPED the NAME↔MARKETING_VERSION check: no xcconfig at '$XCCONFIG'."
  echo "    (set \$XCCONFIG or pass the path; CI checks out faBolus alongside this repo)"
  echo "✅ AppVersion.BUILD=$code_build is a positive integer; NAME=$code_name unverified."
  exit 0
fi

app_name=$(grep -oE '^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*[^[:space:]]+' "$XCCONFIG" \
           | tail -1 | sed -E 's/.*=[[:space:]]*//')

if [ -z "$app_name" ]; then
  echo "❌ could not read MARKETING_VERSION from '$XCCONFIG'."
  exit 2
fi

if [ "$code_name" != "$app_name" ]; then
  echo "DRIFT: AppVersion.NAME=$code_name but faBolus MARKETING_VERSION=$app_name"
  echo "       faBolusGarmin tracks the app version in lockstep (BRANCHES.md §1.3)."
  echo "       Fix: set NAME = \"$app_name\" in $SRC (and bump BUILD)."
  exit 1
fi

echo "✅ version in sync: NAME=$code_name (== faBolus MARKETING_VERSION), BUILD=$code_build"
