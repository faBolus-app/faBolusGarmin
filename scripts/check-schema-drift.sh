#!/usr/bin/env bash
# Fails if this Garmin remote drifts from the phone↔remote contract schema
# (faBolus/schema/command.schema.json — the source of truth, which lives in the faBolus repo).
#
# The Garmin app consumes a SUBSET of the contract; schema/remote-keys.txt names exactly which keys.
# For each listed key this asserts:
#   (a) it still exists as a property in the schema        → catches a schema rename/removal
#   (b) it is still referenced in the Monkey C source      → catches a stale manifest
# It also checks that RemoteComm.mc's SCHEMA_VERSION equals the schema's version const.
#
# The schema path defaults to ../faBolus/schema/command.schema.json (a sibling checkout); override
# with $SCHEMA or the first argument. CI checks out faBolus alongside this repo and sets $SCHEMA.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEMA="${SCHEMA:-${1:-../faBolus/schema/command.schema.json}}"
KEYS="schema/remote-keys.txt"
SRC=(source/app/RemoteComm.mc source/app/AppState.mc)

if [ ! -f "$SCHEMA" ]; then
  echo "❌ schema not found at '$SCHEMA' — set \$SCHEMA or pass the path (CI checks out faBolus alongside)."
  exit 2
fi

fail=0

# (1) version const must match
schema_ver=$(python3 -c "import json;print(json.load(open('$SCHEMA'))['properties']['version']['const'])")
code_ver=$(grep -oE 'SCHEMA_VERSION *= *[0-9]+' source/app/RemoteComm.mc | grep -oE '[0-9]+' | head -1)
if [ "$schema_ver" != "$code_ver" ]; then
  echo "DRIFT: RemoteComm.mc SCHEMA_VERSION=$code_ver but schema version const=$schema_ver"
  fail=1
fi

# schema property names, one per line
props=$(python3 -c "import json;print('\n'.join(json.load(open('$SCHEMA'))['properties'].keys()))")

# (2) every declared key: present in schema AND referenced in source
count=0
while IFS= read -r line; do
  key="${line%%#*}"; key="$(printf '%s' "$key" | tr -d '[:space:]')"
  [ -z "$key" ] && continue
  count=$((count + 1))
  if ! grep -qx "$key" <<<"$props"; then
    echo "DRIFT: remote-keys.txt lists '$key' but it is not a property in the schema (renamed/removed?)"
    fail=1
  fi
  if ! grep -qE "\"$key\"" "${SRC[@]}"; then
    echo "DRIFT: '$key' is in remote-keys.txt but no longer referenced in the Monkey C source (stale manifest?)"
    fail=1
  fi
done < "$KEYS"

if [ "$fail" -ne 0 ]; then
  echo "❌ Garmin remote is out of sync with $SCHEMA. Update schema/remote-keys.txt and the Monkey C keys together."
  exit 1
fi
echo "✅ Garmin remote keys match $SCHEMA (schema version $schema_ver, $count keys)."
