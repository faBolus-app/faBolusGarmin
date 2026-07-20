# faBolusGarmin

A **Garmin (Connect IQ / Monkey C) remote** for bolusing and status viewing. It speaks a small,
**pump- and host-agnostic** JSON contract, so it isn't tied to any one pump or companion app.

- **Today** it runs as a **phone-relay remote for [faBolus](https://github.com/faBolus-app/faBolus)**,
  whose iPhone host owns the pump connection (currently a Tandem t:slim X2 / Mobi via PumpX2Kit).
- Because the wire format is a generic contract (`faBolus/schema/command.schema.json`), **any host
  that implements it can drive this same watch app** — a different pump backend, or a different
  companion app (e.g. a future Loop integration). Nothing in the default phone-relay path is
  Tandem-specific.

**Supported devices:** the **Garmin Venu 3S** is hardware-validated. The app also builds and runs on
button-only watches (e.g. fenix 7) and **Edge cycling computers** (e.g. edge 540 / 1040) — it
adapts to touch vs. buttons and watch vs. no-watch-face **at runtime** (`DeviceProfile`), so adding a
device is usually just a manifest entry. Those non-Venu-3S targets are build-verified and sit behind
the phone's safety interlock, but aren't hardware-validated yet. See
[CONTRIBUTING.md](CONTRIBUTING.md#add-support-for-another-garmin-device).

> **Experimental — in development.** Not FDA-cleared; if you build or use it you assume all
> responsibility. Not affiliated with, endorsed by, or a product of Tandem Diabetes Care, Dexcom,
> or Garmin.

## How it fits together
The watch is a **thin remote**: it renders status and sends confirmed commands
(`statusRead` / `bolusRequest` / `cancelBolus` / `dismissAlert`) as the JSON contract; a **host**
answers them. Safety interlocks are enforced on both sides — an explicit confirm on the watch
(1-2-3 / hold) *and* the host's own confirmation + max-bolus clamp. The watch confirm is a second
factor, never the only one.

- `source/app/` — the UI (glance / bolus / confirm / history / alerts, complication, `TrendArrow`,
  `AppState`, `Nav`). Entry: `FaBolusApp`.
- `source/app/DeviceProfile.mc` — the device seam. Screens read it (`isTouch()`, `isButtons()`,
  `hasComplications()`) and adapt at runtime:
  - **Touch** devices: tap the controls; confirm by tapping **1 → 2 → 3**.
  - **Button** devices: **UP/DOWN** adjust the dose, **MENU** switches Units/Carbs, **START**
    delivers; confirm is a deliberate **two-button hold** (hold UP to arm, then hold START to
    deliver). No on-screen cursor.
- `source/app/RemoteComm` — a transport **router** behind one `send(cmd)` seam: **phone-relay**
  (default) or **direct-to-pump**. The same command dicts flow either way, so the UI is
  transport-agnostic.

Beyond the remote, the repo also builds three more Connect IQ surfaces from the same BG feed:
- a **glance** (compact BG in the glance carousel) — built into the app (`FaBolusGlanceView`, reads
  the persisted reading directly).
- a **BG data field** for activity screens on watches and Edge — `datafield/` + `datafield.jungle`.
- a **watch face** scaffold — `watchface/` + `watchface.jungle`.

See [CONTRIBUTING.md](CONTRIBUTING.md#add-a-watch-face-or-another-connect-iq-app-type) for building
and extending these.

### Experimental: direct-to-pump (Tandem)
An optional engine lets the watch talk **directly** to a Tandem pump over BLE with no phone — a full
Monkey C reimplementation of the pump protocol / auth / BLE, **byte-exact vs the pumpX2 `cliparser`
oracle** (31/31 unit tests). This path **is** Tandem-specific and is **paused / compile-verified
only**, pending on-hardware validation. It lives under `direct-pump/`, wired but dormant behind the
same `RemoteComm` seam; the default host-agnostic phone-relay path does not use it.

### Experimental: direct-to-watch CGM (Dexcom G7)
An optional engine lets the watch read a **Dexcom G7 / ONE+** glucose value **directly over BLE** as
a failover when the phone is out of range — a passive listener (it never authenticates, so it can't
disconnect the official app), with the G7 message decoder ported from the vendored Swift
`G7SensorKit`. It lives under `direct-cgm/` and is **paused / compile-verified only**
(`monkeyc -f direct-cgm.jungle …`), pending on-hardware validation; it is **not** in the shipping
build and not yet wired into `AppState.glucose`. See `direct-cgm/DIRECT_CGM_STATUS.md`. (The
shipping remote already shows failover glucose whenever the phone relays it.) The Apple Watch
equivalent — direct G7 BLE when the iPhone is unreachable — is live in the `faBolus` repo.

## Known limitations (being worked on)
- **BG complication reads 0.** The published BG complication does not yet update with the live CGM
  value — it currently shows `0` instead of the reading. Fix in progress.
- **Alert clear doesn't reach the pump.** Clearing an alert currently removes it from the phone and
  watch UI **but does not clear it on the pump itself**. Fix in progress.

## Build & test
```
# release build (entry FaBolusApp); provide your own signing key as developer_key.der
monkeyc -f monkey.jungle -o bin/faBolusGarmin.prg -y developer_key.der -d venu3s -w
# unit tests (simulator must be running: `connectiq`)
monkeyc -f test.jungle -o bin/faBolusGarmin-test.prg -y developer_key.der -d venu3s --unit-test -w
monkeydo bin/faBolusGarmin-test.prg venu3s -t
```
Golden oracle vectors live in `tests/golden_vectors.txt`; regenerate with `tools/gen_golden.sh`
(needs JDK 14+ and the prebuilt `cliparser.jar`). Keep the Monkey C `RemoteCommand` mirror in sync
with `faBolus/schema/command.schema.json` — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Related
- [`faBolus`](https://github.com/faBolus-app/faBolus) — the iPhone / Apple Watch host and the
  contract (`schema/`) this remote speaks; its
  [ARCHITECTURE.md](https://github.com/faBolus-app/faBolus/blob/master/ARCHITECTURE.md) explains how
  remotes and hosts fit together and how to host the remotes from another app.
- [`PumpX2Kit`](https://github.com/faBolus-app/PumpX2Kit) — the Swift Tandem protocol / auth / BLE
  core; the reference the direct-pump engine ports from.
