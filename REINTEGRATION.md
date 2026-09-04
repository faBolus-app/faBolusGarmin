# REINTEGRATION.md — dev/datafield (faBolusGarmin repo)

## Feature preserved

The `datafield` Connect IQ build target: a **separate** Connect IQ app (manifest
`type="datafield"`) from the main remote-control watch app, intended to show glucose as a field on
any activity screen (watches and Edge cycling computers). Files preserved on this branch:

- `datafield/FaBolusDataField.mc` — the `Ui.SimpleDataField` subclass.
- `datafield/FaBolusDataFieldApp.mc` — the `App.AppBase` subclass (`getInitialView`).
- `datafield.jungle` — the build config (`project.manifest = manifest-datafield.xml`,
  `base.sourcePath = datafield`, `base.resourcePath = resources`).
- `manifest-datafield.xml` — declares `id="c3d4e5f6a7b8c9d0e1f2030405060708"`, `name="@Strings.AppName"`
  (the same store name as the working remote-control listing), five `<iq:product>` entries
  (`venu3s`, `fr265s`, `fenix7`, `edge540`, `edge1040`), and `<iq:permissions/>` (empty — no
  `ComplicationSubscriber`).

## Why this branch exists — platform PROHIBITION, not a stub

This target is **structurally, permanently non-functional**, verified two independent ways:

1. `FaBolusDataField.compute()` (`datafield/FaBolusDataField.mc:27-29`) unconditionally
   `return "N/A"` with no other code path — there is no TODO left to wire up.
2. Connect IQ's app-permission model does not allow app type `datafield` to hold the
   `ComplicationSubscriber` permission, which is the only channel this app could use to read the
   faBolus public BG complication. Verified end-to-end against the vendored Connect IQ SDK
   **9.2.0**: injecting `<iq:uses-permission id="ComplicationSubscriber"/>` into a scratch copy of
   `manifest-datafield.xml` and running the SDK's manifest validator produces
   `ERROR: The following permission is invalid for app type 'datafield'`, **exit 102**. There is
   no other supported cross-app BG channel on this platform, so `compute()` can never return a
   real reading on any of its five declared products — not "not yet implemented", but
   **impossible on this app type**.

Deleted from `main` by OWNER DECISION 2026-08-31 (D-05, Phase 37 plan 02), which also noted that
`manifest-datafield.xml`'s `name="@Strings.AppName"` collides with the working remote-control
app's store listing name ("faBolus") — a second, independent reason not to ship it, on top of the
permission prohibition.

## State at removal

This branch was cut from `main` at commit `1813d700191ac836be31314cae3ea3e79231cb8e` (the tip
immediately before the deletion commit), so it carries the full pre-deletion target: source,
jungle, and manifest, unchanged from that tip.

## Reintegration steps

Reintegration only makes sense if the platform prohibition above is lifted by a future Connect IQ
SDK version (i.e. a `datafield`-type app is permitted to hold `ComplicationSubscriber`, or some
other cross-app BG channel becomes available to that app type). If/when that happens:

1. Copy back `datafield/FaBolusDataField.mc`, `datafield/FaBolusDataFieldApp.mc`,
   `datafield.jungle`, and `manifest-datafield.xml` from this branch into `main`.
2. Re-add the `compile datafield venu3s -w` step to `scripts/build-and-test.sh`'s compile matrix
   (see this branch's copy of the script, pre-deletion, for the exact line and its neighboring
   comment).
3. **Before shipping**, fix the store-name collision noted above: give the data field its own
   `name` string distinct from the remote-control app's listing, so the two Connect IQ
   submissions are not both called "faBolus".
4. **Actually wire `compute()`** to a real BG source now that the permission prohibition is
   lifted — subscribing to the faBolus public complication is the mechanism this scaffold always
   intended; do not ship another unconditional `"N/A"`.
5. Restore the documentation statements this branch's pre-deletion tree carried across
   `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, `docs/SBOM.md`, `docs/STORE-BUILDS.md`, and
   `.github/workflows/ci.yml` — cross-check against this branch's copies rather than reinventing
   the wording, since some of those statements (the fail-gracefully governance rule's standing
   example) were deliberately re-anchored to a different surface on `main` when this branch was
   cut, and should move back only if this target becomes the better example again.
6. Re-run `scripts/build-and-test.sh` on a clean tree and confirm the compile matrix and test
   count both pick back up the datafield entries this deletion removed (see the Phase 37 plan 02
   deletion commit for the exact before/after counts).

This branch does not touch faBolus's dose/signed core (a data field cannot bolus), so no
dose-set stub/frozen-wire-field un-stub is applicable to this reintegration.
