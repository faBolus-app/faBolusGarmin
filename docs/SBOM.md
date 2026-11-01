# Software Bill of Materials — faBolusGarmin

Machine-checkable provenance for every third-party / ported component this Garmin (Connect IQ /
Monkey C) app ships, builds against, or carries in-tree. `scripts/check-sbom.sh` fails if a declared
barrel dependency or a ported upstream lacks a row here (it is wired as a CI step alongside the
contract check).

faBolusGarmin is a **pure Monkey C app with no vendored third-party runtime source in the shipping
build.** The only external thing a shipping build needs — the Connect IQ SDK — is
**license-gated and is NOT vendored** into this repo (installed out-of-band).

Format per row: component · version/revision · SPDX license · source · how faBolusGarmin uses it.

## First-party (this repo)

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| faBolusGarmin app | in-repo | MIT | `source/app/` | The Monkey C remote: UI, the phone link, the bolus flow and calculator, BG complication and glance. Covered by the root `LICENSE`. |

## Required to build/run, but NOT vendored (license/credential-gated)

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| Garmin Connect IQ SDK / Monkey C runtime | 9.2.0 | LicenseRef-Garmin-Proprietary | Installed out-of-band (EULA-gated; no unattended installer) | Compiler (`monkeyc`), device runtime, simulator. Never committed. |

## Contract dependency (not code we ship)

`contract/` is a vendored copy of faBolus's `Packages/RemoteProtocol/contract/` (protocol version 2: the
field reference, JSON schema, golden fixtures and the calculator's oracle rows) at the faBolus commit in
`contract/PIN`; `scripts/check-contract.sh` checks the copy against that commit in CI. This is a shared
contract with a sibling first-party repo, not a third-party dependency.

## Trademarks

Code is MIT (root `LICENSE`); the **faBolus™** name is a trademark of Zev Granowitz and is **not** licensed by
it. Tandem, t:slim X2, Mobi, Dexcom, and Garmin are trademarks of their respective owners; faBolusGarmin
is independent and unaffiliated. See [`../NOTICE.md`](../NOTICE.md) for the full attribution prose and
[`../THIRD_PARTY.md`](../THIRD_PARTY.md) for the index.
