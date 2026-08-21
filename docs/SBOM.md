# Software Bill of Materials — faBolusGarmin

Machine-checkable provenance for every third-party / ported component this Garmin (Connect IQ /
Monkey C) app ships, builds against, or carries in-tree. `scripts/check-sbom.sh` fails if a declared
barrel dependency or a ported upstream lacks a row here (it is wired as a CI step alongside the
schema-drift contract check).

faBolusGarmin is a **pure Monkey C app with no vendored third-party runtime source in the shipping
build.** The only external things a shipping build needs — the Connect IQ SDK and the private
`EatingSense.barrel` — are **license/credential-gated and are NOT vendored** into this repo (both are
`.gitignore`d / installed out-of-band). The two paused engines under `direct-cgm/` and `direct-pump/`
carry ported/reference third-party lineage and are listed for honesty even though they are **not part of
any shipping build** (compile-verified only).

Format per row: component · version/revision · SPDX license · source · how faBolusGarmin uses it.

## First-party (this repo)

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| faBolusGarmin app | in-repo | MIT | `source/app/` (+ `datafield/`) | The Monkey C remote: UI, `RemoteComm` transport router, `AppState`, BG complication. Covered by the root `LICENSE`. |

## Required to build/run, but NOT vendored (license/credential-gated)

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| Garmin Connect IQ SDK / Monkey C runtime | 9.2.0 | LicenseRef-Garmin-Proprietary | Installed out-of-band (EULA-gated; no unattended installer) | Compiler (`monkeyc`), device runtime, simulator. Never committed. |
| EatingSenseKit (`barrels/EatingSense.barrel`) | 1.0.0 | MIT (code) | Built from the private **faBolusNudge** SDK | Wrist eating-sensing barrel; streams the IMU window to the phone. Declared in `manifest.xml` / `manifest-official.xml` (`<iq:depends>`). **Uncommitted** (`.gitignore`: `barrels/*.barrel`) — a hard build prerequisite for the shipping jungles (see `WIP-REGISTER.md` item 6). |

## Ported / reference third-party source (in-tree, NOT in any shipping build — paused engines)

| Component | Upstream | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| G7 message decoder | LoopKit/G7SensorKit (© 2022 LoopKit Authors; portions xDripG5 / CGMBLEKit, © 2015–2016 Nathan Racklyeft) | MIT | `direct-cgm/engine/G7Message.mc` | Monkey C port of the Dexcom G7 / ONE+ broadcast decoder. Passive/read-only. `direct-cgm/` is paused / compile-verified only — not wired into `AppState.glucose`, not in the shipping build. |
| Tandem BLE protocol / auth / messages | jwoglom/pumpX2 (© James Woglom) | MIT | `direct-pump/` (independent reimplementation) + `tests/golden_vectors.txt` | An independent Monkey C reimplementation of the Tandem pump protocol reverse-engineered by pumpX2, byte-exact vs the pumpX2 `cliparser` oracle (golden vectors). `direct-pump/` is **excluded from every shipping jungle** and declares no BLE permission (see `WIP-REGISTER.md` item 7 / P0-c). |

## Contract dependency (not code we ship)

The remote mirrors faBolus's `schema/command.schema.json` (the source of truth) in `RemoteCommand.mc`;
`scripts/check-schema-drift.sh` enforces the mirror in CI. This is a shared contract with a sibling
first-party repo, not a third-party dependency.

## Trademarks

Code is MIT (root `LICENSE`); the **faBolus™** name is a trademark of Tia Geri and is **not** licensed by
it. Tandem, t:slim X2, Mobi, Dexcom, and Garmin are trademarks of their respective owners; faBolusGarmin
is independent and unaffiliated. See [`../NOTICE.md`](../NOTICE.md) for the full attribution prose and
[`../THIRD_PARTY.md`](../THIRD_PARTY.md) for the index.
