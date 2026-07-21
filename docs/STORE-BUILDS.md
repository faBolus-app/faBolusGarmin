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

Both bundle all five devices: `venu3s, fr265s, fenix7, edge540, edge1040` (add a device by adding
its `<iq:product>` to **both** manifests).

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
