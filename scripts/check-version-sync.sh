#!/usr/bin/env bash
# Fails if AppVersion.NAME drifts from faBolus's MARKETING_VERSION, or if the Details row's build
# commit is stale or has crept into committed source.
#
# faBolusGarmin ships in lockstep with the app (BRANCHES.md §1.3), so source/app/AppVersion.mc's NAME is
# deliberately NOT independent — it mirrors faBolus/Config.xcconfig's MARKETING_VERSION. A version that
# can silently drift is worse than no version at all: the whole point of the Details row is to identify
# which build is on the wrist, and a stale NAME would identify it WRONGLY, which is harder to catch than
# a missing row. This is that guard.
#
# The OTHER half of the row — the build commit — is not a constant anyone maintains, so it needs a
# different kind of guard. It lives in source/generated/AppRevision.mc, rewritten from `git` by
# scripts/stamp-revision.sh before every compile. That mechanism has exactly two ways to go quietly
# wrong, and both are checked below:
#   1. The revision creeps back into COMMITTED source. It must never: a commit's hash is a function of
#      its own contents, so a committed hash can only ever be an earlier commit's — permanently stale.
#      That includes the old hand-incremented BUILD counter this replaced, whose failure mode was the
#      same lie by a slower route (forget to bump, and two binaries claim one version).
#   2. A stale generated stamp is left on disk and a bare `monkeyc` compiles it. Freshness is delegated
#      to `stamp-revision.sh --check`, which runs the generator's own derivation rather than a second
#      copy of it, so the guard cannot drift from the thing it guards.
#
# The xcconfig path defaults to ../faBolus/Config.xcconfig (a sibling checkout); override with $XCCONFIG
# or the first argument. Mirrors scripts/check-schema-drift.sh's contract, including its exit codes:
#   0 = in sync (or skipped, when the sibling checkout is absent)   1 = drift   2 = bad invocation
set -euo pipefail
cd "$(dirname "$0")/.."

XCCONFIG="${XCCONFIG:-${1:-../faBolus/Config.xcconfig}}"
SRC="source/app/AppVersion.mc"
STAMP="source/generated/AppRevision.mc"

if [ ! -f "$SRC" ]; then
  echo "❌ $SRC not found — this script must run from the faBolusGarmin repo."
  exit 2
fi

code_name=$(grep -oE 'const[[:space:]]+NAME[[:space:]]*=[[:space:]]*"[^"]+"' "$SRC" \
            | grep -oE '"[^"]+"' | tr -d '"' | head -1)

if [ -z "$code_name" ]; then
  echo "❌ could not parse NAME out of $SRC (was the constant renamed or reformatted?)"
  exit 2
fi

# --- the revision must not be a maintained constant ------------------------------------------------
if grep -qE 'const[[:space:]]+(BUILD|SHORT|REVISION|COMMIT|SHA|HASH)[[:space:]]*=' "$SRC"; then
  echo "DRIFT: $SRC declares a build/revision constant in COMMITTED source."
  echo "       The build commit is derived, never maintained — see the note at the top of this script."
  echo "       Fix: delete the constant; the row reads AppRevision from the generated stamp."
  exit 1
fi

# --- the generated stamp must stay generated -------------------------------------------------------
# source/generated/.gitignore makes this need an explicit `git add -f`, but a force-add is exactly how a
# frozen, silently-stale hash would enter the repo, so it is asserted rather than assumed.
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files --error-unmatch "$STAMP" >/dev/null 2>&1; then
    echo "DRIFT: $STAMP is TRACKED by git — it must be generated per build, never committed."
    echo "       A committed stamp freezes at one commit's hash and then misidentifies every later"
    echo "       build. Fix: git rm --cached $STAMP"
    exit 1
  fi
fi

# The sibling app checkout is optional: a Garmin-only clone must still be able to run its own checks.
# Skipping is reported loudly rather than silently passing, so a CI job that MEANT to check can spot it.
if [ ! -f "$XCCONFIG" ]; then
  echo "⚠️  SKIPPED the NAME↔MARKETING_VERSION check: no xcconfig at '$XCCONFIG'."
  echo "    (set \$XCCONFIG or pass the path; CI checks out faBolus alongside this repo)"
  echo "    NAME=$code_name unverified."
  ./scripts/stamp-revision.sh --check
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
  echo "       Fix: set NAME = \"$app_name\" in $SRC."
  exit 1
fi

echo "✅ version in sync: NAME=$code_name (== faBolus MARKETING_VERSION)"

# Last, because a stale stamp must not short-circuit the cross-repo NAME check above under `set -e`.
# Delegated rather than reimplemented: --check runs the generator's own derivation.
./scripts/stamp-revision.sh --check
