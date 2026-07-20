# Contributing to faBolusGarmin

faBolusGarmin is a **host- and pump-agnostic Garmin remote**. It speaks the JSON contract in
[`faBolus`](https://github.com/faBolus-app/faBolus)'s `schema/command.schema.json`; any host that
implements that contract can drive it. Contributions are welcome by **PR, not fork**. All work is
for **experimental use only** (in development, not FDA-cleared).

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
   `<deviceId>.resourcePath = resources` (see `edge540`/`edge1040`). The complication code is already
   runtime-guarded, and these devices run the same `watchApp` type.
3. **Launcher icon (optional polish).** If the default icon is upscaled for the device, add a
   correctly-sized `launcher_icon` via a resource-qualifier folder (`resources-<device>/drawables/…`).
4. **Verify.** Run the device in the CIQ simulator, exercising bolus entry and the confirm with the
   device's actual input (buttons if it's button-only), then on hardware; keep the schema drift check
   green. Add the device to the README's "Supported devices" list and note simulator-only vs.
   hardware-tested.

Only the Venu 3S is hardware-validated today; the button-device and Edge paths are build-verified and
sit behind the phone's confirm + max-bolus interlock (the remote never delivers on its own), but they
need on-device shakeout before a device is called "supported."

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
by side (like `probe.jungle` / `test.jungle`):
- **Watch face** — a scaffold exists: `watchface/` + `manifest-watchface.xml` + `watchface.jungle`
  (`monkeyc -f watchface.jungle -o bin/faBolusFace.iq -y <dev_key.der> -e -r -w`). It draws the time
  and a BG slot; wire live glucose by subscribing to the faBolus **public BG complication** (see the
  TODO in `watchface/FaBolusFaceView.mc`). Watches only — Edge has no watch face.
- **Data field / glance / widget** — not built yet, and good next targets. A BG **data field**
  (`type="datafield"`) would show glucose on any run/ride activity screen (Edge included). Add one
  the same way: a `<type>/` source dir + `manifest-<type>.xml` + `<type>.jungle`, reusing
  `RemoteComm`/`AppState` for the phone feed and the shared `resources`.

## The contract mirror (don't let it drift)
The source of truth is `faBolus/schema/command.schema.json`, mirrored in Swift (`RemoteCommand`) and
here in Monkey C (`RemoteCommand.mc`). If you change the contract:
1. Update the schema and bump its `version`, plus the Swift mirror (in faBolus).
2. Update the Monkey C mirror to match.
3. Prefer additive, optional fields so older remotes keep working.

## Safety
- Never weaken the interlocks: the 1-2-3 / hold confirmation on the watch is a **second** factor; the
  host still enforces its own confirmation + max-bolus clamp. Dosing changes get extra review.
- The direct-to-pump engine (`direct-pump/`) is the most safety-critical code — it signs and sends
  real pump commands — and must stay **byte-exact vs the pumpX2 `cliparser` oracle**.

## Before a PR
- Build the app:
  `monkeyc -f monkey.jungle -o bin/faBolusGarmin.prg -y developer_key.der -d venu3s -w`.
- Run the unit tests in the CIQ simulator (README → "Build & test"); the oracle golden vectors must
  pass.
- Note anything only compiled vs. tested on hardware.
