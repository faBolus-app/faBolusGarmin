# AGENTS.md — faBolusGarmin

Working notes for agents and humans. Garmin (Connect IQ / Monkey C) remote for faBolus — a thin
remote that relays confirmed commands to the iPhone host, which owns the pump. Experimental, not
FDA-cleared. Companion map: [`llms.txt`](llms.txt). Branch policy is canonical in
[faBolus `BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md); the local
[`BRANCHES.md`](BRANCHES.md) is a pointer.

## Safety
- The phone is the authority. This app **requests**; it does not dose on its own. There is **no**
  direct-to-pump or direct-to-CGM engine on `main` (those trees live on `dev/direct-ble` /
  `experimental`).
- Bolus confirm is a deliberate gesture per device (touch 1-2-3 / two-button hold). Don't weaken it.
  It is one explicit gesture, not a second host confirmation. The phone recomputes the dose from carbs,
  rejects divergence, and clamps to max bolus.

## Command contract
`RemoteCommand` is mirrored in Monkey C from faBolus's `schema/command.schema.json`. Change fields →
update the mirror → `scripts/check-schema-drift.sh`. Phone-only kinds (auth/sealed/approval) are not
in this shared schema.

## Layout
- `source/app/` — UI, bolus confirm, `RemoteComm` (phone-relay), `AppState`.
- Jungles: `monkey.jungle` + `manifest.xml` (Beta), `official.jungle` + `manifest-official.xml`
  (Official), `test.jungle`.
- **venu3s** is the sole `main` build target and the sole hardware-validated device. Other devices
  live on `dev/garmin-devices`.
- `tests/` — Monkey C unit suite (run locally; CI has no SDK).

Sibling repos: `../faBolus`, `../TandemKit`.

## Build + test
- **Local gate:** `./scripts/build-and-test.sh` compiles every jungle and runs the unit suite in the
  simulator. CI runs the schema-drift contract check, the SBOM / license-provenance check
  (`scripts/check-sbom.sh`), and a Semgrep pass over the shared deslop ruleset — the report is
  advisory, but the residue count is ratcheted: a second CI step fails if any residue rule rises
  above its committed baseline (`.semgrep/baseline.json`) — see `.github/workflows/ci.yml`. CI
  cannot build or run the Monkey C suite (no SDK/simulator in cloud CI), so the build + unit gate
  is LOCAL only. `monkeydo`'s exit code lies — the script parses `PASSED (…failed=0, errors=0)`.
- **Sideload:** `./scripts/stamp-revision.sh && monkeyc -f monkey.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s`
  (the Details "App:" row's commit stamp is generated and git-ignored; skipping it fails the compile on
  `Undefined symbol ':AppRevision'` rather than shipping a wrongly-stamped binary)
- Store builds: [`docs/STORE-BUILDS.md`](docs/STORE-BUILDS.md) (Connect IQ SDK 9.2.0).

## Device floor
venu3s only on `main`. Fail gracefully on a capability a device/display cannot provide — never
fabricate a value. That is distinct from honest-staleness `--` (a safety signal). The BG
complication's numeric `:value` slot is the standing example: it cannot render `--` at all, so
`BgComplication.shortLabelFor` marks a stale reading with an explicit `" old"` suffix instead — an
honest indicator of the platform limitation, never a bare dash that could pass for a fresh reading
(`source/app/BgComplication.mc`).

## Conventions
Match the phone's command semantics. Device input/UI differences go behind `DeviceProfile`. Comments
explain why (confirm gesture, staleness, schema). Do not add phase/ticket IDs or describe deleted
engines as if they were on `main`.

`semgrep --config <faBolus>/.semgrep/deslop.yml --metrics=off .` flags AI-process residue in the
Monkey C sources and tests. The ruleset lives in the faBolus repo; CI fetches it by raw URL. The
report itself is advisory, but the residue count is ratcheted (a second CI step fails if any
residue rule rises above its committed baseline). Scan `.`, not `source` — `tests/` is in the globs
too, and the
committed `.semgrepignore` exists because semgrep's built-in default list drops a lowercase
`tests/`. Triage by hand: a display-width budget ("runs 29-30+ chars") matches the ticket pattern and
is a KEEP.
