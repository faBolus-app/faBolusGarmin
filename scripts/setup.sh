#!/usr/bin/env bash
# One-time setup for a clone: installs the pre-push hook that runs every gate, including the Connect IQ
# build and unit tests that hosted CI cannot run (the SDK's license keeps it out of public CI, and the
# unit tests need the simulator's window). Push with --no-verify only for a push that changes no code.
set -euo pipefail
cd "$(dirname "$0")/.."
hook="$(git rev-parse --git-path hooks)/pre-push"
cat >"$hook" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check.sh"
HOOK
chmod +x "$hook"
echo "installed $hook"
