#!/usr/bin/env bash
#
# The Garmin build + unit-test harness (master-plan P6). This is a LOCAL developer gate, not a CI job,
# and that is a recorded decision, not an omission — see the "Why local, not CI" note below and
# .github/workflows/ci.yml.
#
# It compiles every jungle and runs the Monkey C unit suite in the Connect IQ simulator. Run it before
# opening a PR that touches Garmin code; CI cannot (it has no SDK and no display).
#
#   ./scripts/build-and-test.sh              # compile all jungles + run unit tests
#   ./scripts/build-and-test.sh --no-tests   # compile only (skip the simulator step)
#
# Env overrides:
#   CIQ_SDK=/path/to/connectiq-sdk-...   # default: newest SDK under ~/Library/Application Support/Garmin
#   CIQ_KEY=/path/to/developer_key.der   # default: ./developer_key.der
#
# Why local, not CI
# -----------------
# Three independent walls, any one of which is decisive:
#   1. The Connect IQ SDK is license-gated; its EULA does not permit committing or caching it in public
#      CI, and it has no unattended installer. `monkeyc` cannot run in CI without it.
#   2. `monkeydo` runs the unit tests inside the GUI simulator, which needs a display. GitHub runners
#      are headless, so the unit tests cannot run there at all — a technical wall, not just licensing.
#   3. The two SHIPPING jungles (monkey.jungle, official.jungle) require barrels/EatingSense.barrel,
#      built from the private faBolusNudge SDK and git-ignored — the same credential wall that forces
#      FABOLUS_NUDGE=0 on the iOS side. CI cannot produce it.
# CI's Garmin coverage is therefore the CONTRACT: schema-drift against faBolus's command.schema.json
# (see ci.yml), which needs no SDK. Compilation and unit tests are this script, run by a developer who
# has the SDK. Faking a green Garmin build badge in CI would be worse than an honest, scoped gate.
#
# monkeydo's exit code is UNRELIABLE (it returns nonzero even when every test passes), so this script
# decides pass/fail by PARSING the "PASSED (passed=N, failed=0, errors=0)" line, never the exit code.
set -uo pipefail
cd "$(dirname "$0")/.."

# --- locate the SDK ---------------------------------------------------------
SDK="${CIQ_SDK:-}"
if [ -z "$SDK" ]; then
  SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"connectiq-sdk-* 2>/dev/null | sort | tail -1)"
fi
if [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
  echo "❌ Connect IQ SDK not found. Install it (SDK Manager) or set CIQ_SDK=/path/to/connectiq-sdk-..." >&2
  exit 2
fi
MONKEYC="$SDK/bin/monkeyc"; MONKEYDO="$SDK/bin/monkeydo"; CONNECTIQ="$SDK/bin/connectiq"
KEY="${CIQ_KEY:-developer_key.der}"
[ -f "$KEY" ] || { echo "❌ signing key '$KEY' not found (set CIQ_KEY)." >&2; exit 2; }
echo "SDK: $SDK"

OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
FAIL=0

# --- compile matrix ---------------------------------------------------------
# Barrel-free jungles → their hardware-validated device (venu3s is the common one; each carries its own
# manifest). `-w` treats warnings as errors for the two that ship as .iq resources.
compile() {  # <jungle> <device> [extra args...]
  local j="$1" d="$2"; shift 2
  if "$MONKEYC" -f "$j.jungle" -o "$OUT/$j-$d.prg" -y "$KEY" -d "$d" "$@" >"$OUT/$j-$d.log" 2>&1; then
    echo "  ✅ $j.jungle  ($d)"
  else
    echo "  ❌ $j.jungle  ($d)"; grep -iE "error|exception" "$OUT/$j-$d.log" | head -3; FAIL=1
  fi
}

echo "== barrel-free jungles =="
compile datafield  venu3s -w
compile watchface  venu3s -w
compile probe      venu3s
compile direct-cgm venu3s
compile test       venu3s

echo "== shipping jungles (need barrels/EatingSense.barrel) =="
if [ -f barrels/EatingSense.barrel ]; then
  # fr245 is the lowest-capability declared device (CIQ 3.3, no Complications module → its complication
  # publisher is compiled out via the jungle's nocomplications split). Building it here is the point.
  compile monkey venu3s
  compile monkey fr245
else
  echo "  ⏭  skipped: barrels/EatingSense.barrel absent (private faBolusNudge SDK). This is expected"
  echo "     off a dev machine that has the Nudge SDK; the shipping app cannot be built without it."
fi

# --- unit tests (simulator) -------------------------------------------------
if [ "${1:-}" != "--no-tests" ]; then
  echo "== unit tests (Connect IQ simulator) =="
  if "$MONKEYC" -f test.jungle --unit-test -o "$OUT/test-ut.prg" -y "$KEY" -d venu3s >"$OUT/ut-build.log" 2>&1; then
    # monkeydo needs the simulator running; launch it, wait for its listening socket, then run tests.
    "$CONNECTIQ" >"$OUT/sim.log" 2>&1 &
    SIMPID=$!
    for _ in $(seq 1 30); do lsof -iTCP -sTCP:LISTEN -a -p "$SIMPID" >/dev/null 2>&1 && break; sleep 1; done
    "$MONKEYDO" "$OUT/test-ut.prg" venu3s -t >"$OUT/monkeydo.log" 2>&1 || true   # exit code is unreliable
    osascript -e 'quit app "ConnectIQ"' >/dev/null 2>&1 || kill "$SIMPID" 2>/dev/null || true
    sed -n '/^RESULTS/,$p' "$OUT/monkeydo.log"
    if grep -qE "PASSED \(passed=[0-9]+, failed=0, errors=0\)" "$OUT/monkeydo.log"; then
      echo "  ✅ unit tests passed"
    else
      echo "  ❌ unit tests did not pass (or the simulator did not report) — see output above"; FAIL=1
    fi
  else
    echo "  ❌ unit-test binary failed to build"; tail -5 "$OUT/ut-build.log"; FAIL=1
  fi
else
  echo "== unit tests skipped (--no-tests) =="
fi

echo
if [ "$FAIL" = 0 ]; then echo "✅ Garmin build+test OK"; else echo "❌ Garmin build+test FAILED"; fi
exit $FAIL
