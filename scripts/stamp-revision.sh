#!/usr/bin/env bash
#
# Writes source/generated/AppRevision.mc — the short commit hash the Details "App:" row displays.
#
# WHY A GENERATOR AND NOT A CONSTANT SOMEBODY EDITS
# ------------------------------------------------
# The row exists to answer "which binary is on the wrist?". A hand-maintained answer is worse than no
# answer, because the day somebody forgets to bump it two different binaries both claim the same version
# and the row starts lying. So the value is derived, not remembered.
#
# WHY A GENERATED FILE AND NOT A COMPILER FLAG
# --------------------------------------------
# Monkey C has no build-time codegen, and nothing in the toolchain can inject a string:
#   * `monkeyc` has no -D/--define and no preprocessor. Its only string-valued inputs are FILES
#     (see `monkeyc --help`: the sole conditional-compilation lever is -x/--excludes, which toggles
#     annotations — a boolean, not a value).
#   * The jungle language cannot help either. Its grammar (Jungle.g4, shipped inside monkeybrains.jar)
#     has exactly one substitution form, `$(lvalue)`, and `lvalue` resolves only to jungle qualifiers and
#     jungle-local variables — there is no environment-variable rule and no command substitution. The
#     assignable properties are manifest / typecheck / optimization / sourcePath / resourcePath / lang /
#     barrelPath / personality / excludeAnnotations, i.e. PATHS and ANNOTATIONS, never string constants.
#   * And Monkey C cannot read a file or shell out at runtime to discover it for itself.
# That leaves exactly one mechanism: write a source file onto a path the jungle already compiles, before
# monkeyc runs. This script is that write; the three app jungles carry `source/generated` on sourcePath.
#
# WHY THE VALUE IS NOT IN COMMITTED SOURCE
# ----------------------------------------
# It cannot be, as arithmetic rather than as preference. A commit's hash is a function of its contents,
# so storing HEAD's hash in a file that is part of that same commit is a fixed point you cannot compute.
# Any committed hash is therefore the hash of some EARLIER commit — permanently stale by at least one,
# which is precisely the failure this whole change exists to remove. So the stamp is git-ignored
# (source/generated/.gitignore) and regenerated per build, and the working tree stays clean on every
# build. scripts/check-version-sync.sh asserts it never becomes tracked.
#
# HONESTY RULES
#   * Uncommitted changes mean the hash alone is a lie — the tree does not match that commit. DIRTY=true
#     then, and the row renders a trailing "+".
#   * Outside a git checkout (a tarball, an exported source drop) the revision is genuinely unknown, so
#     the stamp says "unknown" rather than guessing. "unknown" contains no hex-only characters, so it can
#     never be mistaken for a real hash.
#
#   ./scripts/stamp-revision.sh            # write the stamp (idempotent; every build script calls this)
#   ./scripts/stamp-revision.sh --check    # verify the stamp on disk describes THIS tree; never writes
#
# --check exists so scripts/check-version-sync.sh can assert freshness WITHOUT re-implementing the
# derivation above. Both modes run the identical code path and differ only in what they do with the
# result, so the generator and its guard cannot drift apart — which would be the one way this mechanism
# could go quietly wrong.
#
# Exit codes mirror the other scripts here: 0 = stamped / fresh (or skipped), 1 = stale, 2 = bad
# invocation.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="source/generated/AppRevision.mc"
UNKNOWN="unknown"

MODE="write"
case "${1:-}" in
  "")       MODE="write" ;;
  --check)  MODE="check" ;;
  *)        echo "❌ usage: $0 [--check]"; exit 2 ;;
esac

if [ ! -d source/app ]; then
  echo "❌ source/app not found — this script must run from the faBolusGarmin repo."
  exit 2
fi

# Fixed-width by construction: `git rev-parse --short` may LENGTHEN its output to keep the abbreviation
# unique, which would quietly widen the Details row. Cutting the full hash pins the width, and the value
# is a debugging pointer rather than an identity proof, so uniqueness is not the property that matters.
short="$UNKNOWN"
dirty="false"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if full="$(git rev-parse HEAD 2>/dev/null)"; then
    short="$(printf '%s' "$full" | cut -c1-7)"
    # Untracked files count as dirty on purpose: an untracked .mc dropped into source/app IS compiled
    # into the binary, so the hash would not describe what shipped. Build products and keys are already
    # excluded by .gitignore, and the generated stamp excludes itself, so a clean tree stays clean.
    if [ -n "$(git status --porcelain)" ]; then
      dirty="true"
    fi
  fi
fi

mkdir -p "$(dirname "$OUT")"

# Written to a sibling temp file and moved into place so an interrupted run cannot leave a half-file that
# fails to compile, and so an unchanged stamp keeps its mtime (no needless rebuild churn).
tmp="$OUT.tmp"
trap 'rm -f "$tmp"' EXIT
{
  cat <<'HEADER'
// GENERATED FILE — do not edit, and do not commit it (source/generated is git-ignored).
//
// Rewritten by scripts/stamp-revision.sh immediately before every compile, so the Details "App:" row
// names the exact tree the binary was built from with nobody having to remember anything. See that
// script for why the value cannot live in committed source and cannot come from a compiler flag.
HEADER
  printf 'module AppRevision {\n\n'
  printf '    // Seven leading hex characters of the build commit, or "unknown" outside a git checkout.\n'
  printf '    const SHORT = "%s";\n\n' "$short"
  printf '    // True when the build tree carried uncommitted changes, so SHORT alone would misdescribe it.\n'
  printf '    const DIRTY = %s;\n' "$dirty"
  printf '}\n'
} > "$tmp"

# Spelled out as an if rather than folded into the assignment: under `set -e` a command substitution
# that exits nonzero (which `[ false = true ] && ...` does) takes the whole assignment — and the script —
# down with it. That failure is invisible precisely on a CLEAN tree, i.e. on a release build.
rendered="$short"
if [ "$dirty" = true ]; then
  rendered="$short+"
fi

if [ "$MODE" = "check" ]; then
  # Absent is reported loudly rather than failed: nothing has been built in this tree yet, so there is no
  # stamp to be wrong about, and the compile itself fails closed on the missing symbol if anyone tries.
  # A PRESENT-but-stale stamp is the dangerous case — that is a binary whose row names the wrong tree.
  if [ ! -f "$OUT" ]; then
    rm -f "$tmp"
    echo "⚠️  SKIPPED the revision-stamp check: no $OUT (nothing has been built in this tree)."
    echo "    A build cannot silently skip it — compiling without the stamp fails on 'Undefined symbol"
    echo "    :AppRevision'. Every build script here runs the generator first."
    exit 0
  fi
  if cmp -s "$tmp" "$OUT"; then
    rm -f "$tmp"
    echo "✅ revision stamp is fresh: $rendered"
    exit 0
  fi
  rm -f "$tmp"
  echo "DRIFT: $OUT does not describe this tree (expected $rendered)."
  echo "       The last build here was made from a different commit or a differently-dirty tree, so its"
  echo "       Details row names the wrong one. Fix: ./scripts/stamp-revision.sh (or just re-run"
  echo "       ./scripts/build-and-test.sh, which stamps before it compiles)."
  exit 1
fi

if [ -f "$OUT" ] && cmp -s "$tmp" "$OUT"; then
  rm -f "$tmp"
  echo "→ revision stamp unchanged: $rendered"
else
  mv "$tmp" "$OUT"
  echo "→ stamped $OUT: $rendered"
fi
