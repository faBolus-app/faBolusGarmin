#!/usr/bin/env bash
#
# Build the faBolus Garmin remote as YOUR OWN personal beta, with a unique Connect IQ app id.
#
# The Connect IQ store requires a distinct app id for every beta listing — even a private one tied to
# your own account. This script generates a fresh id the FIRST time (saved in .beta-app-id, gitignored)
# and reuses it on every later build: regenerating each time would orphan your store listing and unpair
# your phone. It writes a local manifest + jungle carrying that id and builds a store-ready .iq.
#
# IMPORTANT — point the iPhone app at the SAME id: set the value printed below as GARMIN_BETA_APP_ID in
# faBolus/LocalConfig.xcconfig, rebuild the iPhone app, and choose the "beta" Garmin target in its
# debug panel. Otherwise the phone talks to the shared beta id, not yours.
#
# Requires: the Connect IQ SDK and YOUR Garmin store signing key. Override paths via env: MONKEYC, KEY.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SDK_DEFAULT="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/monkeyc"
MONKEYC="${MONKEYC:-$SDK_DEFAULT}"
KEY="${KEY:-$HOME/garmin_dev_key.der}"
BASE_ID="a1b2c3d4e5f600112233445566778899"   # the committed beta id in manifest.xml (what we replace)
ID_FILE=".beta-app-id"
OUT="bin/faBolus-beta-personal.iq"

if [ ! -f "$ID_FILE" ]; then
  uuidgen | tr 'A-F' 'a-f' > "$ID_FILE"
  echo "→ Generated a new personal beta app id (saved in $ID_FILE; kept for future builds)."
fi
DASHED=$(tr -d '[:space:]' < "$ID_FILE")     # 8-4-4-4-12, for the iPhone (UUID string)
NODASH=$(echo "$DASHED" | tr -d '-')         # 32 hex, for the Garmin manifest id

# Local manifest + jungle carrying this id (both gitignored — see .gitignore).
sed "s/id=\"$BASE_ID\"/id=\"$NODASH\"/" manifest.xml > manifest-beta-local.xml
sed "s#project.manifest = manifest.xml#project.manifest = manifest-beta-local.xml#" monkey.jungle > beta-local.jungle

mkdir -p bin
"$MONKEYC" -f beta-local.jungle -o "$OUT" -y "$KEY" -e -r

echo ""
echo "✅ Built $OUT"
echo "   Garmin beta app id : $NODASH"
echo "   iPhone companion   : set  GARMIN_BETA_APP_ID = $DASHED  in faBolus/LocalConfig.xcconfig,"
echo "                        rebuild the iPhone app, and pick the 'beta' Garmin target."
echo "   Upload $OUT to the Connect IQ dashboard as your own (private) beta listing."
