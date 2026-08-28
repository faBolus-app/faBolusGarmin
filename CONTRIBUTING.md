# Contributing to faBolusGarmin

faBolusGarmin is a **host- and pump-agnostic Garmin remote**. It speaks the JSON contract in
[`faBolus`](https://github.com/faBolus-app/faBolus)'s `schema/command.schema.json`; any host that
implements that contract can drive it. Contributions are welcome by **PR, not fork**. All work is
for **experimental use only** (in development, not FDA-cleared).

## Branch model, versioning & lockstep (§1.3 / §1.4)
Branch governance is centralized in [`BRANCHES.md`](BRANCHES.md) (a stub) →
[`faBolus/BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md): the three-branch
model, the §1.2 experimental gate, and the §1.4 promotion criteria. Read it before opening a PR. The
per-release history is in [`CHANGELOG.md`](CHANGELOG.md).

- **Lockstep (§1.3).** faBolusGarmin is a **base feature** of faBolus, not a separate product. A Garmin
  `main` release accompanies every app `main` release and holds the **same quality bar**; Garmin work
  does not lag behind and does **not ship separately**.
- **Published device floor.** The **Garmin Venu 3S is the sole hardware-validated device, and the
  sole build target on `main`.** The `manifest.xml` `<iq:products>` list on `main` contains only
  `venu3s`; additional touch/button watches and Edge cycling computers are build-verified on the
  `dev/garmin-devices` branch, not on `main`. This floor is also stated store-facing in
  [`store/connectiq-listing.md`](store/connectiq-listing.md) — keep the two in sync (see "Add support
  for another Garmin device" below for how a device graduates).
- **Fail gracefully on unsupported hardware.** Where a device genuinely cannot provide a capability, the
  app must degrade to an explicit, honest state — never a fabricated value or silent misbehavior. This
  is separate from the deliberate honest-staleness `--` shown for a stale/absent reading (a safety
  signal, which must be preserved). The data field is the standing example: Connect IQ forbids a
  `datafield` app from subscribing to the BG complication, so it ships as a labelled placeholder rather
  than pretending to have a reading (`datafield/FaBolusDataField.mc`).

## Keep it host-agnostic
- The watch is a thin remote. Everything it sends/receives is the shared contract
  (`statusRead` / `bolusRequest` / `cancelBolus` / `dismissAlert` + the status payload). Don't bake
  assumptions about a specific pump or host into the phone-relay path.
- `RemoteComm` is the one seam for transports — add transports there and leave the UI / `AppState`
  untouched.

## Add support for another Garmin device
The app adapts to the device **at runtime** — `DeviceProfile` (`source/app/DeviceProfile.mc`) reads
`System.getDeviceSettings()` and every screen chooses its input model and complication vs. none from
it. Layout is already resolution-relative. So adding a device is mostly a manifest entry, not a
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
   device's actual input (buttons if it's button-only), then on hardware; keep the schema drift check
   green. Add the device to the README's "Supported devices" list and note simulator-only vs.
   hardware-tested.

Only the Venu 3S is hardware-validated today; the button-device and Edge paths are build-verified and
sit behind the watch confirm gesture plus the phone's recompute + max-bolus clamp (the remote never
delivers on its own), but they need on-device shakeout before a device is called "supported."

### The two input models
`DeviceProfile.isTouch()` picks between them; the views/delegates branch on it, so both live in the
same files:
- **Touch** (e.g. Venu 3S, edge 1040): tap the drawn controls; confirm by tapping **1 → 2 → 3** in
  order.
- **Buttons** (e.g. fenix, Forerunner, edge 540): button-native, no on-screen cursor —
  **UP/DOWN** adjust the bolus amount, **MENU** switches Units/Carbs, **START** delivers. The
  confirm is a deliberate **two-different-button hold**: hold **UP** ~1.5 s to arm, then hold
  **START** ~1.5 s to deliver (releasing early cancels). Never make the confirm a single repeatable
  press.

When adapting to a new input layout, keep the confirm at least this deliberate (two distinct,
sustained actions), and keep the touch and button flows in sync in `HoldView`/`HoldDelegate` and
`BolusView`/`BolusDelegate`.

## Add a watch face or another Connect IQ app type
Each Connect IQ app type is a separate app (its own manifest + jungle), so the repo keeps them side
by side (like `datafield.jungle` / `test.jungle`):
- **Watch face** — removed from `main`; it lives only on the `experimental` branch as its own
  Connect IQ app (`watchface/` plus a dedicated manifest/jungle pair). Watches only — Edge has no
  watch face.
- **Data field** — `datafield/` + `manifest-datafield.xml` + `datafield.jungle`
  (`monkeyc -f datafield.jungle -o bin/faBolusField.iq -y <dev_key.der> -e -r -w`). A `SimpleDataField`
  that shows BG on any run/ride activity screen — watches **and** Edge. Same public-complication feed
  as the watch face (stubbed TODO in `datafield/FaBolusDataField.mc`), so it shows "--" until wired.
- **Glance** — built into the remote app itself: `FaBolusApp.getGlanceView()` +
  `source/app/FaBolusGlanceView.mc`, both annotated `(:glance)`. Because it's the same app it reads
  the persisted BG (`bg`/`bgEpoch`) directly, so it shows a real reading with no extra wiring.
- **Widget** — not built; add it the same way (its own `manifest-*.xml` + `*.jungle` + source dir).

## The contract mirror (don't let it drift)
The source of truth is `faBolus/schema/command.schema.json`, mirrored in Swift (`RemoteCommand`) and
here in Monkey C (`RemoteComm.mc` / `AppState.mc`). If you change the contract:
1. Update the schema and bump its `version`, plus the Swift mirror (in faBolus).
2. Update the Monkey C mirror to match.
3. Prefer additive, optional fields so older remotes keep working.

## Safety
- Never weaken the interlocks: the bolus is confirmed by **one explicit gesture on the watch**
  (1-2-3 / hold). The host independently **recomputes the dose from the carbs, rejects it if it
  diverges from the estimate the watch showed, and clamps to the max-bolus limit** (defense in
  depth, not a second human confirmation). Dosing changes get extra review.

## Before a PR
- Build the app:
  `monkeyc -f monkey.jungle -o bin/faBolusGarmin.prg -y developer_key.der -d venu3s -w`.
- Run the unit tests in the CIQ simulator (README → "Build & test").
- Note anything only compiled vs. tested on hardware.
