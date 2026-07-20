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

## Add support for another Garmin watch
The app currently ships for the **Garmin Venu 3S** only (`manifest.xml` lists one product,
`venu3s`). Supporting another device is a welcome contribution — the layout code is already
device-relative, so it's mostly manifest + input + assets, not a rewrite:

1. **Declare the product.** Add `<iq:product id="<deviceId>"/>` to `manifest.xml` (device ids come
   from the Connect IQ SDK's device manager). Build for it with `-d <deviceId>`.
2. **Launcher icon size.** Each device family expects a specific launcher-icon size (the venu3s
   wants 70×70). Add a correctly-sized `launcher_icon` via a device/size **resource qualifier**
   folder (e.g. `resources-<device>/drawables/…`) so each device gets a crisp icon instead of an
   upscaled one.
3. **Input model — the main work.** The screens target the venu3s's **touch** model: tap targets
   (bolus −/+, Deliver, the 1-2-3 confirm circles, alert rows) and swipe up/down between screens,
   using coordinate hit-testing in the `*Delegate.mc` / `HoldDelegate.mc` files. A **button-only**
   device (many Forerunner/fenix) has no taps — you'll need button/behavior-based equivalents for
   those delegates. Verify and adapt input per device.
4. **Screen shape & fonts.** Views lay out with fractions of `dc.getWidth()/getHeight()`, so they
   scale, but check the device's shape (round / semi-round / rectangular) for clipping, and confirm
   the number fonts render (`TrendArrow` already draws its own arrow because some fonts can't render
   Unicode arrows).
5. **Test.** Run in the CIQ simulator for that device, then on hardware; keep the schema drift check
   green. Note what was simulator-only vs. hardware-tested.
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
