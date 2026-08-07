#!/usr/bin/env bash
# Fails if faBolusGarmin's provenance chain drifts from docs/SBOM.md.
#
# faBolusGarmin ships no vendored third-party runtime source, so (unlike faBolus's package-oriented
# check) this asserts the small, real surface it does have:
#   (1) the licensing/attribution files all exist (LICENSE, NOTICE.md, THIRD_PARTY.md, docs/SBOM.md);
#   (2) every barrel a shipping manifest depends on (<iq:depends name="…">) has a row in the SBOM —
#       catches a new bundled barrel slipping in undocumented;
#   (3) each third-party upstream attributed in NOTICE.md (pumpX2, G7SensorKit) also appears in the SBOM
#       — keeps the prose and the machine-checkable table in step.
#
# Reads only local files (no network, no sibling checkout), so it is independent of the schema-drift
# contract check and safe to run as a separate CI step.
set -euo pipefail
cd "$(dirname "$0")/.."

SBOM="docs/SBOM.md"
fail=0

# (1) required licensing/attribution files
for f in LICENSE NOTICE.md THIRD_PARTY.md "$SBOM"; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f is required for the provenance chain"; fail=1
  fi
done
# Nothing else is checkable without the SBOM present.
if [ ! -f "$SBOM" ]; then
  echo "❌ SBOM check failed — $SBOM is missing." >&2
  exit 1
fi

# (2) every declared barrel dependency must have an SBOM row
barrels=$(grep -hoE '<iq:depends[[:space:]]+name="[^"]+"' manifest*.xml 2>/dev/null \
          | sed -E 's/.*name="([^"]+)".*/\1/' | sort -u || true)
for b in $barrels; do
  if ! grep -q "$b" "$SBOM"; then
    echo "MISSING SBOM ENTRY: barrel '$b' is declared in a manifest but not listed in $SBOM"; fail=1
  fi
done

# (3) third-party upstreams attributed in NOTICE.md must also be in the SBOM
for upstream in pumpX2 G7SensorKit; do
  if grep -q "$upstream" NOTICE.md 2>/dev/null && ! grep -q "$upstream" "$SBOM"; then
    echo "DRIFT: NOTICE.md attributes '$upstream' but it has no row in $SBOM"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "❌ SBOM check failed — reconcile the component with $SBOM." >&2
  exit 1
fi
echo "✅ SBOM check passed: attribution files present, ${barrels:+barrel(s) [$(echo $barrels)] }and NOTICE upstreams accounted for in $SBOM."
