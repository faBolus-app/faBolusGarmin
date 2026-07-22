#!/usr/bin/env bash
#
# One command to publish faBolus to YOUR OWN Garmin watch as a private beta.
#
# The Connect IQ store needs a unique app id for every beta listing — even a private one on your own
# account — so nobody can reuse the shared beta id. This script does everything automatable:
#   1. Generates your personal app id the first time (saved in .beta-app-id; reused forever after, so
#      your store listing and phone pairing stay stable).
#   2. Builds a store-ready bin/faBolus-beta-personal.iq signed with your Garmin key.
#   3. Points the iPhone app at that id automatically (writes GARMIN_BETA_APP_ID into the faBolus repo's
#      LocalConfig.xcconfig and regenerates its Xcode project) — no files to edit by hand.
#   4. Reveals the .iq in Finder so you can upload it.
#
# Then only two manual steps remain (Garmin/Apple don't allow automating them):
#   • Rebuild the iPhone app in Xcode (Open faBolus.xcodeproj → Run) — it now targets your beta.
#   • Upload the .iq at the Connect IQ dashboard and install it to your watch from the Garmin app.
#
# Prereqs (both are Garmin requirements, one-time): the Connect IQ SDK, and your Garmin store signing
# key at ~/garmin_dev_key.der. Override paths with:  MONKEYC=… KEY=… FABOLUS_DIR=… ./scripts/beta-build.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SDK_DEFAULT="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/monkeyc"
MONKEYC="${MONKEYC:-$SDK_DEFAULT}"
KEY="${KEY:-$HOME/garmin_dev_key.der}"
FABOLUS_DIR="${FABOLUS_DIR:-../faBolus}"
BASE_ID="a1b2c3d4e5f600112233445566778899"   # the committed beta id in manifest.xml (what we replace)
ID_FILE=".beta-app-id"
OUT="bin/faBolus-beta-personal.iq"

# --- Friendly prerequisite checks ------------------------------------------------------------------
if [ ! -f "$MONKEYC" ]; then
  echo "❌ Connect IQ SDK not found. Expected the compiler at:"
  echo "     $MONKEYC"
  echo "   Install the Connect IQ SDK (developer.garmin.com/connect-iq/sdk), then either use its path"
  echo "   or re-run with:  MONKEYC=/path/to/bin/monkeyc ./scripts/beta-build.sh"
  exit 1
fi
if [ ! -f "$KEY" ]; then
  echo "❌ Garmin signing key not found at:  $KEY"
  echo "   You need a Garmin developer key (one-time). In the Connect IQ SDK / VS Code extension:"
  echo "   \"Generate a Developer Key\", save it to ~/garmin_dev_key.der (or re-run with KEY=/path/key.der)."
  exit 1
fi

# --- 1. Personal app id (generate once, reuse forever) --------------------------------------------
if [ ! -f "$ID_FILE" ]; then
  uuidgen | tr 'A-F' 'a-f' > "$ID_FILE"
  echo "→ Generated your personal beta app id (saved in $ID_FILE; reused on every future build)."
fi
DASHED=$(tr -d '[:space:]' < "$ID_FILE")     # 8-4-4-4-12, for the iPhone
NODASH=$(echo "$DASHED" | tr -d '-')         # 32 hex, for the Garmin manifest

# --- 2. Build the store .iq -----------------------------------------------------------------------
sed "s/id=\"$BASE_ID\"/id=\"$NODASH\"/" manifest.xml > manifest-beta-local.xml
sed "s#project.manifest = manifest.xml#project.manifest = manifest-beta-local.xml#" monkey.jungle > beta-local.jungle
mkdir -p bin
echo "→ Building your beta (all watch models)…"
"$MONKEYC" -f beta-local.jungle -o "$OUT" -y "$KEY" -e -r

# --- 3. Point the iPhone app at this id automatically ---------------------------------------------
if [ -d "$FABOLUS_DIR" ]; then
  LOCALCFG="$FABOLUS_DIR/LocalConfig.xcconfig"
  [ -f "$LOCALCFG" ] || { [ -f "$FABOLUS_DIR/LocalConfig.xcconfig.example" ] && cp "$FABOLUS_DIR/LocalConfig.xcconfig.example" "$LOCALCFG" || touch "$LOCALCFG"; }
  if grep -q '^[[:space:]]*GARMIN_BETA_APP_ID' "$LOCALCFG"; then
    sed -i '' "s#^[[:space:]]*GARMIN_BETA_APP_ID.*#GARMIN_BETA_APP_ID = $DASHED#" "$LOCALCFG"
  else
    printf 'GARMIN_BETA_APP_ID = %s\n' "$DASHED" >> "$LOCALCFG"
  fi
  echo "→ Set GARMIN_BETA_APP_ID in $LOCALCFG (the iPhone app will target your beta automatically)."
  if [ -x "$FABOLUS_DIR/scripts/generate-project.sh" ]; then
    (cd "$FABOLUS_DIR" && ./scripts/generate-project.sh >/dev/null 2>&1) && echo "→ Regenerated the iPhone Xcode project."
  fi
else
  echo "⚠️  Couldn't find the faBolus iPhone repo at '$FABOLUS_DIR'."
  echo "    Set  GARMIN_BETA_APP_ID = $DASHED  in faBolus/LocalConfig.xcconfig yourself,"
  echo "    or re-run with  FABOLUS_DIR=/path/to/faBolus ./scripts/beta-build.sh"
fi

# --- 4. Reveal the .iq + next steps ---------------------------------------------------------------
open -R "$OUT" 2>/dev/null || true
echo ""
echo "✅ Done. Your beta app id: $NODASH"
echo ""
echo "Two manual steps remain:"
echo "  1) In Xcode: open faBolus.xcodeproj and press Run to put the updated app on your iPhone."
echo "  2) Upload the revealed file ($OUT) at the Connect IQ dashboard"
echo "     (apps.garmin.com → sign in → your developer dashboard → new/updated beta app),"
echo "     then install it to your watch from the Garmin Connect IQ Store app."
