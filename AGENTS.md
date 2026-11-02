# AGENTS.md — faBolusGarmin

Working notes for agents and humans. Garmin (Connect IQ / Monkey C) remote for faBolus — a thin
remote that relays confirmed commands to the iPhone host, which owns the pump. Experimental, not
FDA-cleared. Companion map: [`llms.txt`](llms.txt). Branches: [faBolus `BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md);
the local [`BRANCHES.md`](BRANCHES.md) points there.

## Safety

- The phone is the authority. This app **requests**; it does not dose on its own. There is **no**
  direct-to-pump or direct-to-CGM engine (an earlier one is on the `archive/dev/direct-ble` tag).
- Bolus confirm is a deliberate gesture per device (touch 1-2-3 / two-button hold). Don't weaken it.
  It is one explicit gesture, not a second host confirmation. The phone recomputes the dose from carbs,
  refuses it if it differs from the watch's estimate, and the pump's own limits govern.

## Phone↔watch contract

The watch speaks protocol version 2, defined in faBolus's `Packages/RemoteProtocol/contract/` (field
reference, JSON schema, golden fixtures written by the phone's Swift, and the calculator's oracle rows).
`contract/` here is a vendored copy at the faBolus commit in `contract/PIN`; change it only with
`scripts/sync-contract.sh <faBolus-commit>`. `scripts/check-contract.sh` checks the copy against that
commit, and the unit suite reads every fixture and runs the calculator on every oracle row. A message of
any other version is shown as "update", never read.

## Layout

- `source/app/` — one module per concern, each the only writer of its `Storage` keys (`Store.mc` names
  them): `Link` (the phone link: polling, backoff, transmit), `Wire` (messages), `Inbound` (dispatch),
  `Status`, `Prefs`, `History`, `Alerts`, `BolusFlow` (the bolus request and its outcome), `Calculator`,
  `Display`; the views and delegates; `BgService`/`BgComplication` (background) and
  `FaBolusGlanceView` (glance).
- `contract/` — the vendored phone↔watch contract (see above).
- Jungles: `monkey.jungle` + `manifest.xml` (Beta), `official.jungle` + `manifest-official.xml`
  (Official), `test.jungle`.
- **venu3s** is the sole build target and the sole hardware-validated device. Builds for other devices
  are on the `archive/dev/garmin-devices` tag.
- `tests/` — Monkey C unit suite (run locally; CI has no SDK). `scripts/gen-test-resources.sh` turns
  `contract/` into the suite's resources under `tests/generated/` (git-ignored).

Sibling repos: `../faBolus`, `../TandemKit`. `scripts/beta-build.sh`, `scripts/sync-contract.sh`,
`scripts/check-contract.sh` and `scripts/check-version-sync.sh` default to `../faBolus`.

## Build + test

- **Gates:** `./scripts/check.sh` runs them all; run `./scripts/setup.sh` once per clone so the
  pre-push hook runs it before every push. Its `build` gate is `./scripts/build-and-test.sh`, which
  compiles every jungle, fails on any compiler warning (SDK 9.2.0 has no warnings-as-errors flag, so
  the script is the flag) and runs the unit suite in the simulator. Hosted CI can't run that gate
  (the SDK's license keeps it out of public CI, and the tests need the simulator's window), so CI
  runs the rest: ShellCheck, actionlint, markdownlint, the contract check (against a checkout of
  faBolus at `contract/PIN`) and the SBOM check. Semgrep reports only. `monkeydo`'s exit code lies, so the script parses
  `PASSED (…failed=0, errors=0)`.
- **Sideload:** `./scripts/stamp-revision.sh && monkeyc -f monkey.jungle -o bin/faBolus.prg -y developer_key.der -d venu3s`
  (the Details "App:" row's commit stamp is generated and git-ignored; skipping it fails the compile on
  `Undefined symbol ':AppRevision'` rather than shipping a wrongly-stamped binary)
- Store builds: [`docs/STORE-BUILDS.md`](docs/STORE-BUILDS.md) (Connect IQ SDK 9.2.0).

## Device floor

venu3s only. Fail gracefully on a capability a device/display cannot provide — never
fabricate a value. That is distinct from honest-staleness `--` (a safety signal). The complications
are the standing example: a face can't show a value's age, so a stale value is published as no number
and the label `--`, never as a value that could pass for a current one (`source/app/BgComplication.mc`).
The glucose complication's colour bands are mg/dL and can't follow the user's unit, so with mmol/L it
publishes only its label, never a number in the wrong unit or one the bands colour wrongly.
Their arrows are ASCII (`^`, `/`, `->`): a face draws the label in its own font, Garmin's guidance is
Latin characters only, and a symbol a device's font lacks shows as `?` or nothing.

## Reviewing

<!-- Only facts a reviewer can't get from the diff. How to review is the review tool's job; don't restate it here. -->

Facts a reviewer needs that the diff doesn't show:

- The Safety section above names what matters most here.
- Out of scope: anything a `check.sh` gate already fails on. Every jungle type-checks at strict
  (level 3). A `(:typecheck([disableBackgroundCheck, disableGlanceCheck]))` annotation declares which
  process a module runs in (Garmin's BackgroundTimer sample pattern); it turns off no type check.
- Connect IQ behavior is checked against the SDK 9.2.0 docs and samples, at the manifests'
  `minSdkVersion`.
- The app, the glance and the background service run as separate processes that share
  `Application.Storage`, so a key written by more than one of them can be overwritten. Glance and
  background code also run under much smaller memory limits.
- The fixtures are messages the phone's code produced, so a change to a field's type or meaning fails
  the suite once `contract/` is synced; until then the watch tests against the pinned contract.
- Most past bugs were in the phone↔watch link: state kept outside a state machine, retry loops, stuck
  states after a drop, and messages lost, duplicated or reordered.

## Conventions

Match the phone's semantics. Touch and button input branch on `Nav.isTouch()`. Comments
explain why (confirm gesture, staleness, schema). Do not add phase/ticket IDs or describe deleted
engines as if they were in the tree.

`semgrep --config <faBolus>/.semgrep/deslop.yml --metrics=off .` reports AI-process residue (ticket
IDs, drifted line references) in the Monkey C sources and tests. It is a report, not a gate. Scan `.`,
not `source`: the committed `.semgrepignore` exists because semgrep's built-in default list drops a
lowercase `tests/`.
