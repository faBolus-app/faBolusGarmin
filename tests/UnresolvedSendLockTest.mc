using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// THE UNRESOLVED-SEND DISCLOSURE behind a durable unresolved-send tombstone.
//
// A durable tombstone records that a prior dispatch's outcome is unconfirmed. The watch mirrors the
// phone: it DISCLOSES that state (non-blocking) rather than walling off a new dose. canBolus() and
// reattemptBlocked() do NOT consult the tombstone, so the Bolus button stays usable; the unresolved
// state is surfaced by unresolvedDisclosureMarker() plus the read-only unresolvedSendDisclosure detail.
// This deliberately weakens a wrist double-dose guard — the residual re-dose-into-unknown risk is
// accepted because the pump is the primary annunciator and owns the authoritative history/IOB.
//
// This suite pins the three properties, all on pure AppState decisions:
//   1. DISCLOSURE, NOT A WALL — canBolus() ignores the tombstone (the button stays usable) and the send
//                              gate does not refuse for it; unresolvedDisclosureMarker() names the state.
//   2. THE MARKER IS BOUNDED  — the tombstone perturbs neither the eligibility generation nor the
//                              cancel path, so it cannot tear down an armed confirm or block a cancel.
//   3. RELEASE IS AUTHORITATIVE AND NEVER AUTOMATIC — the tombstone clears only by a requestId-matched
//                              authoritative echo (preferred: resolves the DOSE) or by the phone
//                              reporting a human reconciliation (resolves the marker only). Nothing
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

    // --- 1. disclosure, not a wall -----------------------------------------------------------------

    // THE CORE OF THE DOWNGRADE: same state, tombstone the only difference — and the button STAYS usable.
    (:test)
    function tombstoneDoesNotLockTheBolusAffordance(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        Test.assertMessage(AppState.canBolus(), "baseline: a bolus is possible");
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertMessage(AppState.canBolus(),
            "an unresolved prior send must NOT disable the button — the watch discloses, it does not wall off");
        // ...and the send gate agrees: a bare durable tombstone yields no refusal (only an in-flight
        // outcome would), so the affordance and the gate tell the SAME story.
        Test.assertMessage(AppState.bolusSendRefusal() == null,
            "the send gate does not refuse for a bare durable tombstone");
        tidy();
        return true;
    }

    (:test)
    function unresolvedDoseIsNamedByTheMarker(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        Test.assertEqualMessage(AppState.unresolvedDisclosureMarker(), "",
            "baseline: nothing unresolved, empty marker");
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");
        Test.assertEqualMessage(AppState.unresolvedDisclosureMarker(), "Earlier dose unresolved",
            "the unresolved dose is NAMED by the non-blocking marker");
        // ...and it does NOT masquerade as a block reason: the button is usable, so no block label.
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "",
            "the marker is not a block label — the button stays enabled");
        tidy();
        return true;
    }

    // The non-blocking marker is INDEPENDENT of the transient block reasons: it discloses the unresolved
    // dose no matter what else is (or is not) blocking, while bolusBlockLabel() reports the ACTUAL
    // disabling reason (the tombstone is no longer one). The two carry different information.
    (:test)
    function markerDisclosesIndependentOfTransientBlocks(logger as Test.Logger) as Lang.Boolean {
        bolusPossible();
        AppState.persistUnresolvedTombstone(REQ, Time.now().value(), "units:1.00");

        RemoteComm.testPhoneReachable = false;          // a real, transient block
        Test.assertEqualMessage(AppState.unresolvedDisclosureMarker(), "Earlier dose unresolved",
            "the marker still discloses the unresolved dose");
        Test.assertEqualMessage(AppState.bolusBlockLabel(), "Phone not connected",
            "...while the block label names the ACTUAL disabling reason, not the tombstone");

        RemoteComm.testPhoneReachable = true;
        AppState.hostCanBolus = false;                  // a different transient block
        Test.assertEqualMessage(AppState.unresolvedDisclosureMarker(), "Earlier dose unresolved",
            "the marker is unaffected by a pump-side block");
        tidy();
        return true;
    }

    // --- 2. the marker is bounded -----------------------------------------------------------------

    // The single most important safety property: the tombstone is NOT an input to eligibilityFingerprint()
    // (which reads pumpBolusAllowed() directly) and never was, so it cannot bump bolusEligibilityGen and
    // cannot spuriously tear down an already-armed confirm mid-flow.
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
        Test.assertMessage(AppState.canCancel(),
            "cancelling the in-flight one is allowed — cancel is never gated by the tombstone");
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

    // The wearer reaches this copy as the non-blocking disclosure shown at bolus-entry open while a prior
    // dispatch is unresolved. It is the honest explanation behind the "Earlier dose unresolved" marker, so
    // it must exist, must fit, and must not lie in EITHER direction.
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
