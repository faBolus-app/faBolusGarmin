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
`System.getDeviceSettings()` and every screen chooses touch vs. button input and complication vs.
none from it. Layout is already resolution-relative. So adding a device is mostly a manifest entry,
not a rewrite:

1. **Declare the product (usually all you need).** Add `<iq:product id="<deviceId>"/>` to
   `manifest.xml` (ids come from the Connect IQ SDK device manager). Build with `-d <deviceId>`.
   Touch devices get the tap UI; button-only devices get the focus-cursor UI (up/down move a
   highlight, **START** activates; the 1-2-3 confirm becomes three START presses) — both are already
   implemented, nothing per-device to write.
2. **Cycling computers / devices with no watch face** (Edge, etc.) have no complication surface, so
   the complication *resource* must be dropped or the build fails. Add one line to `monkey.jungle`:
   `<deviceId>.resourcePath = resources` (see `edge540`/`edge1040`). The complication code itself is
   already runtime-guarded, and these devices run the same `watchApp` type.
3. **Launcher icon (optional polish).** If the default icon is upscaled for the device, add a
   correctly-sized `launcher_icon` via a resource-qualifier folder (`resources-<device>/drawables/…`).
4. **Verify.** Run the device in the CIQ simulator (exercise bolus entry, the 1-2-3 confirm, and
   alerts with *buttons* if it's a button device), then on hardware; keep the schema drift check
   green. Add the device to the README's "Supported watches / devices" list and note simulator-only
   vs. hardware-tested — the button/Edge input paths are not yet hardware-validated.

Only the Venu 3S is hardware-validated today; the button-device and Edge paths are build-verified and
behind the phone's confirm + max-bolus interlock (the remote never delivers on its own), but they
need on-device shakeout before a device is called "supported."
6. **Document it.** Add the device to the README's "Supported watches" list and the faBolus docs.

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
