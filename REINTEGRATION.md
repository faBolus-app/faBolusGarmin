# REINTEGRATION.md — dev/control-iq-awareness (faBolusGarmin repo, Garmin half of W1)

## Feature preserved

The Control-IQ auto-correction AWARENESS DISPLAY surface (W1, Garmin half), removed by Phase 23 Plan 02
(`NARROW-CIQ-23`), from `source/app/AppState.mc`:

- Helper fns/consts: `controllerDisplayName`, `controllerAutoCorrects`, `controllerLockoutMinutes`,
  `controllerTrendRising`, `controllerAmbientText`, `controllerLockoutText`, `controllerLockoutFraction`,
  `controllerLockoutMinutesRemaining`; the `CONTROLLER_RISING_TRENDS`/`CONTROLLER_DISCLOSE_AT_OR_ABOVE`/
  `CONTROLLER_DISCLOSE_RISING_AT_OR_ABOVE` consts; the CIQ activity block (`CIQ_SLEEP_TARGET_*`/
  `CIQ_EXERCISE_*` consts, `ciqAutoBolusWords`, `ciqActivityCompactLine`, `ciqExerciseEndsAtLabel`); and
  `controllerDisclosureLine`/`controllerDisclosureIsCaution` (the top-level disclosure-line builders for
  this surface).
- `source/app/CgmView.mc`'s lockout-countdown bar block: the drawn rect bar + the "_N_m until next
  correction" printed numeral.
- `source/app/DetailsView.mc`'s `"sleepExercise"` details row (and its catalog entry, `"sleepExercise"`,
  in `AppState.ALL_DETAILS`).
- `tests/ControllerDisclosureTest.mc` (whole file) — the only Garmin-side test exercising the frozen-token
  guard + strict-boolean guard for `controllerVariant`/`controlIQEnabled` (its
  `parsesVariantAndEnabledWithGuards` test used `controllerDisclosureLine()` as its observable proof
  point). **Its retirement is the one accepted, recorded coverage gap of this phase** — see
  `23-OWNER-DECISION-clinical-copy.md` in the faBolus-internal planning repo for the full disposition.

KEPT and byte-unchanged on both `main` and this branch (D-01/D-08 — NOT part of this preserved surface,
do not restore/re-touch): the frozen `CONTROLLER_VARIANTS`/`CIQ_ZONES` wire consts, `AppState.handle()`'s
parse guards, `maxBasalFraction()` (T1-8, an unrelated fn that happens to sit between two of the removed
fn groups in `AppState.mc`), and `DetailsView.mc`'s `ciqZone`/`ciqSuspend`/`autoCorrection`/
`couldNotDeliver`/`maxBasal` rows.

## State at removal

Cut at faBolusGarmin `main`'s pre-removal HEAD, commit **`63b080f`** (2026-08-28) — the parent of Plan
23-02's single atomic removal commit `d343f6f`. This is the SAME cut point used by this repo's sibling
`dev/stacking-guard-disclosure` branch (Pattern 2 / D-02): both W1 and W2 render into the same
`BolusView.mc` disclosure-block array and were removed in one commit, so the two preservation branches
share a cut point and are differentiated by REINTEGRATION.md scope, not by diff surgery.

`main` has since (`d343f6f`, one commit — D-04):

1. Removed the W1 fns/consts above from `AppState.mc` by function boundary (Pitfall 1 honored —
   `maxBasalFraction()` preserved verbatim between the two W1 fn groups; the frozen wire consts + parse
   guards untouched, D-01).
2. Removed W1's share of `BolusView.mc`'s disclosure-render block: the `ctrlLine` entry that fed the
   shared `discBlocks` array, and the wrap-and-color render loop over that array. **This render loop and
   its two now-orphaned static helpers, `wrapLines`/`splitWords`, are SHARED infrastructure also used by
   W2's `sgLine` entry** — see the "Shared render-loop dependency" note below; they are NOT restorable by
   this branch alone.
3. Removed `CgmView.mc`'s lockout-countdown bar + numeral (this surface's own, non-shared render site).
4. Removed the `"sleepExercise"` row from `DetailsView.mc` and its `ALL_DETAILS` catalog entry (Pitfall 8).
5. `git rm`'d `tests/ControllerDisclosureTest.mc` (it called the deleted fns directly).

No signed-wire change (D-01/D-10): `./scripts/check-schema-drift.sh` confirmed schema v1, 54 keys,
unchanged, both before and after this removal.

This branch's REINTEGRATION.md is scoped to **W1 only** — it does not describe the stacking-guard (W2)
surface (`sgConfirmExtraOverrideRatio`/`recommendedUnits`/`sgDisplaysNumericDose`/`sgCalcOverrideLine`/
`sgDisclosureLine`/`sgDisclosureIsCaution`/`StackingGuardTest.mc`), which is documented on the sibling
`dev/stacking-guard-disclosure` branch.

## Shared render-loop dependency (read before reintegrating either branch alone)

`BolusView.mc`'s pre-removal disclosure block used one shared render loop (`discTopY`/`discBlocks` +
`wrapLines`/`splitWords`) to draw BOTH the `ctrlLine` (W1, this branch) and `sgLine` (W2, sibling branch)
entries. `computeUnits`'s positioning block also had a `discTopY != null` guard tied to that same shared
loop's presence (Pitfall 7 — the guard was permanently-false once the loop was removed, so `main` simplified
it away entirely rather than leaving a dead conditional).

- Reintegrating **W1 alone**: you must also restore the shared render loop + `wrapLines`/`splitWords` +
  the `computeUnits` `discTopY != null` positioning branch (all present, unmodified, in this branch's tree)
  to have anywhere to draw `ctrlLine` — but leave `discBlocks` populated with only the `ctrlLine` entry (no
  `sgLine`) unless W2 is being reintegrated at the same time.
- Reintegrating **both W1 and W2 together**: restore the shared loop once (from either branch — they are
  byte-identical at this shared cut point) and populate `discBlocks` with both entries, matching the
  original interleaved `main` state before `d343f6f`.

## Reintegration path (pure deletion — no stub to remove, D-03)

1. Restore the W1 fns/consts to `source/app/AppState.mc` from this branch's tip (diff against `d343f6f`'s
   parent, `63b080f`, for exact removal spans if `main` has drifted since).
2. Restore the shared `BolusView.mc` render loop (`discTopY`/`discBlocks`/`wrapLines`/`splitWords`) and the
   `ctrlLine` entry + the `computeUnits` `discTopY != null` guard (see "Shared render-loop dependency"
   above for whether to also restore `sgLine`).
3. Restore `CgmView.mc`'s lockout-countdown bar + numeral.
4. Restore `DetailsView.mc`'s `"sleepExercise"` row and its `ALL_DETAILS` catalog entry.
5. Restore `tests/ControllerDisclosureTest.mc` from this branch's tip.
6. Run `./scripts/build-and-test.sh` and confirm `PASSED` with no regressions; run
   `./scripts/check-schema-drift.sh` to reconfirm the wire schema is still unchanged.

## Cross-repo note

The paired faBolus (phone) repo's own `dev/control-iq-awareness` branch carries the phone half of this
same W1 surface (S1 lockout caution, O3 ambient indicator, `ControlIQDisableWarning`). The two halves are
independent display surfaces with no shared wire dependency and can be reintegrated separately or
together.
