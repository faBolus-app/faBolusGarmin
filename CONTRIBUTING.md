# Contributing to faBolusGarmin

faBolusGarmin is the Garmin watch app for faBolus, a remote that speaks the phone↔remote contract in
`contract/`. Contributions are welcome by pull request. Until the rebuild merges, target `rebuild`;
after that, `main` (see [BRANCHES.md](BRANCHES.md)).

faBolusGarmin is experimental, in-development software — not a medical device and not FDA-cleared, for
experimental and demonstration use.

## Device floor

- **The Garmin Venu 3S is the one build target and the one device tested on hardware.** The
  `<iq:products>` list in the manifests contains only `venu3s`. The store listing
  ([`store/connectiq-listing.md`](store/connectiq-listing.md)) states the same; keep the two in sync.
- **Fail gracefully on unsupported hardware.** Where a device can't provide a capability, show an
  explicit, honest state, never a made-up value. This is separate from the `--` shown for a stale or
  missing reading, which is a safety signal and stays. The complications are the standing example: a
  face can't show a value's age, so a stale value is published as no number and the label `--`
  (`source/app/BgComplication.mc`).

## Keep it host-agnostic

- The watch is a thin remote. Everything it sends and receives is the shared contract in `contract/`
  (protocol version 2). Don't bake assumptions about a specific pump or host into the phone link.
- `Link` is the one seam for transports — add transports there and leave the UI and the state modules
  untouched.

## Add support for another Garmin device

The app adapts to the device **at runtime** — `Nav.isTouch()` (`source/app/Nav.mc`) reads
`System.getDeviceSettings()` and every screen chooses its input model from it. Layout is already resolution-relative. So adding a device is mostly a manifest entry, not a
rewrite:

1. **Declare the product (usually all you need).** Add `<iq:product id="<deviceId>"/>` to
   `manifest.xml` (ids come from the Connect IQ SDK device manager). Build with `-d <deviceId>`.
   Both input models are already implemented — nothing per-device to write.
2. **Cycling computers / devices with no watch face** (Edge, etc.) have no complication surface, so
   the complication *resource* must be dropped or the build fails. Add one line to `monkey.jungle`:
   `<deviceId>.resourcePath = resources`. The complication code is already runtime-guarded, and these
   devices run the same `watchApp` type.
3. **Launcher icon (optional polish).** If the default icon is upscaled for the device, add a
   correctly-sized `launcher_icon` via a resource-qualifier folder (`resources-<device>/drawables/…`).
4. **Verify.** Run the device in the CIQ simulator, exercising bolus entry and the confirm with the
   device's actual input (buttons if it's button-only), then on hardware; keep the unit suite green. Add the device to the README's "Supported devices" list and note simulator-only vs.
   hardware-tested.

Only the Venu 3S is tested on hardware. Builds for other watches and Edge computers are kept on the
`archive/dev/garmin-devices` tag; each needs testing on the device before it's called supported.

### The two input models

`Nav.isTouch()` picks between them; the views/delegates branch on it, so both live in the same files:

- **Touch** (e.g. Venu 3S, edge 1040): tap the drawn controls; confirm by tapping **1 → 2 → 3** in
  order.
- **Buttons** (e.g. fenix, Forerunner, edge 540): button-native, no on-screen cursor —
  **UP/DOWN** adjust the bolus amount, **MENU** switches Units/Carbs, **START** delivers. The
  confirm is a deliberate **two-different-button hold**: hold **UP** ~1.5 s to arm, then hold
  **START** ~1.5 s to deliver (releasing early cancels). Never make the confirm a single repeatable
  press.

When adapting to a new input layout, keep the confirm at least this deliberate (two distinct,
sustained actions), and keep the touch and button flows in sync in `source/app/BolusViews.mc`.

## Add a watch face or another Connect IQ app type

Each Connect IQ app type is a separate app (its own manifest + jungle), so the repo keeps them side
by side (like `monkey.jungle` / `test.jungle`):

- **Watch face** — not in this app. An earlier one, its own Connect IQ app (`watchface/` plus a
  manifest and jungle pair), is on the `archive/experimental/2026-08-27` tag. Watches only — Edge has
  no watch face.
- **Glance** — built into the remote app itself: `FaBolusApp.getGlanceView()` +
  `source/app/FaBolusGlanceView.mc`, both annotated `(:glance)`. Because it's the same app it reads
  the stored status directly, so it shows a real reading with no extra wiring.
- **Widget** — not built; add it the same way (its own `manifest-*.xml` + `*.jungle` + source dir).

## The contract (don't let it drift)

The source of truth is faBolus's `Packages/RemoteProtocol`: its Swift types write the golden fixtures in
`contract/`, which this repo vendors at the faBolus commit in `contract/PIN`. To change the contract:

1. Change it in faBolus, rewrite the fixtures there
   (`UPDATE_CONTRACT=1 swift test --package-path Packages/RemoteProtocol`), commit and push.
2. Run `./scripts/sync-contract.sh <that faBolus commit>` here, update the Monkey C to match, and run
   the gates; the unit suite reads every fixture and runs the calculator on every oracle row.
3. A change older watches can't read is a new protocol version: each side shows a message of another
   version as "update", never reads it.

CI's contract gate checks `contract/` against faBolus at `contract/PIN`, and that
`AppVersion.NAME` (`source/app/AppVersion.mc`) equals faBolus's `MARKETING_VERSION` there, so the pinned
commit must be pushed. A release bumps both and syncs the pin to the faBolus release commit.

## Before a pull request

- Run `./scripts/check.sh`. Its `build` gate (`./scripts/build-and-test.sh`) needs the Connect IQ SDK
  and the simulator, so it runs locally, not in CI; `./scripts/setup.sh` makes the pre-push hook run it.
- Keep the confirm deliberate: at least two distinct, sustained actions, in sync between the touch and
  button flows in `source/app/BolusViews.mc`.
- A dosing change (the calculator, the bolus request, its fields) gets extra review. The phone
  recomputes the dose and refuses one that differs from the watch's estimate; keep the watch's preview
  and request in step with that.
- Say what was tested on a watch and what only in the simulator.
