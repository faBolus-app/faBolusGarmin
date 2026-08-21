# Changelog

All notable changes to **faBolusGarmin** are recorded here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

faBolusGarmin does not carry its own product version number: it moves in **lockstep** with the faBolus
app (see [`BRANCHES.md`](BRANCHES.md) §1.3 and the canonical
[`faBolus/BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md)). Releases here
are therefore anchored to the shared **tags** — the immovable `deprecated/*` pre-round-3 snapshot and the
**moving** `safe-baseline/*` last-known-good pointer — rather than to SemVer. The Connect IQ store
listings (Official / Beta) are versioned independently by the store; that is not tracked here.

This is a seeded/back-filled history: entries before the first CHANGELOG commit were reconstructed from
the git log and the tag graph, so they are grouped and summarized rather than exhaustive.

## [Unreleased]

### Changed
- **Phase-2 narrowing (2026-08-20).** `main`'s shipping build target is narrowed to the **Garmin
  Venu 3S only**: the five non-Venu devices (`fr265s`, `fenix7`, `fr245`, `edge540`, `edge1040`) are
  removed from both shipping manifests (`manifest.xml`, `manifest-official.xml`) and their jungle/
  build-script/CI-matrix lines, and retained on the `dev/garmin-devices` branch. The standalone
  Garmin **watch face** app (`manifest-watchface.xml` + `watchface.jungle` + `watchface/`) is removed
  from `main` and retained on `experimental`; the BG **complication publisher**
  (`source/app/BgComplication.mc` + `resources-complications/`) is unchanged and continues to ship
  for `venu3s`. Docs (`README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/STORE-BUILDS.md`,
  `docs/SBOM.md`, `store/connectiq-listing.md`) and `.mc` comments reconciled to match — no
  `main`-side doc or comment names a removed device or the removed watch face as a current target.

## [safe-baseline/2026-08-07-p15] — 2026-08-07

Moving last-known-good pointer, advanced to `979802b`. Lockstep with faBolus
`safe-baseline/2026-08-07-p15`.

### Added
- P15 §2.3: parse, gate, and persist the phone-driven **Garmin bolus-enable** (`garminBolusEnabled`),
  with a one-time on-watch notice when bolusing is first enabled (G3b / G5).
- P15 Addendum B (AB4): **stale-CGM three-way bolus prompt** on the watch (include-stale / carbs-only /
  cancel), mirroring the shared faBolusCore prompt.
- P15 E3/E4/E4b: conventional **analog clock** face redesign with a self-refresh timer, glucose reading
  **age** on the clock screen, and a phone-driven analog-clock preference (the on-watch toggle was
  dropped in favour of the phone setting).

### Changed
- P13c-1: aligned the Garmin **glucose bands** to the closed clinical convention shared with the phone.

### Fixed
- P15 §2.3 G4: tear down an armed `HoldView` when the phone disables bolusing mid-flow.

## [safe-baseline/2026-08-04] — 2026-08-05

Moving last-known-good pointer, first established at `008190d` (tag name encodes the §1.3 governance
snapshot date; lockstep with faBolus `safe-baseline/2026-08-04`). Gathers the round-3 safety fixes, the
CI enablement, and the P5/P6/P9–P13a Garmin work.

### Added
- P9 S8: reliably surface a newly-arrived pump **ALERT** to the watch (notification fan-out).
- P11: **stamp send-time** (`sentAt`) on delivery-authorizing commands so the host can reject a stale
  request.
- P13a-2: Garmin alert-confirm **verb** derived from `supportsRemoteAlertDismiss` (Clear vs Snooze).

### Changed
- P12 group D: gate the Garmin **START-bolus** on the host's semantic `canBolus` / `bolusBlockReason`
  rather than a local guess.
- E5: plot CGM history on a **real-time x-axis** so a gap in readings renders as a gap.

### Fixed
- Group A / A1: an **unknown-age** reading is treated as **stale**, never as "now" — the honest-staleness
  rule that the `--` / age display depends on.

### CI / infrastructure
- **CI actually runs.** Triggers were pointed at `main` (and `experimental`); the workflow had fired
  **zero** times since the default-branch rename from `master`, so an absent check had been reading as a
  passing one.
- P5: **branch-aware** faBolus checkout for the schema-drift contract check (match the sibling branch,
  else fall back to `main`, logging the resolved ref **and its SHA**); added the `experimental` trigger.
- The schema-drift check now also asserts `RemoteComm.mc`'s `SCHEMA_VERSION` equals the schema's
  `version` const.
- P6: added the **local** Garmin build+test harness (`scripts/build-and-test.sh`) and recorded why a
  faithful full Garmin build/test in cloud CI is infeasible (license-gated SDK, GUI-simulator unit tests,
  private `EatingSense.barrel`) — the schema-drift contract check is CI's only Garmin coverage by design.
- Captured the pre-restructuring **WIP register** (`WIP-REGISTER.md`) per v3 handoff §0.1.

## [deprecated/2026-08-04-v0.1.0-build1] — 2026-07-23 _(frozen snapshot — do not use as a fallback)_

Immovable snapshot of `main` (`659dc34`) **before** the round-3 safety fixes. Rolling back here
reintroduces every known pre-round-3 issue; it exists for forensics/bisection only, not as a supported
fallback. Notable work in this window (after `v0.1.0`):

### Added
- Round-3 Garmin remote safety (GA-01…GA-09): gesture-proof residual-risk documentation, touch
  double-routing guard, staleness persistence, and inbound-command validation.
- Read-only mode: hide the bolus button on `remotesReadOnly`; add a CGM-only "glucose" screen.
- Clock and bolus-only screens; per-person **personal beta** build (`scripts/beta-build.sh`, unique
  Connect IQ app id) and the split into **Official + Beta** store apps (distinct app ids).
- EatingSenseKit barrel integration (stream the IMU window to the phone) and OFFICIAL-app parity.
- Support for Forerunner **265S** and **245** (the latter with the Complications module compiled out).
- Send carbs (+ BG + estimate) in carbs mode for the host calculator; request a fresh CGM read when the
  bolus screen opens.
- `AGENTS.md`, `llms.txt`, and store-build documentation.

### Fixed
- GA-04: round bolus components to 2-decimal HALF_UP before combining (oracle parity).
- C-01: port the oracle bolus calculation for the wrist preview.
- BG **complication** correctness (numeric-value-first write, `:ranges` publish, string+ASCII-trend
  publish, `:unit`→`:units` cascade), and the data field's platform limitation (cannot subscribe to the
  complication — permanent, labelled placeholder).
- Self-heal a stuck bolus button; show the delivered amount on cancel; never fabricate a cancelled
  outcome; keep a cancelled/delivering result on screen until acknowledged.

### Changed / docs
- Phase-0 doc corrections (drop the "second factor" / "host confirmation" overclaim); trademark claim for
  the faBolus™ name in `NOTICE.md` / `README.md`; the iPhone Garmin target now defaults to Beta (the
  Official listing is dormant).

## [v0.1.0] — 2026-07-20

Initial tagged build (`2e4eed3`). The phone-relay Garmin remote: glance / history / alerts / details
screens, the bolus confirm (touch 1-2-3 and button two-button-hold), and the phone↔remote JSON contract.

### CI / infrastructure
- Added the Monkey C ↔ contract **schema-drift** check (`scripts/check-schema-drift.sh`), mirroring the
  Swift-side check, to keep the `RemoteCommand.mc` mirror in sync with
  `faBolus/schema/command.schema.json`. _(Note: this workflow initially triggered on `master`; it did not
  actually run until the trigger was repointed at `main` in the `safe-baseline/2026-08-04` window.)_
