# REINTEGRATION.md — dev/stacking-guard-disclosure (faBolusGarmin repo, W2)

## Feature preserved

The Garmin-only "Insulin Stacking Guard" dose-magnitude divergence disclosure (W2 — "This dose is far
above / well above what the pump's calculator suggested…"), removed by Phase 23 Plan 02
(`NARROW-CIQ-23`), from `source/app/AppState.mc`:

- The `sgConfirmExtraOverrideRatio`/`sgReenterOverrideRatio` module vars.
- `recommendedUnits` and `sgDisplaysNumericDose` — orphaned helper fns extended into this deletion per
  Pitfall 2 (their only 2 callers were `sgCalcOverrideLine`/`sgDisclosureLine`, both removed in the same
  commit; grep-confirmed zero other callers before deletion).
- `sgCalcOverrideLine`, `sgDisclosureLine`, `sgDisclosureIsCaution` — the disclosure-line builders for
  this surface.
- `source/app/BolusView.mc`'s `sgLine` entry in the (shared) disclosure-block render array — see "Shared
  render-loop dependency" below; the `sgLine` entry itself is this branch's own, but the loop that draws it
  is shared with the sibling `dev/control-iq-awareness` branch's `ctrlLine`.
- `tests/StackingGuardTest.mc` (whole file).

KEPT and byte-unchanged on both `main` and this branch (D-08a — explicitly NOT part of this preserved
surface): the phone-side `StackingGuard.swift` + phone `sg*Disclosure` props, in the sibling `faBolus`
repo. W2's Phase-8 display suppression there predates this phase; `sg3aAppliedFriction` is still live
confirm/hold friction logic on the phone, untouched by this Garmin-only removal.

## State at removal

Cut at faBolusGarmin `main`'s pre-removal HEAD, commit **`63b080f`** (2026-08-28) — the SAME cut point
used by this repo's `dev/control-iq-awareness` branch (Pattern 2 / D-02). Both W1 (Control-IQ awareness)
and W2 (this branch) were removed from `main` in Plan 23-02's single atomic commit `d343f6f`, because both
render into the same `BolusView.mc` disclosure-block array and both dedicated test files
(`ControllerDisclosureTest.mc`/`StackingGuardTest.mc`) would fail to compile if only one half were removed.
The two preservation branches are cut from the same commit and differentiated by REINTEGRATION.md scope —
deliberately NOT by carving `d343f6f` into two synthetic half-commits (Pattern 2 anti-pattern warning).

`main` has since (`d343f6f`, the shared commit — D-04):

1. Removed the W2 module vars + fns above from `AppState.mc` (Pitfall 2 extended the deletion to the two
   orphaned helpers, grep-verified zero other callers).
2. Removed `BolusView.mc`'s `sgLine` entry from the shared disclosure-render block (see "Shared render-loop
   dependency" below — the loop itself, and its `wrapLines`/`splitWords` helpers, are documented on the
   sibling `dev/control-iq-awareness` branch, since W1's `ctrlLine` used the same loop).
3. `git rm`'d `tests/StackingGuardTest.mc` (it called the deleted fns directly).

No signed-wire change (D-01/D-10) — the stacking-guard disclosure was never part of the signed
`RemoteCommand` schema on either repo; `./scripts/check-schema-drift.sh` confirmed schema v1, 54 keys,
unchanged.

This branch's REINTEGRATION.md is scoped to **W2 only** — it does not describe the Control-IQ awareness
(W1) / `controller*` surface, which is documented on the sibling `dev/control-iq-awareness` branch in this
same repo.

## Shared render-loop dependency (read before reintegrating either branch alone)

See the identical section in the sibling `dev/control-iq-awareness` branch's `REINTEGRATION.md` for the
full detail. Summary: `BolusView.mc`'s pre-removal disclosure block used ONE shared render loop
(`discTopY`/`discBlocks` + the static `wrapLines`/`splitWords` helpers) to draw both `ctrlLine` (W1) and
`sgLine` (W2, this branch). Reintegrating W2 alone requires restoring that shared loop too (present,
unmodified, in this branch's tree at the pre-removal cut point) and populating `discBlocks` with only the
`sgLine` entry; `computeUnits`'s `discTopY != null` positioning guard must also be restored for the loop to
have somewhere to report its layout offset.

## Reintegration path (pure deletion — no stub to remove, D-03)

1. Restore the W2 module vars + fns to `source/app/AppState.mc` from this branch's tip (diff against
   `d343f6f`'s parent, `63b080f`, for exact removal spans if `main` has drifted since).
2. Restore the shared `BolusView.mc` render loop (`discTopY`/`discBlocks`/`wrapLines`/`splitWords`, if not
   already restored by a `dev/control-iq-awareness` reintegration) and the `sgLine` entry + the
   `computeUnits` `discTopY != null` guard.
3. Restore `tests/StackingGuardTest.mc` from this branch's tip.
4. Run `./scripts/build-and-test.sh` and confirm `PASSED` with no regressions; run
   `./scripts/check-schema-drift.sh` to reconfirm the wire schema is still unchanged.

## Cross-repo note

The paired `faBolus` (phone) repo already has its own, EARLIER Phase-8 LOCK-06 stacking-guard suppression
lineage on `main` (commits `9d51d39` / `6ee571c` / `f2c97a5`) — the phone-side SG display was already
suppressed there; `sg3aAppliedFriction` remains live logic (D-08a). A future reintegration of this Garmin
branch should cross-check against that phone-side lineage to restore a coherent, parity-matched SG
disclosure experience across both platforms, rather than reviving the Garmin display in isolation against
a phone that already deliberately hides its own equivalent.
