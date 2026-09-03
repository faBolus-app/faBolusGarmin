# REINTEGRATION.md — dev/direct-ble (faBolusGarmin repo)

## Feature preserved

The paused, probe-only direct-to-pump and direct-to-CGM (Dexcom G7) BLE engines, removed from `main`
by `f0a0fc3` ("refactor: remove paused direct-pump + direct-cgm BLE engines from main (narrow-main)"),
per owner decision 2026-08-27 that they never ship and should not live on `main` for
auditability/reliability — narrow-main removal, not a defect fix.

- `direct-pump/` — the direct-to-pump engine (protocol/auth/messages/BLE), byte-exact against the
  TandemKit oracle with 31-32 unit tests, plus its `probe/` bring-up harness. Blocked on unimplemented
  pure-Monkey-C secp256r1 EC-JPAKE (see `direct-pump/DIRECT_PUMP_STATUS.md:32`, "the crux") — the
  highest-value parked asset in the repo per `WIP-REGISTER.md` item 7.
- `direct-cgm/` — the direct-to-G7 CGM engine + harness, "paused / compile-verified only", never wired
  into `AppState.glucose` (`WIP-REGISTER.md` item 11).
- Build wiring for both: `probe.jungle`, `direct-cgm.jungle`, `manifest-probe.xml`,
  `manifest-directcgm.xml`, `tools/gen_golden.sh` (the direct-pump oracle-vector generator), and
  `tests/ParityTest.mc` / `tests/ResumeTest.mc` / `tests/ResponsesTest.mc` /
  `tests/golden_vectors.txt` (the direct-pump oracle-parity / resume / response tests).

**This branch also carries 7 additional Phase-21 commits made AFTER the cut** (BLE-C1/M1/M2/L1-L4/
IN-02/WR-01–05 fixes: message-level oracle parity for the 5 signed CONTROL vectors, a two-sided
<=20-byte write-chunk clamp, op-queue fail-closed + watchdogs + constant-time compare, serialized G7
CCCD writes, pump write-callback status gating, and G7 CGM watchdogs + fail-closed teardown) — so this
branch is not merely a preservation snapshot, it is the more-complete, more-hardened version of both
engines. `experimental` also carries the engines and is due the same Phase-21 fixes (owner note,
2026-08-27: "live on dev/direct-ble ... + experimental (to refresh)").

## State at removal

This branch's merge-base with `main` is `da9d68b`; `main` has since (24 commits ahead of that base,
including the removal):

1. Deleted `direct-pump/` (engine + `probe/` harness) and `direct-cgm/` (engine + harness) outright, in
   `f0a0fc3`. This branch's copies of both trees, PLUS the branch's own 7 Phase-21 hardening commits on
   top, are intact.
2. Deleted the build wiring for both: `probe.jungle`, `direct-cgm.jungle`, `manifest-probe.xml`,
   `manifest-directcgm.xml`, `tools/gen_golden.sh`, and the 4 direct-pump test files
   (`ParityTest.mc`/`ResumeTest.mc`/`ResponsesTest.mc`/`golden_vectors.txt`). This branch's copies are
   intact.
3. Rewired `test.jungle`'s `base.sourcePath` to drop `direct-pump/engine/*` (now `source/app;tests`
   only) and `scripts/build-and-test.sh`'s compile matrix to drop the `probe` + `direct-cgm` jungle
   targets. This branch's copies still include both.
4. Dropped the now-unused `BluetoothLowEnergy` permission from `manifest-test.xml`. This branch's copy
   still declares it (needed for direct BLE).
5. Updated comments in `monkey.jungle`, `.github/CODEOWNERS`, and `pull_request_template.md` to stop
   referencing the removed trees. This branch's copies still reference them (accurately, for this
   branch).
6. Shipping build unaffected either way — `monkey.jungle`/`official.jungle` never included either
   engine, on `main` or on this branch. No `source/app`/dose/alert/complication behavior changed by the
   removal, and none of this branch's 7 hardening commits touch `source/app` either.

`build-and-test.sh` was green on `main` post-removal at 241/241 (was 270 including the 29 removed
engine tests). This branch's own suite is reported at 270/270 (per the phase's own tracking note),
consistent with carrying both engines plus their tests.

## Reintegration path

1. Re-add `direct-pump/` (engine + `probe/`) and `direct-cgm/` (engine + harness) from this branch —
   use this branch's copies, not `main`'s pre-removal history, since this branch carries the later
   Phase-21 hardening on top.
2. Re-add the build wiring: `probe.jungle`, `direct-cgm.jungle`, `manifest-probe.xml`,
   `manifest-directcgm.xml`, `tools/gen_golden.sh`, and the 4 direct-pump test files.
3. Restore `test.jungle`'s `base.sourcePath` to include `direct-pump/engine/*` and
   `scripts/build-and-test.sh`'s compile matrix to include the `probe` + `direct-cgm` jungle targets.
4. Restore the `BluetoothLowEnergy` permission to `manifest-test.xml`.
5. Restore the `monkey.jungle` / `.github/CODEOWNERS` / `pull_request_template.md` comments that
   reference the trees.
6. Before shipping either engine (as opposed to reintegrating it onto `main` merely to resume paused
   work), re-close the secp256r1 EC-JPAKE gap that blocks `direct-pump/` (`DIRECT_PUMP_STATUS.md:32`)
   and re-wire `direct-cgm/` into `AppState.glucose` — neither gap was closed by the Phase-21 hardening
   commits, which fixed BLE-layer defects, not the pairing/wiring blockers.
7. Re-verify byte-exactness against the current TandemKit oracle before any reintegration — the oracle
   may have moved since this branch's cut.
