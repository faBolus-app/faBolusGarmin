using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;
using Toybox.Application.Storage;

// The authenticated dismiss-ack watch side — the two-lane durable state (AppState.dismissPending /
// .dismissProvisional), the `dismissAck` handle() branch (AppState.handleDismissAck), the
// relaunch-safe capability persistence/parse-order (supportsDismissAck), and the capability-gated
// cutover from the filtered-statusRead fallback (reconcileDismissSent, still tested in
// AlertHelpersTest.mc). AppState/FaBolusApp are compiled into the test binary (test.jungle). Style
// mirrors tests/UnresolvedDeliveryTombstoneTest.mc (Storage-backed durability, "simulate a relaunch"
// via loadPrefs()) and tests/AlertHelpersTest.mc (direct AppState.handle() driving).
module DismissAckTest {

    function alertDict(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    // A statusRead reply carrying an explicit `alerts` array (possibly empty/omitting an identity —
    // the "filtered snapshot" every test here drives) and, when non-null, the supportsDismissAck flag.
    function statusReadMsg(alertsArr as Lang.Array, supportsAck as Lang.Boolean?) as Lang.Dictionary {
        var d = { "kind" => "statusRead", "alerts" => alertsArr };
        if (supportsAck != null) { d["supportsDismissAck"] = supportsAck; }
        return d;
    }

    function dismissAckMsg(rid, aid, akind) as Lang.Dictionary {
        return { "kind" => "dismissAck", "requestId" => rid, "alertId" => aid, "alertKind" => akind };
    }

    // Wipe every persisted key this mechanism touches, so cases are order-independent regardless of
    // prior tests / a prior simulator session (mirrors UnresolvedDeliveryTombstoneTest.wipeStorage).
    function wipeDismissStorage() as Void {
        Storage.deleteValue(AppState.KEY_DISMISS_PENDING);
        Storage.deleteValue(AppState.KEY_DISMISS_PROVISIONAL);
        Storage.deleteValue(AppState.KEY_SUPPORTS_DISMISS_ACK);
        Storage.deleteValue(AppState.KEY_SEEN_ALERTS);
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.dismissPending = {};
        AppState.dismissProvisional = {};
        AppState.supportsDismissAck = false;
        AppState.dismissSentAlertIdentities = [];
        AppState.readOnly = false;
        wipeDismissStorage();
    }

    // "Cold relaunch": clear the in-memory dismiss-state mirror (a real process restart would lose it)
    // WITHOUT touching Storage, then call loadPrefs() — the exact call FaBolusApp.onStart() makes.
    function simulateRelaunch() as Void {
        AppState.dismissPending = {};
        AppState.dismissProvisional = {};
        AppState.supportsDismissAck = false;
        AppState.loadPrefs();
    }

    // === Correlated authenticated ack (capability present) ======================================

    (:test)
    function correlatedAckRemovesMatchingAlertAndClearsBothLanes(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        Test.assertMessage(AppState.dismissPending.hasKey("1-5"), "retry entry retained after beginDismiss");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"), "provisional entry retained after beginDismiss");

        AppState.handle(dismissAckMsg(reqId, 5, 1));

        Test.assertEqualMessage(AppState.alerts.size(), 0, "the correlated ack removed exactly that alert");
        Test.assertMessage(!AppState.dismissPending.hasKey("1-5"), "retry entry cleared on ack");
        Test.assertMessage(!AppState.dismissProvisional.hasKey("1-5"), "provisional entry cleared on ack");
        return true;
    }

    // A correlated ack removes ONLY the matching alert, leaving a sibling untouched.
    (:test)
    function correlatedAckLeavesSiblingAlertsUntouched(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off"), alertDict(9, 2, "Low insulin") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "only the acked alert is removed");
        var kept = AppState.alerts[0] as Lang.Dictionary;
        Test.assertMessage(kept["id"] == 9 && kept["kind"] == 2, "the sibling alert survives");
        return true;
    }

    // === NEGATIVE paths ===========================================================================

    (:test)
    function noAckLeavesAlertStaying(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        // No dismissAck ever arrives — the alert stays exactly as-is.
        Test.assertEqualMessage(AppState.alerts.size(), 1, "no ack ⇒ the alert stays");
        return true;
    }

    (:test)
    function mismatchedRequestIdRemovesNothing(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.handle(dismissAckMsg("totally-wrong-reqid", 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "a mismatched requestId removes nothing");
        return true;
    }

    (:test)
    function matchedRequestIdButMismatchedIdentityRemovesNothing(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        // The SAME requestId, but a DIFFERENT (alertId, alertKind) — must not resolve to the entry that
        // actually owns this requestId (the identity-keyed lookup naturally refuses this).
        AppState.handle(dismissAckMsg(reqId, 5, 2));   // wrong kind
        Test.assertEqualMessage(AppState.alerts.size(), 1, "matched reqId but mismatched identity removes nothing");
        AppState.handle(dismissAckMsg(reqId, 9, 1));   // wrong id
        Test.assertEqualMessage(AppState.alerts.size(), 1, "matched reqId but mismatched id removes nothing");
        return true;
    }

    (:test)
    function malformedAckIsASafeNoOp(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        // Missing alertId/alertKind, non-String requestId, non-Number alertId/alertKind — none of these
        // may trap or remove anything.
        AppState.handle({ "kind" => "dismissAck", "requestId" => reqId });
        AppState.handle({ "kind" => "dismissAck", "requestId" => 12345, "alertId" => 5, "alertKind" => 1 });
        AppState.handle({ "kind" => "dismissAck", "requestId" => reqId, "alertId" => "five", "alertKind" => 1 });
        AppState.handle({ "kind" => "dismissAck", "requestId" => reqId, "alertId" => 5, "alertKind" => "one" });
        Test.assertEqualMessage(AppState.alerts.size(), 1, "every malformed ack safely no-ops");
        return true;
    }

    // === H1 (relaunch-in-ack-mode, MUST-FIX regression) ==========================================

    // After persisting a pending+provisional AND supportsDismissAck=true, a simulated relaunch
    // restores the overlay AND the capability; the FIRST post-relaunch filtered statusRead (omits the
    // identity, carries supportsDismissAck=true) does NOT remove the alert — the capability is restored
    // (last-known true) AND re-parsed from THIS message BEFORE the alerts-replace, so the
    // filtered-reconcile fallback removal never fires. This is the exact regression test for the
    // relaunch fail-open.
    (:test)
    function h1RelaunchInAckModeSurvivesFirstFilteredStatusRead(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsDismissAck = true;
        Storage.setValue(AppState.KEY_SUPPORTS_DISMISS_ACK, true);

        simulateRelaunch();
        Test.assertMessage(AppState.supportsDismissAck, "loadPrefs restores the persisted capability (true)");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"), "loadPrefs restores the display provisional");
        Test.assertMessage(AppState.dismissPending.hasKey("1-5"), "loadPrefs restores the retry entry");

        // The FIRST post-relaunch statusRead: a FILTERED snapshot (empty — the identity is omitted,
        // exactly like a t:slim local-snooze or any absence) that ALSO carries supportsDismissAck=true.
        AppState.handle(statusReadMsg([], true));

        Test.assertEqualMessage(AppState.alerts.size(), 1, "the overlaid alert survives the first post-relaunch filtered statusRead");
        return true;
    }

    // === Durable overlay across relaunch (HIGH-B) ================================================

    (:test)
    function durableOverlaySurvivesRelaunchAndRepeatedFilteredStatusReads(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsDismissAck = true;
        Storage.setValue(AppState.KEY_SUPPORTS_DISMISS_ACK, true);
        simulateRelaunch();

        // Multiple subsequent filtered statusReads, all omitting the identity, must not drop it.
        AppState.handle(statusReadMsg([], true));
        AppState.handle(statusReadMsg([], true));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "repeated filtered statusReads never drop the overlay");

        // Only an authenticated dismissAck removes it.
        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 0, "the authenticated ack finally removes it");
        return true;
    }

    // L1: the overlaid identity is force-marked 'seen' so re-overlaying it never re-notifies/vibrates.
    (:test)
    function overlaidProvisionalIsForceMarkedSeen(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsDismissAck = true;
        Storage.setValue(AppState.KEY_SUPPORTS_DISMISS_ACK, true);
        simulateRelaunch();

        Test.assertMessage(!AppState.containsStr(AppState.loadSeenAlerts(), "1-5"), "not yet seen before any overlay");
        AppState.handle(statusReadMsg([], true));
        Test.assertMessage(AppState.containsStr(AppState.loadSeenAlerts(), "1-5"), "overlaid identity force-marked seen");
        // newAlertsSince over the now-seen set must not re-surface it as "new" (no re-notify/vibrate).
        Test.assertMessage(AppState.newAlertsSince(AppState.loadSeenAlerts()).size() == 0,
            "the overlaid, now-seen identity never re-triggers a new-alert notify");
        return true;
    }

    // === EXPIRY IS NOT A REMOVER (HIGH-C / M1) ===================================================

    (:test)
    function expiryAloneLeavesTheAlertVisible(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        // Force the retry entry's createdAt WELL past the TTL.
        var entry = AppState.dismissPending["1-5"] as Lang.Dictionary;
        entry["createdAt"] = Time.now().value() - (AppState.DISMISS_RETRY_TTL_SEC + 60);
        AppState.dismissPending["1-5"] = entry;

        // Expiry alone (no ack, no statusRead) never touches the alert.
        Test.assertEqualMessage(AppState.alerts.size(), 1, "expiry alone leaves the alert visible");

        // A delayed ack for the now-expired entry removes nothing — expiry is never a remover.
        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "a delayed/expired ack removes nothing");
        return true;
    }

    // A clock-rolled-back (future) createdAt is treated as invalid/expired too — never a permanently-
    // valid retry entry from a clock that jumped.
    (:test)
    function clockRolledFutureCreatedAtIsTreatedAsExpired(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        var entry = AppState.dismissPending["1-5"] as Lang.Dictionary;
        entry["createdAt"] = Time.now().value() + 3600;   // an hour in the future
        AppState.dismissPending["1-5"] = entry;

        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "a clock-rolled-future entry never accepts an ack");
        return true;
    }

    // The retry lane's dueDismissRetries() surface excludes expired entries (stops retrying), while the
    // DISPLAY provisional is untouched by the same expiry.
    (:test)
    function expiredEntryStopsBeingOfferedForRetry(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        var now = Time.now().value();
        Test.assertEqualMessage(AppState.dueDismissRetries(now).size(), 1, "an unexpired entry is due for retry");

        var entry = AppState.dismissPending["1-5"] as Lang.Dictionary;
        entry["createdAt"] = now - (AppState.DISMISS_RETRY_TTL_SEC + 60);
        AppState.dismissPending["1-5"] = entry;
        Test.assertEqualMessage(AppState.dueDismissRetries(now).size(), 0, "an expired entry stops being retried");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"),
            "the DISPLAY provisional is untouched by the retry lane's own expiry");
        return true;
    }

    // === CAPABILITY GATE ==========================================================================

    // Absent supportsDismissAck (old phone) ⇒ the watch runs the filtered-reconcile fallback — a
    // dispatched-but-unproven dismiss whose alert is proven ABSENT by a filtered statusRead IS removed
    // (the fallback correctly clearing it), so a mixed-version rollout is never stuck.
    (:test)
    function absentCapabilityFallsBackTo1408FilteredReconcile(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);   // the fallback's own bookkeeping (AlertConfirmDelegate always sets this)

        // A legacy host never sends supportsDismissAck at all (absent — no key on the wire).
        AppState.handle(statusReadMsg([], null));

        Test.assertEqualMessage(AppState.alerts.size(), 0,
            "absent capability ⇒ the filtered-reconcile fallback's filtered-absence removal fires (not stuck)");
        return true;
    }

    // Explicit false (t:slim) ⇒ same fallback behavior — never stranded on a pump that can't authenticate.
    (:test)
    function falseCapabilityFallsBackTo1408FilteredReconcile(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);

        AppState.handle(statusReadMsg([], false));

        Test.assertEqualMessage(AppState.alerts.size(), 0,
            "false capability (t:slim) ⇒ the filtered-reconcile fallback still clears the locally-snoozed alert");
        return true;
    }

    // True ⇒ authenticated-ack-only: the SAME filtered-absence statusRead does NOT remove the alert —
    // only a correlated dismissAck may.
    (:test)
    function trueCapabilityIsAuthenticatedAckOnlyNeverFilteredAbsence(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);

        AppState.handle(statusReadMsg([], true));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "true capability ⇒ filtered-absence alone never removes the alert");

        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 0, "only the authenticated ack removes it");
        return true;
    }

    // === ORDERING (MEDIUM-1) =====================================================================

    // An interleaved statusRead (with supportsDismissAck=true) BEFORE the dismissAck arrives does not
    // fabricate a removal — the alert stays until the ack, in whichever order the two messages land.
    (:test)
    function interleavedStatusReadBeforeAckDoesNotRemoveTheAlert(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsDismissAck = true;

        AppState.handle(statusReadMsg([], true));   // races ahead of the ack
        Test.assertEqualMessage(AppState.alerts.size(), 1, "an interleaved statusRead alone never removes the alert");

        AppState.handle(dismissAckMsg(reqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 0, "the ack, once it lands, still removes it correctly");
        return true;
    }

    // === PER-IDENTITY (at most one retry + one provisional; re-dismiss bumps generation) =========

    (:test)
    function reDismissReplacesWithNewGenerationAndInvalidatesTheOldRequestId(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var firstReqId = AppState.beginDismiss(5, 1, "Auto-off");
        var firstGen = (AppState.dismissPending["1-5"] as Lang.Dictionary)["generation"];

        var secondReqId = AppState.beginDismiss(5, 1, "Auto-off");
        var secondGen = (AppState.dismissPending["1-5"] as Lang.Dictionary)["generation"];

        Test.assertMessage(!firstReqId.equals(secondReqId), "a genuinely new occurrence mints a NEW requestId");
        Test.assertMessage(secondGen > firstGen, "generation strictly increases on a new occurrence");
        Test.assertEqualMessage(AppState.dismissPending.keys().size(), 1, "at most one retry entry per identity");
        Test.assertEqualMessage(AppState.dismissProvisional.keys().size(), 1, "at most one provisional per identity");

        // The OLD (now-superseded) requestId can no longer ack anything.
        AppState.handle(dismissAckMsg(firstReqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "an old-generation requestId's ack removes nothing");

        // The NEW requestId correctly acks.
        AppState.handle(dismissAckMsg(secondReqId, 5, 1));
        Test.assertEqualMessage(AppState.alerts.size(), 0, "the current-generation requestId's ack removes it");
        return true;
    }

    // A lost-ack RETRY reuses the SAME requestId+generation (dueDismissRetries surfaces it unchanged).
    (:test)
    function retryReusesTheSameRequestIdAndGeneration(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        var due = AppState.dueDismissRetries(Time.now().value());
        Test.assertEqualMessage(due.size(), 1, "one identity due for retry");
        var d = due[0] as Lang.Dictionary;
        Test.assertEqualMessage(d["requestId"], reqId, "the retry reuses the SAME requestId — never mints a new one");
        Test.assertEqualMessage(d["id"], 5, "the retry's alertId matches");
        Test.assertEqualMessage(d["kind"], 1, "the retry's alertKind matches");
        return true;
    }
}
