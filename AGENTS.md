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
  `datafield.jungle`, `watchface.jungle`, `direct-cgm.jungle`.
- Devices: `venu3s` (touch: onTap) + button devices (fenix7, fr265s, fr245, edge540, edge1040 — UP/DOWN
  + two-button-hold confirm). `fr245` has no Complications module (compiled out via
  `fr245.excludeAnnotations = complications`).
- `tests/`, `tools/gen_golden.sh` — parity/golden tests.

## Build (authoritative: `docs/STORE-BUILDS.md`)
- SDK: Connect IQ (9.2.0); `monkeyc` is in the SDK's `bin/`.
- **Sideload (on-device test):** `monkeyc -f monkey.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s` (no `-e -r`; sideload key).
- **Store packages** (`-e -r`, signed with the **store** key `~/garmin_dev_key.der`):
  - Official: `monkeyc -f official.jungle -o bin/faBolus-official.iq -y ~/garmin_dev_key.der -e -r`
  - Beta: `monkeyc -f monkey.jungle -o bin/faBolus-beta.iq -y ~/garmin_dev_key.der -e -r`
  - Build BOTH every release; upload each `.iq` to its Connect IQ store listing. `bin/` is gitignored.

## Conventions
- Match the phone's command semantics; device-specific input/UI differences go behind per-device checks.
  Note anything unverified on-hardware. Sibling repos: `../faBolus`, `../PumpX2Kit`.
