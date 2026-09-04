using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;
using Toybox.Application.Storage;

// Wrist half: `pendingRequestId` (AppState.mc) is in-memory only and lost on a nav/restart/
// kill, so a cold relaunch could re-arm/re-send a dose whose phone-side outcome is still genuinely
// unknown — the wrist side of the settled-echo-loss double-dose window (the phone has its own guard).
// The fix is a DURABLE tombstone {requestId, sentAt, doseKey} in Connect IQ
// Application.Storage, written ONLY once dispatch to the phone might have occurred (dispatched==true),
// consulted by reattemptBlocked() (so a fresh sendBolusNow after a relaunch is refused while unresolved),
// and cleared only by an authoritative terminal echo (delivered/cancelled/failed) for the matching
// requestId.
//
// A REFUTED alternative: arming the tombstone at pendingRequestId-set time, BEFORE the
// phoneReachable() check, would survive a synchronously-failed dispatch — nothing ever
// reached the phone, so no phone echo can ever arrive, and a durable tombstone there is an unrecoverable
// PERMANENT lock. The fix gates the write on `dispatched==true` via a small extracted seam
// (maybeWriteUnresolvedTombstone) specifically so this gate is unit-testable — `RemoteComm.sendBolus`'s
// own true/false outcome depends on `System.getDeviceSettings().phoneConnected`, which is NOT
// sim-controllable in this environment (same limitation documented in tests/CanBolusTest.mc /
// tests/AppLivenessTest.mc). "Simulating a relaunch" here means clearing AppState's in-memory fields and
// calling loadPrefs() again — AppState is a module-level singleton (no per-instance state to reconstruct),
// so this is the exact same code path FaBolusApp.onStart() drives on a real cold launch.
module UnresolvedDeliveryTombstoneTest {

    function bolusStatusMsg(reqId as Lang.String, status as Lang.String) as Lang.Dictionary {
        return { "kind" => "bolusStatus", "requestId" => reqId, "status" => status };
    }

    // Reset every field the tombstone mechanics touch (in-memory + Storage) so cases are
    // order-independent regardless of prior tests / a prior simulator session.
    function baseline() as Void {
        // Reset the test-only reachability override to real behavior at the start of EVERY case, so a
        // value one case forces (below) never leaks into the next (or, since this module runs last, into
        // another test file). Only outOfRangeAttemptLeavesNoTombstone opts into forcing it.
        RemoteComm.testPhoneReachable = null;
        AppState.status = null;
        AppState.message = null;
        AppState.pendingRequestId = null;
        AppState.sawPhoneBolusing = false;
        AppState.outcomeSentEpoch = 0;
        AppState.mode = "units";
        AppState.deliverUnits = 1.0;
        AppState.carbsValue = 0;
        AppState.bolusEligibilityGen = 0;
        AppState.armedEligibilityGen = 0;
        AppState._prevEligibilityFp = null;
        AppState.readOnly = false;
        AppState.garminBolusEnabled = true;
        AppState.hostCanBolus = true;          // phone-authoritative allow
        AppState.hostBolusBlockReason = null;
        AppState.bolusPasscodeRequired = false;
        AppState.connection = "Connected";
        AppState.lastBolus = -1.0;
        // sendBolusNow also carries liveness / elapsed-time-since-arm re-checks — keep this baseline
        // forward-compatible (fresh liveness, in-window arm) so these cases, none of which are about
        // liveness, keep their original pass/fail shape.
        AppState.lastReplyEpoch = Time.now().value();
        simulateRelaunch();   // clears in-memory tombstone fields + wipes any persisted leftover
    }

    // "Cold relaunch": clear the in-memory tombstone mirror (and any OTHER in-memory fields a real
    // process restart would lose) WITHOUT touching Storage, then call loadPrefs() — the exact call
    // FaBolusApp.onStart() makes — to reload whatever (if anything) is durably persisted.
    function simulateRelaunch() as Void {
        AppState.unresolvedTombstoneReqId = null;
        AppState.pendingRequestId = null;
        AppState.status = null;
    }

    // Fully wipe any persisted tombstone (used to leave Storage clean for OTHER test files).
    function wipeStorage() as Void {
        Storage.deleteValue(AppState.KEY_UNRESOLVED_TOMBSTONE);
    }

    // --- codex HIGH: no permanent lock on a provably-unsent request -------------------------------

    // The `!phoneReachable()` outOfRange path sends NOTHING — sendBolusNow must leave no durable
    // tombstone. Reachability is environment-specific (the venu3s simulator reports the phone CONNECTED by
    // default, unlike the sims tests/CanBolusTest.mc / tests/AppLivenessTest.mc were written against), so we
    // force it unreachable through RemoteComm.testPhoneReachable — the test-only seam that mirrors
    // testSuppressTransmit — to drive the REAL sendBolusNow code path deterministically (not just the
    // extracted maybeWriteUnresolvedTombstone seam). baseline() resets the override afterward.
    (:test)
    function outOfRangeAttemptLeavesNoTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        RemoteComm.testPhoneReachable = false;   // force the outOfRange path regardless of the sim default
        Test.assertMessage(!RemoteComm.phoneReachable(), "seam forces the phone unreachable");
        var sent = AppState.sendBolusNow(null);
        Test.assertMessage(sent, "sendBolusNow still returns true (outOfRange is a completed outcome)");
        Test.assertEqualMessage(AppState.status, "outOfRange", "status settled to outOfRange");
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "no durable tombstone after outOfRange");
        Test.assertMessage(Storage.getValue(AppState.KEY_UNRESOLVED_TOMBSTONE) == null,
            "nothing persisted to Storage either");
        // A relaunch after this must permit a fresh send — nothing to unblock, since nothing was ever
        // written.
        simulateRelaunch();
        AppState.loadPrefs();
        Test.assertMessage(!AppState.reattemptBlocked(), "relaunch after outOfRange never blocks a fresh send");
        RemoteComm.testPhoneReachable = null;   // restore real reachability for subsequent cases/files
        return true;
    }

    // The extracted seam directly: dispatched==false must never persist a tombstone, even though this
    // exact branch (a synchronous Comm.transmit failure AFTER phoneReachable() already returned true)
    // isn't reachable through the full sendBolusNow() path in this sandboxed sim (phoneReachable() is
    // unconditionally false here, so sendBolusNow's OWN earlier guard always wins first — see the case
    // above). This is the direct codex-HIGH assertion: "a provably-unsent request never locks the wrist."
    (:test)
    function dispatchedFalseSeamWritesNoTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(false, "req-would-be-failed", Time.now().value(), "units:1.00");
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "dispatched==false ⇒ no in-memory tombstone");
        Test.assertMessage(Storage.getValue(AppState.KEY_UNRESOLVED_TOMBSTONE) == null,
            "dispatched==false ⇒ nothing persisted");
        return true;
    }

    // The positive companion: dispatched==true DOES persist, via the same seam.
    (:test)
    function dispatchedTrueSeamWritesTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        var sentAt = Time.now().value();
        AppState.maybeWriteUnresolvedTombstone(true, "req-dispatched-1", sentAt, "units:1.00");
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "dispatched==true ⇒ in-memory tombstone set");
        Test.assertEqualMessage(AppState.unresolvedTombstoneReqId, "req-dispatched-1", "requestId recorded");
        var persisted = Storage.getValue(AppState.KEY_UNRESOLVED_TOMBSTONE);
        Test.assertMessage(persisted instanceof Lang.Dictionary, "persisted to Storage as a dictionary");
        var persistedDict = persisted as Lang.Dictionary;
        Test.assertEqualMessage(persistedDict["requestId"], "req-dispatched-1", "persisted requestId matches");
        wipeStorage();
        return true;
    }

    // --- survives a simulated relaunch + blocks a re-arm/re-send -----------------------------------

    (:test)
    function dispatchedTombstoneSurvivesRelaunchAndBlocksResend(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-relaunch-1", Time.now().value(), "units:1.00");
        Test.assertMessage(AppState.reattemptBlocked(), "a live tombstone blocks reattemptBlocked() pre-relaunch");

        // Simulate a cold relaunch: wipe every in-memory field a real process restart would lose, then
        // call loadPrefs() — the exact call FaBolusApp.onStart() makes.
        simulateRelaunch();
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "in-memory tombstone cleared by the relaunch sim");
        AppState.loadPrefs();
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "loadPrefs() restores the durable tombstone");
        Test.assertEqualMessage(AppState.unresolvedTombstoneReqId, "req-relaunch-1", "restored requestId matches");

        // A fresh send attempt (as if the wearer tried to re-arm/re-send after the relaunch) must be
        // refused before minting a new requestId.
        Test.assertMessage(AppState.reattemptBlocked(), "restored tombstone still blocks reattemptBlocked() post-relaunch");
        var priorPending = AppState.pendingRequestId;
        var sent = AppState.sendBolusNow(null);
        Test.assertMessage(!sent, "sendBolusNow refuses while an unresolved tombstone survives the relaunch");
        // Both are null here (pendingRequestId is deliberately not restored across a relaunch, and the
        // tombstone guard refuses the send before any new reqId is minted). Assert equality with `==`
        // rather than Test.assertEqualMessage, whose SDK impl invokes a method on the operands and throws
        // an "Unexpected Type Error: Failed invoking <symbol>" when they are null.
        Test.assertMessage(AppState.pendingRequestId == priorPending, "no new requestId minted");
        wipeStorage();
        return true;
    }

    // --- authoritative terminal echo clears it; a subsequent dose is allowed -----------------------

    (:test)
    function terminalEchoClearsTombstoneAndAllowsNextDose(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-terminal-1", Time.now().value(), "units:1.00");
        simulateRelaunch();
        AppState.loadPrefs();
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "restored before the echo lands");

        // The authoritative echo arrives for the SAME requestId. Note pendingRequestId is NOT restored
        // by loadPrefs() (only the durable tombstone is) — the clear must not depend on it.
        Test.assertMessage(AppState.pendingRequestId == null, "pendingRequestId stays null post-relaunch (unrestored)");
        AppState.handle(bolusStatusMsg("req-terminal-1", "delivered"));
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "an authoritative terminal echo clears the tombstone");
        Test.assertMessage(Storage.getValue(AppState.KEY_UNRESOLVED_TOMBSTONE) == null,
            "cleared from Storage too");
        Test.assertMessage(!AppState.reattemptBlocked(), "a subsequent dose is allowed once cleared");
        return true;
    }

    // A cancel-terminal echo (cancelled) is equally authoritative and clears it.
    (:test)
    function cancelledEchoAlsoClearsTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-terminal-2", Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-terminal-2", "cancelled"));
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "cancelled echo clears the tombstone too");
        return true;
    }

    // A failed-terminal echo also clears it.
    (:test)
    function failedEchoAlsoClearsTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-terminal-3", Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-terminal-3", "failed"));
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "failed echo clears the tombstone too");
        return true;
    }

    // --- a non-terminal / late / out-of-band message does NOT clear it -----------------------------

    // A non-terminal echo (delivering/cancelling) for the SAME requestId must not clear it — the outcome
    // is still unknown.
    (:test)
    function nonTerminalEchoDoesNotClearTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-nonterm-1", Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-nonterm-1", "delivering"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "a non-terminal echo leaves the tombstone in place");
        return true;
    }

    // Regression: an "unknown" echo (the outcome watchdog's honest timeout / the phone's
    // indeterminate) for the SAME requestId must NOT clear the tombstone either — it is the
    // ambiguous-outcome case the tombstone exists to protect. Before this fix, the clear site reused
    // isTerminalStatus() (which treats "unknown" as terminal), so this echo would have wrongly cleared
    // the tombstone and unblocked a re-send while the real outcome was still unresolved.
    (:test)
    function unknownEchoDoesNotClearTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-unknown-1", Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-unknown-1", "unknown"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "an 'unknown' echo leaves the tombstone in place");
        Test.assertMessage(AppState.reattemptBlocked(), "a re-send is still blocked after an 'unknown' echo");
        return true;
    }

    // A terminal echo for a DIFFERENT (unrelated) requestId — out-of-band / stale — must not clear it.
    (:test)
    function unrelatedRequestIdEchoDoesNotClearTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-mine-1", Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-someone-elses", "delivered"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "an unrelated requestId's terminal echo is ignored");
        Test.assertEqualMessage(AppState.unresolvedTombstoneReqId, "req-mine-1", "the original tombstone is untouched");
        return true;
    }

    // A statusRead (not a bolusStatus at all) must never clear it either.
    (:test)
    function statusReadNeverClearsTombstone(logger as Test.Logger) as Lang.Boolean {
        baseline();
        wipeStorage();
        AppState.maybeWriteUnresolvedTombstone(true, "req-status-1", Time.now().value(), "units:1.00");
        AppState.handle({ "kind" => "statusRead", "message" => "Connected" });
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "an unrelated statusRead never clears the tombstone");
        return true;
    }
}
