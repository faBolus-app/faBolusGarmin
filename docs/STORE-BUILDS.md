# Generating the Connect IQ store builds

There are **two store listings of the same app**, built from the same source with different app ids:

| Listing | Manifest | Jungle | App id | Store name |
|---|---|---|---|---|
| **Official** | `manifest-official.xml` | `official.jungle` | `ded131ecb69d46493650153aef623be6` | **faBolus** |
| **Beta** | `manifest.xml` | `monkey.jungle` | `a1b2c3d4e5f600112233445566778899` | **faBolus (Beta)** |

**Build BOTH every release** — they are separate store submissions and both need to be kept current:
- **Official** → a fresh version of the main "faBolus" listing.
- **Beta** → a fresh version of the existing "faBolus (Beta)" listing.

The iPhone app's developer panel (Settings → About → tap disclaimer 7× → Debug → Garmin target app)
selects which one it pairs with; it **defaults to Official**.

## Prerequisites
- Connect IQ SDK (currently 9.2.0). `MONKEYC` below points at its `bin/monkeyc`.
- The **store signing key** `~/garmin_dev_key.der` (do NOT use `developer_key.der`, which is the
  sideload key — the store requires the registered store key).

```sh
MONKEYC="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/monkeyc"
KEY="$HOME/garmin_dev_key.der"
```

## Build both store packages (`-e -r` = export/release, all products in the manifest)

```sh
# OFFICIAL — upload as a new/updated version of the "faBolus" listing
"$MONKEYC" -f official.jungle -o bin/faBolus-official.iq -y "$KEY" -e -r

# BETA — upload as a new version of the existing "faBolus (Beta)" listing
"$MONKEYC" -f monkey.jungle   -o bin/faBolus-beta.iq     -y "$KEY" -e -r
```

Both bundle all six devices: `venu3s, fr265s, fenix7, fr245, edge540, edge1040` (add a device by
adding its `<iq:product>` to **both** manifests). `fr245` (Forerunner 245, CIQ 3.3) has no
Complications module, so its complication publisher is compiled out via `fr245.excludeAnnotations =
complications` in both jungles (the rest of the app runs normally on its button-confirm path).

## Personal beta (self-compilers) — a unique app id per person

The Connect IQ store requires a **unique app id for every beta listing**, even a private one under your
own account — so two people can't both upload the shared beta id above. To publish your own private
beta and sideload it to your watch via the store:

```sh
./scripts/beta-build.sh
```

It generates a fresh app id the **first** time (saved in `.beta-app-id`, gitignored) and reuses it on
every later build — regenerating would orphan your listing and unpair your phone. It writes a local
manifest + jungle with that id and builds `bin/faBolus-beta-personal.iq`. Override the SDK/key paths
with `MONKEYC=… KEY=… ./scripts/beta-build.sh` (defaults to `~/garmin_dev_key.der`).

Then point the **iPhone app** at the same id: the script prints a `GARMIN_BETA_APP_ID` value — set it
in `faBolus/LocalConfig.xcconfig`, rebuild the iPhone app, and choose the **beta** Garmin target in the
app's debug panel. Upload the `.iq` to the Connect IQ dashboard as your private beta listing.

## Companion watch face + data field (separate Connect IQ apps, optional)
These are their own store submissions (one shared build each — no beta/official split):

```sh
"$MONKEYC" -f watchface.jungle -o bin/faBolusFace.iq  -y "$KEY" -e -r
"$MONKEYC" -f datafield.jungle  -o bin/faBolusField.iq -y "$KEY" -e -r
```

## Upload
Connect IQ dashboard → each listing → upload the matching `.iq`. The **official** id is a *new*
store app the first time (create the listing); the **beta** id updates the existing listing.

> Sideload (on-device testing) uses `developer_key.der` and omits `-e -r`, e.g.
> `"$MONKEYC" -f official.jungle -o bin/faBolus.prg -y developer_key.der -d fr265s`.
