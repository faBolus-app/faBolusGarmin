# AGENTS.md — faBolusGarmin

Working notes for AI coding agents (and humans). Companion to [`llms.txt`](llms.txt) (the map). This is
the Garmin (Connect IQ / Monkey C) remote for faBolus — a thin remote that relays confirmed commands to
the iPhone host (which owns the pump), plus an experimental `direct-pump/` engine. Experimental, not
FDA-cleared.

## Safety
- The phone is the authority; this app **requests**, it doesn't dose on its own — except `direct-pump/`,
  the **most safety-critical** code (it signs + sends pump commands directly). Treat `direct-pump/` like
  insulin-delivery code and keep byte parity with the reference; don't guess protocol bytes.
- Bolus confirm is a deliberate gesture per device (touch 1-2-3 / button hold). Don't weaken it.

## Command contract (keep in sync with the phone)
`RemoteCommand` is mirrored here in Monkey C from faBolus's `schema/command.schema.json` (the source of
truth). Change fields → update the mirror → run `scripts/check-schema-drift.sh`. Phone-only kinds
(auth/sealed/approval) are intentionally NOT in this shared schema.

## Layout
- `source/` — app: nav/carousel + screens (glance/alerts/history/details), bolus confirm, plus
  `direct-cgm/` and `direct-pump/` engines.
- Jungles + manifests select builds: `monkey.jungle`+`manifest.xml` (Beta listing),
  `official.jungle`+`manifest-official.xml` (Official listing), `test.jungle`, `probe.jungle`,
  `datafield.jungle`, `direct-cgm.jungle`.
- Devices: `venu3s` (touch: onTap) is the sole build target on `main`. Additional button-only and Edge
  devices are build-verified on the `dev/garmin-devices` branch, not on `main`.
- `tests/`, `tools/gen_golden.sh` — parity/golden tests.

## Build + test before a PR
- **`./scripts/build-and-test.sh`** compiles every jungle and runs the 29-case Monkey C unit suite in
  the simulator. Run it before any PR touching Garmin code. It is a **local** gate: CI has no SDK and
  no display, so CI's Garmin coverage is only the schema-drift contract check (see
  `.github/workflows/ci.yml`). The script parses the simulator's `PASSED (…failed=0, errors=0)` line —
  `monkeydo`'s exit code lies (nonzero even when all tests pass).

## Build (authoritative: `docs/STORE-BUILDS.md`)
- SDK: Connect IQ (9.2.0); `monkeyc` is in the SDK's `bin/`.
- **Sideload (on-device test):** `monkeyc -f monkey.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s` (no `-e -r`; sideload key).
- **Store packages** (`-e -r`, signed with the **store** key `~/garmin_dev_key.der`):
  - Official: `monkeyc -f official.jungle -o bin/faBolus-official.iq -y ~/garmin_dev_key.der -e -r`
  - Beta: `monkeyc -f monkey.jungle -o bin/faBolus-beta.iq -y ~/garmin_dev_key.der -e -r`
  - Build BOTH every release; upload each `.iq` to its Connect IQ store listing. `bin/` is gitignored.

## Governance, versioning & device floor (§1.3 / §1.4)
Branch model and promotion criteria are governed centrally — see [`BRANCHES.md`](BRANCHES.md) (a stub)
and the canonical [`faBolus/BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md)
for the three-branch model, the §1.2 experimental gate, and the §1.4 promotion criteria. Per-release
history is in [`CHANGELOG.md`](CHANGELOG.md).

- **Lockstep (§1.3).** faBolusGarmin is a **base feature** of faBolus, not a separate product. A Garmin
  `main` release accompanies every app `main` release and is held to the **same quality bar**; Garmin
  work does not lag behind and does **not ship separately**.
- **Published device floor.** **venu3s is the sole hardware-validated device, and the sole `main`
  build target.** The `manifest.xml` `<iq:products>` list on `main` contains only `venu3s`; additional
  devices are build-verified on the `dev/garmin-devices` branch, not on `main`. The store-facing
  statement of this floor is [`store/connectiq-listing.md`](store/connectiq-listing.md); keep the two
  in sync when a device is promoted from build-target to hardware-validated.
- **Fail gracefully on unsupported hardware (RULE).** When a capability a device genuinely cannot
  provide is requested, the app must degrade to an explicit, honest state — never misbehave, never
  present a fabricated value. This is distinct from, and must **not** disturb, the deliberate
  **honest-staleness `--`** shown when a reading is stale or absent (that is a safety signal, not a
  failure). The data field is the standing example: it structurally cannot read the BG complication, so
  it ships as a labelled placeholder (`datafield/FaBolusDataField.mc`). _(This is the governance rule;
  the specific runtime "unsupported / unavailable" message on structurally-incapable surfaces is a
  separate later increment.)_

## Conventions
- Match the phone's command semantics; device-specific input/UI differences go behind per-device checks.
  Note anything unverified on-hardware. Sibling repos: `../faBolus`, `../PumpX2Kit`.
