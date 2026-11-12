#!/usr/bin/env bash
# Vendors the phone↔remote contract from a faBolus commit into contract/ and records the commit in
# contract/PIN. The contract (Packages/RemoteProtocol/contract in faBolus) is the field reference, the
# JSON schema, the golden fixtures that faBolus's Swift writes, and the bolus calculator fixtures.
#
#   ./scripts/sync-contract.sh <commit> [faBolus checkout]    # default checkout: ../faBolus
#
# Update the pin whenever faBolus changes the contract, then run ./scripts/check.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

COMMIT="${1:?usage: sync-contract.sh <faBolus commit> [faBolus checkout]}"
FABOLUS="${2:-../faBolus}"
# Git on the faBolus checkout. A git hook runs with GIT_DIR (and in a worktree, an absolute one) naming this
# repository, which would point these commands here instead of at faBolus.
fabolus_git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR git -C "$FABOLUS" "$@"; }
SRC="Packages/RemoteProtocol/contract"

SHA="$(fabolus_git rev-parse --verify "$COMMIT^{commit}")"
rm -rf contract.new && mkdir contract.new
fabolus_git archive "$SHA" "$SRC" | tar -x -C contract.new --strip-components=3
[ -f contract.new/schema.json ] || { echo "❌ $SHA has no $SRC" >&2; rm -rf contract.new; exit 1; }
echo "$SHA" > contract.new/PIN
rm -rf contract && mv contract.new contract
echo "✅ contract/ is faBolus $SHA"
