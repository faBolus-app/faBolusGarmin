#!/usr/bin/env bash
# The quality gates. With no argument this runs them all.
#
#   scripts/check.sh                 # every gate
#   scripts/check.sh shell markdown  # just these
#
# Gates: build, shell, actions, markdown, contract.
# `build` is scripts/build-and-test.sh: it needs the Connect IQ SDK and the simulator, so it runs on a
# developer's Mac (the pre-push hook from scripts/setup.sh), never in hosted CI. CI runs the others.
# `contract` reads faBolus's v1 schema from ../faBolus unless SCHEMA points elsewhere.
set -euo pipefail
cd "$(dirname "$0")/.."

gate_build() { ./scripts/build-and-test.sh; }
gate_shell() { git ls-files -z '*.sh' | xargs -0 shellcheck; }
gate_actions() { actionlint; }
gate_markdown() { markdownlint-cli2; }
gate_contract() {
  ./scripts/check-schema-drift.sh
  ./scripts/check-sbom.sh
}

gates=("$@")
[ "${#gates[@]}" -gt 0 ] || gates=(build shell actions markdown contract)
for g in "${gates[@]}"; do
  echo "== $g"
  "gate_$g"
done
echo "all gates passed: ${gates[*]}"
