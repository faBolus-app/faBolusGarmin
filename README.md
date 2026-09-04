> [!CAUTION]
> **Not a medical device — do not use it for treatment decisions.** faBolusGarmin is experimental
> software under active development. It is **not FDA-cleared or approved** and has **not** been
> clinically validated. **Do not rely on it to make or carry out any insulin-dosing, treatment, or other
> clinical decision.** It is for software development and evaluation only — always confirm every reading
> and dose directly on your pump and CGM, and talk to your healthcare provider about your therapy.

# faBolusGarmin

A **Garmin (Connect IQ / Monkey C) remote** for bolusing and status viewing. It speaks a small,
**pump- and host-agnostic** JSON contract, so it isn't tied to any one pump or companion app.

- **Today** it runs as a **phone-relay remote for [faBolus](https://github.com/faBolus-app/faBolus)**,
  whose iPhone host owns the pump connection (currently a Tandem t:slim X2 / Mobi via TandemKit).
- Because the wire format is a generic contract (`faBolus/schema/command.schema.json`), **any host
  that implements it can drive this same watch app** — a different pump backend, or a different
  companion app (e.g. a future Loop integration). Nothing in the default phone-relay path is
  Tandem-specific.

**Supported devices:** the **Garmin Venu 3S** is the sole build target on `main`, and the sole
hardware-validated device. It adapts to touch vs. buttons **at runtime** (`DeviceProfile`), so a
future device is usually just a manifest entry — additional touch/button watches and Edge cycling
computers are build-verified on the `dev/garmin-devices` branch, not on `main`. See
[CONTRIBUTING.md](CONTRIBUTING.md#add-support-for-another-garmin-device).

> **Experimental — in development.** Not FDA-cleared; if you build or use it you assume all
> responsibility. Not affiliated with, endorsed by, or a product of Tandem Diabetes Care, Dexcom,
> or Garmin.

## How it fits together
The watch is a **thin remote**: it renders status and sends confirmed commands
(`statusRead` / `bolusRequest` / `cancelBolus` / `dismissAlert`) as the JSON contract; a **host**
answers them. The bolus is confirmed by **one explicit gesture on the watch** (1-2-3 / hold). The host
does not add a separate confirmation gesture today; instead it independently **recomputes the dose from
the carbs, rejects it if it diverges from the estimate the watch showed, and clamps to the max-bolus
limit** (defense in depth, not a second human confirmation). A bound two-phase host-nonce confirmation
is planned (see `reaudit-remediation-plan` GA-01); until it lands, do not describe the watch gesture as
one of *two* confirmations.

- `source/app/` — the UI. The swipeable screens are user-orderable from the phone: **glance** (glucose +
  bolus), **glucose-only** (no button), **clock** (analog/digital + glucose, tap to switch, no button),
  **bolus-only** (just the button), **history**, **alerts** — plus the bolus/confirm modal flow, the
  complication, `TrendArrow`, `AppState`, and the `Nav` carousel. Entry: `FaBolusApp`.
- `source/app/DeviceProfile.mc` — the device seam. Screens read it (`isTouch()`, `isButtons()`)
  and adapt at runtime:
  - **Touch** devices: tap the controls; confirm by tapping **1 → 2 → 3**.
  - **Button** devices: **UP/DOWN** adjust the dose, **MENU** switches Units/Carbs, **START**
    delivers; confirm is a deliberate **two-button hold** (hold UP to arm, then hold START to
    deliver). No on-screen cursor.
- `source/app/RemoteComm` — phone-relay send behind one `send(cmd)` seam. Direct-to-pump is **not**
  in this tree (preservation branches only).

Beyond the remote, the repo also builds one more Connect IQ surface from the same BG feed:
- a **glance** (compact BG in the glance carousel) — built into the app (`FaBolusGlanceView`, reads
  the persisted reading directly).

See [CONTRIBUTING.md](CONTRIBUTING.md#add-a-watch-face-or-another-connect-iq-app-type) for building
and extending these. (A standalone watch-face app that consumed the complication previously lived on
`main`; it has been removed and now lives only on the `experimental` branch.)

Direct-to-pump BLE and direct-to-watch CGM engines are **not** on `main`. They live only on the
`dev/direct-ble` / `experimental` preservation branches.

## Build & test
`./scripts/build-and-test.sh` is the gate and does all of the below for you. By hand:
```
# stamp the build commit for the Details "App:" row — the app does not compile without it
./scripts/stamp-revision.sh
# release build (entry FaBolusApp); provide your own signing key as developer_key.der
monkeyc -f monkey.jungle -o bin/faBolusGarmin.prg -y developer_key.der -d venu3s -w
# unit tests (simulator must be running: `connectiq`)
monkeyc -f test.jungle -o bin/faBolusGarmin-test.prg -y developer_key.der -d venu3s --unit-test -w
monkeydo bin/faBolusGarmin-test.prg venu3s -t
```
The stamp is generated and git-ignored, so a bare `monkeyc` on a fresh clone fails with
`Undefined symbol ':AppRevision'` until you run the script. That is deliberate: a binary with **no**
version is fine, a binary stamped with the **wrong** tree is not.
Keep the Monkey C contract mirror in sync with `faBolus/schema/command.schema.json` — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Related
- [`faBolus`](https://github.com/faBolus-app/faBolus) — the iPhone host and the
  contract (`schema/`) this remote speaks; its
  [ARCHITECTURE.md](https://github.com/faBolus-app/faBolus/blob/master/ARCHITECTURE.md) explains how
  remotes and hosts fit together and how to host the remotes from another app.
- [`TandemKit`](https://github.com/faBolus-app/TandemKit) — the Swift Tandem protocol / auth / BLE
  core used by the iPhone host.

## License & trademark

Code is MIT-licensed (see [LICENSE](LICENSE)). **faBolus™** is a trademark of Zev Granowitz — the license
covers the source code, not the name or branding. See [NOTICE.md](NOTICE.md) for details.
