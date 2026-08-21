# REINTEGRATION.md — dev/garmin-devices (faBolusGarmin repo)

## Feature preserved

The non-`venu3s` Garmin device build targets (Phase 2, GARMIN-01): `fr265s`, `fenix7`, `fr245`,
`edge540`, `edge1040` — declared as `<iq:product>` entries in `manifest.xml`'s `<iq:products>`
block, alongside the sole hardware-validated device (`venu3s`). Also preserved on this branch: the
**standalone watch-face app** (`manifest-watchface.xml`, `watchface.jungle`, and the
`watchface/` source directory: `FaBolusFaceApp.mc`, `FaBolusFaceView.mc`), a separate
Connect IQ build target from the main remote-control watch app.

Per `BRANCHES.md`'s "Minimum Garmin device set" section, `fr265s`/`fenix7`/`fr245`/`edge540`/
`edge1040` were previously **compile-verified only, not hardware-validated** — `venu3s` remains
the sole hardware-validated device both before and after their removal from `main`.

## State at removal

Removed from `main`'s `manifest.xml` in Phase 2 (GARMIN-01): `main`'s `<iq:products>` block now
declares only `venu3s`. This branch (`dev/garmin-devices`) already diverged from `main` when this
research was performed — it is the second branch (after `dev/cgm-extra` in the faBolus repo) whose
surface has actually been removed, and it retains the full pre-removal manifest (all 6 device
`<iq:product>` entries) plus the standalone watch-face app files, none of which exist in `main`'s
manifest or source tree once removed.

## Reintegration steps

1. **Restore the manifest device entries**: add back the `fr265s`, `fenix7`, `fr245`, `edge540`,
   `edge1040` `<iq:product>` entries to `main`'s `manifest.xml` `<iq:products>` block (see this
   branch's `manifest.xml` for the exact entries plus their explanatory comments — button-watch vs.
   touch-input vs. cycling-computer distinctions, and the `fr245`/cycling-computer note about
   Complications being compiled out via `monkey.jungle`).
2. **Restore the standalone watch-face app**: copy back `manifest-watchface.xml`,
   `watchface.jungle`, and the `watchface/` directory (`FaBolusFaceApp.mc`, `FaBolusFaceView.mc`)
   from this branch into `main`.
3. Re-confirm `BRANCHES.md`'s "Minimum Garmin device set" table still lists the restored devices
   correctly, and update `faBolusGarmin/store/connectiq-listing.md` (the store-facing source of
   truth for the supported-devices list) to match.
4. Re-run the compile-verification build for each restored device target (they remain
   compile-verified-only, not hardware-validated, unless separately bench-tested) and the
   watch-face app's own build.
5. Re-check `faBolusGarmin/scripts/check-schema-drift.sh` and the `RemoteCommand` schema-version
   compatibility matrix in `BRANCHES.md` §1.3 — restoring build targets does not change the wire
   schema, but confirm no drift was introduced by unrelated changes in the interim.

This branch does not touch faBolus's dose/signed core (it is a separate repo entirely, consumed
read-only by faBolus per the cross-repo lockstep described in `BRANCHES.md`), so no dose-set
stub/frozen-wire-field un-stub is applicable to this reintegration.
