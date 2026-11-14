# Changelog

Notable changes to faBolusGarmin. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

faBolusGarmin has no version of its own: it moves with the faBolus app. The watch's Details screen shows
`App: <version> · <commit>`. The version is faBolus's `MARKETING_VERSION`, kept in step by
`scripts/check-version-sync.sh`, which compares it with faBolus at `contract/PIN`. The commit is written
at build time into the git-ignored `source/generated/AppRevision.mc` by `scripts/stamp-revision.sh`, with
a trailing `+` when the tree had uncommitted changes. A build without the stamp doesn't compile, so a binary is never stamped with the
wrong tree.

## [Unreleased]

### Added

- Details shows a temp rate set on the pump, with its percent ("Basal 1.20/3.00 U/hr · 40% · Temp 150%"),
  and Basal-IQ's stop for a predicted low ("Basal: Basal-IQ suspended"), which isn't the pump's suspension:
  a bolus still goes. The basal complication says "Temp" or "Basal-IQ off" for them.
- Details rows for when the CGM sensor started and was last calibrated, each left out while unknown.
- Ages of a day or more read in days ("3d ago").

### Changed

- The glucose chart leaves out a reading above its ceiling or below its floor instead of drawing it on the
  edge, where it read as a reading at the edge. The phone's plots do the same.

## [v0.4.0] — 2026-11-01

The watch app rebuilt for the new faBolus phone app, faBolus 0.4.0. The last build for the earlier phone
app is tagged `v1-final`.

### Changed

- The watch speaks protocol version 2, from the contract vendored in `contract/` at the faBolus commit in
  `contract/PIN`. A message of another version shows "Update faBolus on phone" or "Update the watch app"
  and is never read.
- The phone sends the watch's settings in a config message: screen order, the default screen, Details
  rows, chart ranges and bounds, complication slots, and the bolus and freshness windows the phone
  enforces.
- Every value carries its measurement time, and ages out on the phone's freshness windows. A stale
  complication shows no number and `--`.
- One alert card per pump alert, with Clear only once the pump has accepted a clear from the phone.
- A cancel stops the bolus request's resends, and the watch shows "Cancelling…" while the phone works on it.
- A bolus request is stamped with the watch's estimate of the phone's clock.
- The whole app passes Connect IQ strict type-checking.

### Added

- An optional "Last auto-correction" Details row.
- Optional names on the complications ("IOB 1.25"), off by default.

### Removed

- The bolus passcode. The 1 → 2 → 3 confirm, the read-only switch and the phone's checks remain.
- The analog clock face and the complication display setting. The clock screen is digital.
- The second build for a public store listing. There's one build, which you sideload or upload as your own
  private beta, and the watch calls it "faBolus".

## [v0.1.0] — 2026-07-20

The first tagged build of the watch app for the earlier phone app: glance, history, alerts and details
screens, and the bolus confirm (1-2-3 on touch, a two-button hold on button watches).
