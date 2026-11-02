# Building the watch app

faBolus is self-built: there's no public listing, and the project doesn't publish the watch app. There is
one build, `monkey.jungle` with `manifest.xml` (app id `a1b2c3d4e5f600112233445566778899`, the id the
phone app targets by default), and two ways to put it on your watch. The step-by-step guide is faBolus's
[Garmin watch](https://fabolus.org/build/garmin-build/) page.

## Prerequisites

- Connect IQ SDK (currently 9.2.0). `MONKEYC` below points at its `bin/monkeyc`.
- A Garmin developer key (`.der`). Keep it: a private beta must be uploaded with the same key every time.

```sh
MONKEYC="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/monkeyc"
KEY="$HOME/garmin_dev_key.der"
```

Stamp the build commit first. It is what the watch's Details `App:` row shows, so it is how you identify
a build later from a device report, and the app does not compile without it (the stamp is generated and
git-ignored; see [`scripts/stamp-revision.sh`](../scripts/stamp-revision.sh)). A trailing `+` in its
output means the tree was dirty, so the hash alone does not describe what you built. Then check that the
version matches the phone app the contract is pinned to (`contract/PIN`):

```sh
./scripts/stamp-revision.sh
./scripts/check-version-sync.sh
```

## Sideload over USB

```sh
"$MONKEYC" -f monkey.jungle -o bin/faBolus.prg -y "$KEY" -d venu3s
```

Copy `bin/faBolus.prg` into `GARMIN/APPS` on the watch (OpenMTP on a Mac). The phone app talks to it with
no change, because its default `GARMIN_BETA_APP_ID` is this app's id.

## Your own private beta

The Connect IQ store lets you upload an app as a beta that only your own Garmin account sees, and it
installs and updates over the air. Every beta needs its own app id, even a private one, so a script makes
one for you:

```sh
./scripts/beta-build.sh
```

The script:

1. Generates your personal app id the **first** time (saved in `.beta-app-id`, gitignored) and reuses
   it on every later build. Regenerating it would orphan your beta and unpair your phone.
2. Builds **`bin/faBolus-beta-personal.iq`** from `monkey.jungle` with that id, signed with your key,
   and reveals it in Finder.
3. Points the iPhone app at your id: writes `GARMIN_BETA_APP_ID` into `../faBolus/LocalConfig.xcconfig`
   and regenerates its Xcode project.

It checks the SDK and your key at `~/garmin_dev_key.der` first, with setup guidance if either is missing.
Override paths with `MONKEYC=… KEY=… FABOLUS_DIR=… ./scripts/beta-build.sh`. The faBolus build guide
passes the key it makes, `KEY=../developer_key.der`.

Two manual steps remain (Garmin and Apple don't allow automating them):

- In Xcode, open `faBolus.xcodeproj` and Run to put the updated app on your iPhone.
- Upload the revealed `.iq` as a beta app in the Connect IQ developer dashboard, then install it on
  your watch from the Connect IQ Store app, signed in with the same Garmin account.

## The release binary

Each faBolus release records one watch build: the export of `monkey.jungle` at the release's
`contract/PIN`, for every device in the manifest:

```sh
"$MONKEYC" -f monkey.jungle -o bin/faBolus.iq -y "$KEY" -e -r
```
