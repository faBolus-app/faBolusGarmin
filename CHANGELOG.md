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
- A config with a screen, Details row, chart range or complication slot this build doesn't know is read
  without it, instead of being refused whole (and sent again by the phone on every poll). An unknown default
  screen is the first one known.

### Fixed

- A status Connect IQ held while the app was closed is no longer shown or used as current when it's handed
  over: a value's age is the older of the phone's view plus the time since it arrived, and the watch's clock
  less when it was measured. A status sent before the one held never replaces it, however late it arrives,
  unless it's current by the watch's clock and the one held was sent ahead of it (the phone's clock put
  right). A stored status ages the same way after a reload, by uptime as well as the wall clock.
- Only a status, bolus outcome or chart counts as hearing from the phone, and only when the phone sent it
  within the last minute, so a queued old message can't open the bolus button. A watch clock more than
  about 30 s fast keeps the button closed ("No reply from faBolus").
- The phone counts as answering only while both the wall clock and uptime say it was heard within a minute;
  with the clock stepped back (set from the phone), uptime alone decides, so a stepped-back clock neither
  keeps a silent phone live nor refuses the statuses of a talking one.
- The app registers for phone messages again with every poll, so a background service the system ends
  without exiting can't leave the app hearing nothing until it restarts.
- A phone message the system hands to the background service while the app is open now reaches the app:
  a status counts as hearing from the phone (so the bolus button no longer says "Phone not connected" while
  the glucose updates) and reaches the chart and alerts, and a bolus outcome or dismiss result is applied
  once, in order. A chart, or word that the phone app can't talk to this one, reaches the app too.
- The background service polls whatever the watch's Bluetooth flag says, and a message the system hands
  over as null no longer crashes it or the app; every path of the service ends by telling the app.
- The background service doesn't post a notification for an alert the app has already shown, unless it
  cleared and came back since. An alert that clears and comes back buzzes once, whichever of the app and
  the service sees it leave and return.
- A value whose age can't be told (after a restart with the watch's clock behind when it arrived) is shown
  marked old ("old", "(old)"), or hidden when old readings are, and never used for a correction.
- A yes to including a stale reading lapses once the reading is too old to include, and when the confirm
  is left or Deliver is pressed again, so the dose can't carry an old correction while the screen says
  "Stale CGM: carbs only".
- Carbs only, chosen for one reading, is asked again when a new reading arrives during the confirm, rather
  than sending the old reading and being refused as "Dose changed".
- With only the corrected dose over the limit, the correction question is still asked and carbs only can
  be sent; the half over the limit says so.
- Cancel stays on the button whenever a bolus is shown going; when the status showing it is old and the
  phone silent, the button says so, and a press sends the cancel, asks the phone and says it may not reach
  the phone and to stop the bolus on the pump, instead of "Cancel sent".
- The calculator's "no bolus" messages are chosen from the total before rounding down, as on the phone.
- A bolus whose transmit fails as it's handed over says "Couldn't send. Nothing was sent." instead of
  "Phone not connected".

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
