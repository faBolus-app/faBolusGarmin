using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// THE PERMANENT, UNDISCLOSED BOLUS LOCKOUT behind a durable unresolved-send tombstone.
//
// A tombstone has always made every send fail at sendBolusNow's reattemptBlocked() guard. But
// canBolus() did not consult it, so the affordance LIED: a fully enabled indigo Bolus button that
// opened entry, let the wearer compose a dose and tap 1-2-3, and then refused at the send — silently,
// permanently, and across reboots, because clearUnresolvedTombstone() had exactly one production caller
// (a matching authoritative echo) and no user-reachable path at all.
//
// This suite pins the three properties of the fix, all on pure AppState decisions:
//   1. LOCKOUT IS HONEST     — canBolus() reflects the tombstone, and bolusBlockLabel() names it, ahead
//                              of the transient reasons that would otherwise mask it.
//   2. LOCKOUT IS BOUNDED    — adding that term perturbs neither the eligibility generation nor the
//                              cancel path, so it cannot tear down an armed confirm or block a cancel.
//   3. RELEASE IS AUTHORITATIVE AND NEVER AUTOMATIC — the lock is released only by a requestId-matched
//                              authoritative echo (preferred: resolves the DOSE) or by the phone
//                              reporting a human reconciliation (resolves the LOCK only). Nothing
//                              auto-clears, and a manual release does not lock out a later real echo.
//
// Pinned on pure AppState functions, matching tests/CanBolusTest.mc / tests/HoldTeardownTest.mc /
// tests/SendRefusalDisclosureTest.mc: the views (UnresolvedSendView/Delegate) reach Ui and are not
// deterministically drivable from the unit harness, so the safety-critical DECISIONS and the COPY are
// what get asserted — not the pixels.
module UnresolvedSendLockTest {

    const REQ = "req-unresolved-1";

    function bolusStatusMsg(reqId as Lang.String, status as Lang.String) as Lang.Dictionary {
        return { "kind" => "bolusStatus", "requestId" => reqId, "status" => status };
    }

    function lockResolvedMsg(reqId as Lang.String) as Lang.Dictionary {
        return { "kind" => "bolusLockResolved", "requestId" => reqId };
    }

    // A state in which a bolus IS possible: every canBolus() term satisfied and no tombstone. Set
    // explicitly so cases are order-independent regardless of what other test modules left behind.
    // Reachability comes from the documented RemoteComm.testPhoneReachable seam so canBolus() is
    // deterministic here rather than guarded on the simulator's absent phone.
    function bolusPossible() as Void {
        RemoteComm.testPhoneReachable = true;
        AppState.garminBolusEnabled = true;
        AppState.readOnly = false;
        AppState.hostCanBolus = true;
        AppState.hostBolusBlockReason = null;
        AppState.connection = "Connected";
        AppState.lastReplyEpoch = Time.now().value();
        AppState.lastBolus = -1.0;
        AppState.bolusPasscodeRequired = false;
        AppState.armedAtEpoch = Time.now().value();
        AppState.bolusEligibilityGen = 0;
        AppState.armedEligibilityGen = 0;
        AppState._prevEligibilityFp = null;
        AppState.clearInFlight();
        AppState.clearUnresolvedTombstone();
        AppState.clearLockResolvedRecordForTest();
    }

    function tidy() as Void {
        RemoteComm.testPhoneReachable = null;
        AppState.clearInFlight();
        AppState.clearUnresolvedTombstone();
        AppState.clearLockResolvedRecordForTest();
    }

    // --- 1. the lockout is honest ------------------------------------------------------------------

    // THE REGRESSION TEST for the lying button: same state, tombstone the only difference.
    (:test)
    function tombstoneLocksTheBolusAffordance(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        Test.assertMessage(AppState.canBolus(), "baseline: a bolus is possible");
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertMessage(!AppState.canBolus(),
            "an unresolved prior send ⇒ canBolus() false (the button stops looking enabled)");
        // ...and the send gate agrees, so the affordance and the gate now tell the SAME story.
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "unresolvedPriorSend",
            "the send gate refuses on the same condition the button now reflects");
        tidy();
        return true;
    }

    (:test)
    function lockoutIsNamedOnTheButton(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "", "baseline: no block, empty label");
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "Earlier dose unresolved",
            "the lockout is NAMED, never a silent grey button");
        tidy();
        return true;
    }

    // ORDERING. The tombstone branch must sit ahead of every transient reason: it is the only block that
    // never clears on its own, and the disclosure surface is opened only when the label reports it — so a
    // masked reason would make the explanation unreachable and restore the original silence.
    (:test)
    function lockDisclosureBeatsTransientReasons(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");

        RemoteComm.testPhoneReachable = false;          // would otherwise be "Phone not connected"
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "Earlier dose unresolved",
            "the permanent reason wins over an unreachable phone");

        RemoteComm.testPhoneReachable = true;
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "Earlier dose unresolved",
            "...and over 'Reconnecting…', which would have the wearer wait forever");

        AppState.lastReplyEpoch = Time.now().value();
        AppState.hostCanBolus = false;                  // would otherwise be a pump reason
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "Earlier dose unresolved",
            "...and over a pump-side reason");
        tidy();
        return true;
    }

    // --- 2. the lockout is bounded ----------------------------------------------------------------

    // The single most important safety property of this change: canBolus() is NOT an input to
    // eligibilityFingerprint() (which reads pumpBolusAllowed() directly), so the new term cannot bump
    // bolusEligibilityGen and cannot spuriously tear down an already-armed confirm mid-flow.
    (:test)
    function lockDoesNotPerturbTheEligibilityGeneration(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        var before = AppState.eligibilityFingerprint();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertEqualMessage(AppState.eligibilityFingerprint(), before,
            "the tombstone must NOT change the eligibility fingerprint");
        AppState.armBolus();
        Test.assertMessage(!AppState.mustTeardownArmedBolus(),
            "and must NOT trigger an armed-confirm teardown");
        tidy();
        return true;
    }

    // Cancelling an in-flight bolus is a SAFETY action and must never be blocked by a tombstone from an
    // EARLIER dose. canCancel() is deliberately independent of canBolus().
    (:test)
    function lockNeverBlocksCancellingAnInFlightBolus(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        AppState.connection = "Delivering…";   // bolusing() matches a "Deliver" prefix
        AppState.pendingRequestId = "req-in-flight-9";
        Test.assertMessage(AppState.bolusing(), "a bolus is in flight");
        Test.assertMessage(!AppState.canBolus(), "starting a NEW bolus is locked");
        Test.assertMessage(AppState.canCancel(), "but cancelling the in-flight one is still allowed");
        tidy();
        return true;
    }

    // --- 3. release is authoritative, and never automatic ------------------------------------------

    // NOTHING may clear the lock as a side effect. reset() runs on every bolus-entry open and
    // clearInFlight() on every back-out, so if either cleared the tombstone the durable guard would be
    // trivially defeated by navigating.
    (:test)
    function nothingAutoClearsTheLock(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");

        AppState.reset();
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "reset() must NOT clear the lock");
        AppState.clearInFlight();
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "clearInFlight() must NOT clear the lock");
        AppState.armBolus();
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "armBolus() must NOT clear the lock");

        // A NON-terminal and an INDETERMINATE echo must both leave it locked — "unknown" is precisely the
        // ambiguous outcome the tombstone exists to protect.
        AppState.handle(bolusStatusMsg(REQ, "delivering"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "a non-terminal echo must NOT clear the lock");
        AppState.handle(bolusStatusMsg(REQ, "unknown"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "an 'unknown' echo must NOT clear the lock");
        tidy();
        return true;
    }

    // Path 1, the PREFERRED release: an authoritatively-resolved echo for the matching requestId.
    (:test)
    function authoritativeEchoReleasesTheLock(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        AppState.handle(bolusStatusMsg("req-someone-else", "delivered"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "a MISMATCHED id must not release it");
        AppState.handle(bolusStatusMsg(REQ, "delivered"));
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "a matching authoritative echo releases it");
        Test.assertMessage(!AppState.lockWasManuallyResolved(),
            "and it is NOT recorded as a human reconciliation — the dose itself was resolved");
        tidy();
        return true;
    }

    // Path 2: the phone reporting that a human reconciled this dispatch against the pump's own history.
    // requestId-matched, so it can never blanket-unlock a DIFFERENT unresolved dispatch.
    (:test)
    function phoneReportedReconciliationReleasesOnlyTheMatchingLock(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");

        Test.assertMessage(!AppState.resolveUnresolvedSendLock("req-wrong"),
            "a mismatched requestId must be refused");
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "...and must leave the lock in place");

        Test.assertMessage(AppState.resolveUnresolvedSendLock(REQ), "the matching requestId is accepted");
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "...and releases the lock");
        Test.assertMessage(AppState.canBolus(), "so a bolus becomes possible again");
        tidy();
        return true;
    }

    (:test)
    function resolvingWhenNothingIsLockedIsANoOp(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "nothing is locked");
        Test.assertMessage(!AppState.resolveUnresolvedSendLock(REQ), "a resolve is refused, not applied");
        Test.assertMessage(!AppState.lockWasManuallyResolved(), "and records nothing");
        tidy();
        return true;
    }

    // An unexplained silent unlock is its own hazard: a human-reconciled release must leave an audit
    // trail, and must NOT forget the requestId it released — which is what lets a later real echo for
    // that same dispatch still be recognised (path 1 supersedes path 2, not the reverse).
    (:test)
    function humanReleaseLeavesAnAuditTrailAndKeepsTheRequestId(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertMessage(AppState.resolveUnresolvedSendLock(REQ), "released");

        Test.assertMessage(AppState.lockWasManuallyResolved(),
            "the release is visible as a human reconciliation, not a confirmed outcome");
        Test.assertEqualMessage(AppState.lockResolvedReqId, REQ,
            "the resolved requestId is REMEMBERED, so a later real echo is still recognisable");
        Test.assertMessage(AppState.lockResolvedAtEpoch > 0, "and stamped with when it happened");
        tidy();
        return true;
    }

    // The inbound message form of path 2, through the real handle() dispatch. A missing/malformed id is a
    // safe no-op rather than a blanket unlock.
    (:test)
    function bolusLockResolvedMessageIsGuarded(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");

        AppState.handle({ "kind" => "bolusLockResolved" });                  // no requestId at all
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "no requestId ⇒ safe no-op");
        AppState.handle({ "kind" => "bolusLockResolved", "requestId" => 42 });  // non-String
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "non-String requestId ⇒ safe no-op");
        AppState.handle(lockResolvedMsg("req-wrong"));
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "mismatched requestId ⇒ safe no-op");

        AppState.handle(lockResolvedMsg(REQ));
        Test.assertMessage(!AppState.hasUnresolvedTombstone(), "the matching id releases the lock");
        tidy();
        return true;
    }

    // --- 4. the disclosure copy: present, sized, and honest ----------------------------------------

    // The wearer reaches this copy by tapping the locked button. It is the ONLY thing between them and an
    // unexplained permanent lockout, so it must exist, must fit, and must not lie in EITHER direction.
    (:test)
    function disclosureIsPresentAndFits(logger as Test.Logger) as Lang.Boolean {
        var lines = AppState.unresolvedSendDisclosure();
        Test.assertMessage(lines.size() > 0, "there is a disclosure to draw");
        for (var i = 0; i < lines.size(); i += 1) {
            var line = lines[i] as Lang.String;
            Test.assertMessage(line.length() > 0, "no blank disclosure line");
            Test.assertMessage(line.length() <= AppState.UNRESOLVED_LINE_MAX_CHARS,
                "disclosure line fits the FONT_XTINY row budget — " + line);
        }
        return true;
    }

    // The honesty contract. The outcome of the earlier dose is genuinely UNKNOWN: claiming it WAS
    // delivered invites a missed dose, claiming it was NOT invites a double dose. So the copy may claim
    // neither, and must send the wearer to the pump's own history — the only authority on this question.
    (:test)
    function disclosureClaimsNeitherDeliveredNorNotDelivered(logger as Test.Logger) as Lang.Boolean {
        var lines = AppState.unresolvedSendDisclosure();
        var all = "";
        for (var i = 0; i < lines.size(); i += 1) {
            all = all + " " + (lines[i] as Lang.String).toLower();
        }
        // "deliver" catches delivered/delivering/delivery in either direction at once.
        Test.assertMessage(all.find("deliver") == null,
            "the disclosure must not claim the dose was — or was not — delivered: " + all);
        Test.assertMessage(all.find("no insulin") == null, "must not claim no insulin was given");
        Test.assertMessage(all.find("pump") != null, "must point the wearer at the pump's own history");
        Test.assertMessage(all.find("cannot") != null || all.find("not know") != null,
            "must state plainly that faBolus does not know the outcome");
        return true;
    }
}
