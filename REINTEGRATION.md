# REINTEGRATION.md — dev/garmin-hr-relay (faBolusGarmin repo)

## Feature preserved

- `source/app/HeartRateRelay.mc` (whole file, incl. `HeartRateCommListener`) — the ambient
  heart-rate relay. Reads the watch's own `ActivityMonitor.getHeartRateHistory` (ambient history
  only, never live optical-sensor streaming) and, when phone-enabled, transmits an out-of-band
  `hr_window` envelope to the phone, piggybacked on `FaBolusApp.pollTick`'s existing ~15s status
  cadence (no new timer/radio wake).
- `source/app/FaBolusApp.mc`: the `_hr as HeartRateRelay?` field, `onStop`'s `if (_hr != null) {
  _hr.stop(); }`, the guarded HR piggyback in `pollTick()` (`try { if (_hr != null) {
  _hr.emitIfDue(); } } catch (e) { _pollGuardFailureCount += 1; }`, sitting between the
  dismiss-retry try/catch and `scheduleNextPoll()`), the `setHrRelay(hr as HeartRateRelay?)`
  test-only injection seam, and the `hr_ctl` branch in `handlePhoneData` (lazily constructs `_hr`
  on first toggle, calls `setEnabled(data["on"] == true)`).
- `tests/RelayResilienceTest.mc`'s pre-Phase-22 state: `Test 1`
  (`pollTickSchedulesDespiteEmitIfDueThrow`) and the `ThrowingHeartRateRelay` double (subclasses
  `HeartRateRelay`, overrides `emitIfDue()` to always throw) that proved the C5-01/CX-G-05
  pollTick-guard invariant via the HR piggyback specifically. Read the commit immediately BEFORE
  this branch's tip (the Phase-22 removal's parent) for the exact bodies.

## State at removal

Cut at faBolusGarmin `main`'s pre-removal HEAD (`bba3c4b`). Phase 22
(`Remove Garmin-to-phone ambient-HR relay from main`, requirement `NARROW-HR-22`) then, on `main`:

- `git rm`'d `HeartRateRelay.mc` wholesale — no jungle/manifest edit needed, since `test.jungle`'s
  `base.sourcePath = source/app;tests` already compiles `source/app` wholesale.
- Excised the 5 `FaBolusApp.mc` sites named above; trimmed the now-stale in-file comments that
  referenced the relay (initialize-deferral, `_scheduleCount`, `_pollGuardFailureCount`,
  dismiss-retry cross-refs) to name only the surviving `EatingRelay`/`eating_sense` and
  dismiss-retry paths.
- Added a NEW test-only `RemoteComm.testDismissAlertThrows` seam (a guarded throw at the top of
  `dismissAlert()`, mirroring the file's own `testSuppressTransmit`/`testPhoneReachable` idiom) so
  the retargeted `RelayResilienceTest` Test 1 (`pollTickSchedulesDespiteDismissRetryThrow`) could
  keep proving the C5-01/CX-G-05 pollTick-guard invariant via the SURVIVING dismiss-retry resend
  loop, since the HR piggyback that used to exercise it is gone. `false` is the shipping default,
  never assigned outside the unit suite; `dismissAlert()`'s returned dict shape is unchanged when
  the flag is false.
- Retargeted the 3 `hr_ctl`-sample tests (`StatusReplyTest.mc`, `BgPushWakeTest.mc`,
  `PhoneMessageCastGuardTest.mc`) onto the surviving `eating_sense` out-of-band toggle — they used
  `hr_ctl` only as an example of "a non-reply/non-push dict", an invariant `eating_sense` also
  satisfies.
- No signed-wire change: `RemoteComm.SCHEMA_VERSION` stayed `1`; every other command shape is
  byte-unchanged. `hr_window`/`hr_ctl` were always strictly out-of-band (never part of the signed
  `RemoteCommand` schema on either side of this repo pair).

## Reintegration steps

1. Restore `source/app/HeartRateRelay.mc` from this branch, byte-for-byte.
2. In `FaBolusApp.mc`, re-add (diff this branch against the removal commit's parent for exact
   insertion points):
   - the `_hr as HeartRateRelay?` field declaration;
   - `onStop`'s `if (_hr != null) { _hr.stop(); }`;
   - the guarded HR piggyback block in `pollTick()`, positioned between the dismiss-retry
     try/catch and `scheduleNextPoll()` exactly as this branch has it;
   - the `setHrRelay(hr as HeartRateRelay?) as Void { _hr = hr; }` test seam;
   - the `hr_ctl` branch in `handlePhoneData` (lazy-construct `_hr`, `setEnabled(...)`).
3. `RemoteComm.testDismissAlertThrows` (added by the Phase-22 removal) can be left in place —
   it's a harmless, always-false-in-shipping test seam — UNLESS you are also restoring
   `RelayResilienceTest.mc`'s original HR-relay-double Test 1 (step 4), in which case either seam
   independently proves the pollTick-guard invariant; keeping both is not incorrect, just
   redundant.
4. Restore `tests/RelayResilienceTest.mc`'s pre-removal `ThrowingHeartRateRelay` double and its
   original Test 1 (`pollTickSchedulesDespiteEmitIfDueThrow`) from this branch if HR-relay-specific
   coverage is wanted back; otherwise the Phase-22 dismiss-retry retarget
   (`pollTickSchedulesDespiteDismissRetryThrow`) already proves the same C5-01/CX-G-05 invariant
   and can stay as-is.
5. Re-run `./scripts/build-and-test.sh` and confirm `PASSED (passed=N, failed=0, errors=0)`.

## Cross-repo note

The paired `faBolus` repo's own `dev/garmin-hr-relay` branch carries the PHONE half of this same
relay: the `hr_window` parse + `GarminRemoteBridge.newestHeartRate()` +
`AppModel.ingestGarminHeartRate`/`latestGarminHeartRate`/`onWantHeartRate`/`setWantHeartRate`/
`reconcileHeartRateWanted` + the `AppSettings.heartRateContextEnabled` setting + the
`RefreshEffectsCoordinator.onReconcileHeartRateWanted` ordered step. **Both halves must be
reintegrated together** — this watch-side branch alone sends `hr_window` into a void (no
phone-side parser exists on a tree that restores only this half), and the phone-side branch alone
has a `heartRateContextEnabled` setting that pushes a `hr_ctl` toggle no watch build would ever
receive.

Additionally, `dev/graph-detail` (the faBolus repo's HR DISPLAY half — a DIFFERENT, EARLIER
removal) already documents that its preserved `GraphDetailView` VIEW PARAMS assume
`latestGarminHeartRate`/`heartRateContextEnabled` exist on the target tree (D-06a). Reintegrate
this relay pair (faBolusGarmin `dev/garmin-hr-relay` + faBolus `dev/garmin-hr-relay`) BEFORE
`dev/graph-detail` — `dev/graph-detail`'s view params are inert without the relay actually
populating `latestGarminHeartRate`.

This branch does not touch faBolus's dose/signed core (it is a separate repo entirely, consumed
read-only by faBolus per the cross-repo lockstep described in `BRANCHES.md`), so no dose-set
stub/frozen-wire-field un-stub is applicable to this reintegration.
