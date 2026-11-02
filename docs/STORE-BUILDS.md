# Generating the Connect IQ store builds

There are **two store listings of the same app**, built from the same source with different app ids:

| Listing | Manifest | Jungle | App id | Store name |
|---|---|---|---|---|
| **Official** | `manifest-official.xml` | `official.jungle` | `ded131ecb69d46493650153aef623be6` | **faBolus** |
| **Beta** | `manifest.xml` | `monkey.jungle` | `a1b2c3d4e5f600112233445566778899` | **faBolus (Beta)** |

**Build BOTH every release** — they are separate store submissions and both need to be kept current:

- **Official** → a fresh version of the main "faBolus" listing.
- **Beta** → a fresh version of the existing "faBolus (Beta)" listing.

The iPhone app talks to the beta listing's app id unless its build sets `GARMIN_BETA_APP_ID` to a
personal beta's (below). The official listing is dormant for now.

## Prerequisites

- Connect IQ SDK (currently 9.2.0). `MONKEYC` below points at its `bin/monkeyc`.
- The **store signing key** `~/garmin_dev_key.der` (do NOT use `developer_key.der`, which is the
  sideload key — the store requires the registered store key).

```sh
MONKEYC="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/monkeyc"
KEY="$HOME/garmin_dev_key.der"
```

## Build both store packages (`-e -r` = export/release, all products in the manifest)

Stamp the build commit first. It is what the watch's Details `App:` row shows, so it is how you identify
this exact upload later from a device report — and the app does not compile without it (the stamp is
generated and git-ignored; see [`scripts/stamp-revision.sh`](../scripts/stamp-revision.sh)). A trailing
`+` in its output means the tree was dirty, so the hash alone does not describe what you are uploading.

Then check that the version matches the phone release the contract is pinned to (`contract/PIN` should
be the faBolus release commit):

```sh
./scripts/stamp-revision.sh
./scripts/check-version-sync.sh
```

```sh
# OFFICIAL — upload as a new/updated version of the "faBolus" listing
"$MONKEYC" -f official.jungle -o bin/faBolus-official.iq -y "$KEY" -e -r

# BETA — upload as a new version of the existing "faBolus (Beta)" listing
"$MONKEYC" -f monkey.jungle   -o bin/faBolus-beta.iq     -y "$KEY" -e -r
```

Both bundle exactly one device on `main`: `venu3s` (add a device back by adding its `<iq:product>` to
**both** manifests — builds for other devices are on the `archive/dev/garmin-devices` tag).

## Personal beta (a unique app id per person) — one command

The Connect IQ store requires a **unique app id for every beta listing**, even a private one on your
own account — so two people can't both upload the shared beta id above. To publish your own:

```sh
./scripts/beta-build.sh
```

That's it. The script:

1. Generates your personal app id the **first** time (saved in `.beta-app-id`, gitignored) and reuses
   it on every later build — regenerating would orphan your listing and unpair your phone.
2. Builds a store-ready **`bin/faBolus-beta-personal.iq`** signed with your key, and reveals it in Finder.
3. **Automatically points the iPhone app at your id** — writes `GARMIN_BETA_APP_ID` into
   `../faBolus/LocalConfig.xcconfig` and regenerates its Xcode project. No files to edit, and no
   debug-panel toggle: a build configured with a personal beta id targets it automatically.

It checks the two Garmin prerequisites first (the Connect IQ SDK and your signing key at
`~/garmin_dev_key.der`) with setup guidance if either is missing. Override paths with
`MONKEYC=… KEY=… FABOLUS_DIR=… ./scripts/beta-build.sh`. A personal beta can be signed with any developer
key you keep (the faBolus build guide passes the one it makes, `KEY=../developer_key.der`); every later
upload of the same beta must use the same key.

**Two manual steps remain** (Garmin/Apple don't allow automating them):

- In Xcode, open `faBolus.xcodeproj` and Run to put the updated app on your iPhone.
- Upload the revealed `.iq` at the Connect IQ dashboard, then install it to your watch from the Garmin
  Connect IQ Store app.

## Upload

Connect IQ dashboard → each listing → upload the matching `.iq`. The **official** id is a *new*
store app the first time (create the listing); the **beta** id updates the existing listing.

> Sideload (on-device testing) uses `developer_key.der` and omits `-e -r`, e.g.
> `"$MONKEYC" -f official.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s`.
