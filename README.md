> [!CAUTION]
> faBolusGarmin is experimental, in-development software — not a medical device and not FDA-cleared. It is
> for experimental and demonstration use. Not medical advice — check every value against your pump and
> your clinician. If you build or use it, you assume all responsibility.

# faBolusGarmin

The Garmin Connect IQ watch app for [faBolus](https://github.com/faBolus-app/faBolus). It shows the glucose
and pump status the faBolus iPhone app sends it, and asks the phone to bolus, cancel or clear a pump alert.
It never talks to the pump: the phone checks every request and is the only thing connected to it.

**Supported device:** the Garmin **Venu 3S**, the one build target and the one device tested on
hardware. The app adapts to touch or buttons at runtime, so another device is mostly a manifest entry;
see [CONTRIBUTING.md](CONTRIBUTING.md#add-support-for-another-garmin-device).

> [!NOTE]
> faBolusGarmin is an independent, open-source project. It is not affiliated with Tandem Diabetes Care,
> Dexcom or Garmin.

## How it fits together

The watch and the phone speak protocol version 2, defined in faBolus's
`Packages/RemoteProtocol/contract/` and vendored here in [`contract/`](contract/README.md) at the faBolus
commit in `contract/PIN`. The phone sends status, the watch's settings (config) and history; the watch
sends polls, bolus requests, cancels and alert clears.

A bolus needs a deliberate gesture on the watch: tap **1 → 2 → 3** in order on a touch device, or hold
UP then START on a button device. The phone then checks the request: it must be recent and is acted on at
most once, and for carbs the phone works the dose out again from the pump's latest values and refuses it
if it differs from the watch's estimate. The pump's own limits govern. The watch's calculator is only a
preview, tested against the same calculator rows as the phone's.

- `source/app/` holds the app: one module per concern, each the only writer of its stored keys (`Link`,
  `Wire`, `Inbound`, `Status`, `Prefs`, `History`, `Alerts`, `BolusFlow`, `Calculator`, `Display`), the
  views and delegates, the background service and complication (`BgService`, `BgComplication`) and the
  glance (`FaBolusGlanceView`). Entry: `FaBolusApp`.
- The screens, ordered from the phone: glance (glucose and bolus), glucose only, clock and glucose,
  bolus button only, alerts, history and details, plus the bolus and confirm flow.
- `Link.mc` is the phone link: every message goes out through it, polls back off while the phone is
  silent, and a bolus request is resent until the phone answers.

## Build and test

`./scripts/check.sh` runs every gate. Its `build` gate is `./scripts/build-and-test.sh`, which compiles
every jungle, fails on any compiler warning and runs the unit suite in the simulator. Run
`./scripts/setup.sh` once per clone so the pre-push hook runs the gates.

By hand, for a sideload build, with the SDK's `bin/` on your PATH (or `$SDK/bin/monkeyc`, as the build
guide does) and your signing key in the repository as `developer_key.der`, where `build-and-test.sh`
looks for it (`CIQ_KEY=<path>` points it elsewhere):

```sh
./scripts/stamp-revision.sh   # the commit the watch's Details screen shows; the build fails without it
monkeyc -f monkey.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s
```

Unit tests, with the simulator running (`connectiq`):

```sh
monkeyc -f test.jungle -o bin/faBolusGarmin-test.prg -y developer_key.der -d venu3s --unit-test
monkeydo bin/faBolusGarmin-test.prg venu3s -t
```

Copy `bin/faBolus.prg` to `GARMIN/APPS` on the watch, or publish a private beta with
`./scripts/beta-build.sh` ([`docs/STORE-BUILDS.md`](docs/STORE-BUILDS.md)). The step-by-step guide is
faBolus's [Garmin watch](https://fabolus.org/build/garmin-build/) page.

## Related

- [faBolus](https://github.com/faBolus-app/faBolus): the iPhone app and the contract this watch app
  speaks. Its [ARCHITECTURE.md](https://github.com/faBolus-app/faBolus/blob/main/ARCHITECTURE.md)
  explains how the phone and its remotes fit together.
- [TandemKit](https://github.com/faBolus-app/TandemKit): the pump protocol library the phone uses.

## License and trademark

The code is MIT-licensed (see [LICENSE](LICENSE)). **faBolus™** is a trademark of Zev Granowitz; the
license covers the source code, not the name or branding. See [NOTICE.md](NOTICE.md).
