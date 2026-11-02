# Branches

faBolusGarmin moves with faBolus and TandemKit. The branches, the tags and what changes when `rebuild`
merges are described once, in faBolus's
[`BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md).

In short: `main` is the watch app for the earlier phone app, and `rebuild` is the watch app for the new
one. The two don't talk to each other's phone apps, so build the watch app from the same branch as the
phone app. After the three repositories merge, `main` is the only branch. `v1-final` tags the last `main`
before the rebuild, and `archive/*` tags keep the deleted side branches, among them other devices
(`archive/dev/garmin-devices`) and a watch face (`archive/experimental/2026-08-27`).
