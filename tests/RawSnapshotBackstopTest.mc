using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;
using Toybox.Application.Storage;

// Plan 14-10 (owner-authorized follow-up to 14-09 checkpoint #3's `raw-snapshot-backstop` option,
// D1/D2/D3 — see faBolus-internal OWNER-DECISIONS.md "Plan 14-09"/"Plan 14-10"): the RAW pump-alert-
// snapshot proof-of-absence backstop for a pump that does NOT honor a remote dismiss (t:slim X2,
// `supportsRemoteAlertDismiss == false`). This is the MIDDLE capability tier, inserted between the
// 14-09 authenticated-ack tier (supportsDismissAck) and the 14-08 filtered-reconcile fallback
// (reconcileDismissSent) — `handle()`'s 2-way branch becomes 3-way, chosen by CAPABILITY alone, never by
// whether `rawAlerts` happens to be present. Style mirrors tests/DismissAckTest.mc exactly (same
// baseline/simulateRelaunch/wipeStorage idiom, same direct AppState.handle() driving).
module RawSnapshotBackstopTest {

    function alertDict(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    // A statusRead reply carrying a filtered `alerts` array, the DYNAMIC capability flags (null = absent
    // on the wire), and an OPTIONAL `rawAlerts` array — `rawArr == null` means the key is genuinely
    // ABSENT from the message (never sent as a JSON null), matching how the phone omits the field.
    function statusReadMsg(alertsArr as Lang.Array, supportsAck as Lang.Boolean?,
                           supportsRaw as Lang.Boolean?, rawArr as Lang.Array?) as Lang.Dictionary {
        var d = { "kind" => "statusRead", "alerts" => alertsArr };
        if (supportsAck != null) { d["supportsDismissAck"] = supportsAck; }
        if (supportsRaw != null) { d["supportsRawAlertSnapshot"] = supportsRaw; }
        if (rawArr != null) { d["rawAlerts"] = rawArr; }
        return d;
    }

    function wipeRawSnapshotStorage() as Void {
        Storage.deleteValue(AppState.KEY_DISMISS_PENDING);
        Storage.deleteValue(AppState.KEY_DISMISS_PROVISIONAL);
        Storage.deleteValue(AppState.KEY_SUPPORTS_DISMISS_ACK);
        Storage.deleteValue(AppState.KEY_SUPPORTS_RAW_ALERT_SNAPSHOT);
        Storage.deleteValue(AppState.KEY_SEEN_ALERTS);
    }

    function baseline() as Void {
        AppState.alerts = [];
        AppState.dismissPending = {};
        AppState.dismissProvisional = {};
        AppState.supportsDismissAck = false;
        AppState.supportsRawAlertSnapshot = false;
        AppState.dismissSentAlertIdentities = [];
        AppState.readOnly = false;
        wipeRawSnapshotStorage();
    }

    // "Cold relaunch": clear the in-memory mirror (a real process restart would lose it) WITHOUT
    // touching Storage, then call loadPrefs() — the exact call FaBolusApp.onStart() makes.
    function simulateRelaunch() as Void {
        AppState.dismissPending = {};
        AppState.dismissProvisional = {};
        AppState.supportsDismissAck = false;
        AppState.supportsRawAlertSnapshot = false;
        AppState.loadPrefs();
    }

    // === PROOF-OF-ABSENCE REMOVAL ================================================================

    (:test)
    function rawAbsenceRemovesTheWearerDismissedAlert(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"), "provisional retained after beginDismiss");

        // rawAlerts OMITS the identity entirely — proof the pump dropped it. supportsDismissAck=false
        // (absent from the wire, t:slim) so the RAW tier — not ack-mode — is what's under test.
        AppState.handle(statusReadMsg([], false, true, []));

        Test.assertEqualMessage(AppState.alerts.size(), 0, "absence from a PRESENT rawAlerts removes the alert");
        Test.assertMessage(!AppState.dismissProvisional.hasKey("1-5"), "the provisional is cleared on proof-of-absence removal");
        return true;
    }

    // A sibling alert not in the wearer's dismiss lane is untouched by the prune.
    (:test)
    function rawAbsenceRemovalLeavesSiblingUntouched(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off"), alertDict(9, 2, "Low insulin") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        // rawAlerts carries the sibling but omits the dismissed identity.
        AppState.handle(statusReadMsg([ alertDict(9, 2, "Low insulin") ], false, true,
                                       [ alertDict(9, 2, "Low insulin") ]));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "only the proven-absent identity is removed");
        var kept = AppState.alerts[0] as Lang.Dictionary;
        Test.assertMessage(kept["id"] == 9 && kept["kind"] == 2, "the sibling alert survives");
        return true;
    }

    // === KEEP-VISIBLE-ON-PRESENT (D2 — the accepted t:slim behavior change) =====================

    (:test)
    function rawPresenceKeepsTheAlertVisibleAndForceMarksSeen(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");

        // The filtered list omits it (it's dismissed), but rawAlerts STILL CONTAINS it — the pump
        // hasn't cleared the condition.
        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));

        Test.assertEqualMessage(AppState.alerts.size(), 1, "D2: present in rawAlerts ⇒ kept visible (overlaid)");
        Test.assertMessage(AppState.containsStr(AppState.loadSeenAlerts(), "1-5"),
            "the kept-visible alert is force-marked seen (no re-nag)");
        return true;
    }

    // Repeated statusReads that keep the identity in rawAlerts keep it visible indefinitely.
    (:test)
    function rawPresenceKeepsAlertVisibleIndefinitely(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));
        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));
        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "repeated raw-presence never re-nags/removes");
        return true;
    }

    // === NEVER-REMOVED-BY-LOCAL-SNOOZE (the core fix) ============================================

    // Filtered `alerts` OMITS the identity (phone locally-snoozed it) but rawAlerts CONTAINS it ⇒ the
    // alert STAYS visible — filtered-absence is NOT proof on the raw-snapshot tier.
    (:test)
    function filteredAbsenceWithRawPresenceNeverRemoves(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);   // the 14-08 bookkeeping AlertConfirmDelegate always sets too

        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));

        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "core fix: local-snooze filtered-absence is never proof on the raw-snapshot tier");
        return true;
    }

    // === PRESENT-INCLUDING-EMPTY IS AUTHORITATIVE ================================================

    (:test)
    function presentEmptyRawAlertsRemovesEveryWearerProvisional(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off"), alertDict(9, 2, "Low insulin") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.beginDismiss(9, 2, "Low insulin");
        Test.assertEqualMessage(AppState.dismissProvisional.keys().size(), 2, "two provisionals recorded");

        // A PRESENT but EMPTY rawAlerts ⇒ the pump reports zero active alerts ⇒ both are proven cleared.
        AppState.handle(statusReadMsg([], false, true, []));

        Test.assertEqualMessage(AppState.alerts.size(), 0, "present-empty rawAlerts removes every wearer provisional");
        Test.assertEqualMessage(AppState.dismissProvisional.keys().size(), 0, "both provisionals cleared");
        return true;
    }

    // === FAIL-CLOSED on absent/malformed rawAlerts, NO tier fall-through =========================

    (:test)
    function absentRawAlertsUnderTheCapabilityRemovesNothingAndDoesNotFallThrough(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);   // if this fires, the 14-08 fallback WOULD wrongly remove it

        // supportsRawAlertSnapshot=true but the message carries NO rawAlerts key at all.
        AppState.handle(statusReadMsg([], false, true, null));

        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "absent rawAlerts under the capability removes nothing — never falls through to 14-08");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"), "the provisional survives an absent rawAlerts");
        return true;
    }

    // A non-Array rawAlerts (malformed message) is treated exactly like absent.
    (:test)
    function nonArrayRawAlertsIsTreatedAsAbsent(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        var msg = statusReadMsg([], false, true, null);
        msg["rawAlerts"] = "not an array";
        AppState.handle(msg);
        Test.assertEqualMessage(AppState.alerts.size(), 1, "a non-Array rawAlerts removes nothing (treated as absent)");
        return true;
    }

    // A malformed item (missing/non-numeric id or kind) is skipped, never traps, and never falsely
    // treats an otherwise-valid sibling as absent.
    (:test)
    function malformedRawAlertsItemIsSkippedNeverTraps(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off"), alertDict(9, 2, "Low insulin") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.beginDismiss(9, 2, "Low insulin");
        var raw = [
            { "id" => 9, "kind" => 2, "title" => "Low insulin" },       // valid — id 9 present
            { "id" => "not-a-number", "kind" => 1, "title" => "junk" }, // malformed — must be skipped, not trap
        ];
        AppState.handle(statusReadMsg([ alertDict(9, 2, "Low insulin") ], false, true, raw));
        // id=5 kind=1 has NO valid entry in raw ⇒ proven absent ⇒ removed. id=9 kind=2 IS present ⇒ kept.
        Test.assertEqualMessage(AppState.alerts.size(), 1, "the malformed raw item never traps; id 5 is removed, id 9 kept");
        var kept = AppState.alerts[0] as Lang.Dictionary;
        Test.assertMessage(kept["id"] == 9 && kept["kind"] == 2, "the valid sibling survives");
        return true;
    }

    // === TITLE-AGNOSTIC ABSENCE ORACLE (guards a title-driven false-removal) ====================

    // A rawAlerts item with a valid (id,kind) but a malformed/absent title still counts as PRESENT.
    (:test)
    function malformedTitleInRawAlertsStillCountsIdentityAsPresent(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        var raw = [ { "id" => 5, "kind" => 1, "title" => 12345 } ];   // title is a Number, not a String
        AppState.handle(statusReadMsg([], false, true, raw));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "a valid (id,kind) with a malformed title still counts as PRESENT — never falsely removed");
        return true;
    }

    (:test)
    function absentTitleInRawAlertsStillCountsIdentityAsPresent(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        var raw = [ { "id" => 5, "kind" => 1 } ];   // title key entirely absent
        AppState.handle(statusReadMsg([], false, true, raw));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "a valid (id,kind) with NO title still counts as PRESENT — never falsely removed");
        return true;
    }

    // === EXPIRY IS NOT A REMOVER (HIGH-C carried forward) ========================================

    (:test)
    function retryLaneExpiryAloneNeverRemovesOnTheRawTier(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        var entry = AppState.dismissPending["1-5"] as Lang.Dictionary;
        entry["createdAt"] = Time.now().value() - (AppState.DISMISS_RETRY_TTL_SEC + 60);
        AppState.dismissPending["1-5"] = entry;

        // rawAlerts still contains the identity — expiry of the retry lane must not remove the DISPLAY
        // provisional; only raw-absence does.
        AppState.handle(statusReadMsg([], false, true, [ alertDict(5, 1, "Auto-off") ]));
        Test.assertEqualMessage(AppState.alerts.size(), 1, "expiry alone never removes on the raw tier");
        return true;
    }

    // === THREE-WAY CAPABILITY GATE, CAPABILITY-FIRST, MUTUALLY EXCLUSIVE ========================

    // supportsDismissAck=true suppresses the raw path even when rawAlerts is present and omits the
    // identity — ack-mode owns removal exclusively; a present-but-omitting rawAlerts must NOT remove it.
    (:test)
    function dismissAckCapabilitySuppressesTheRawPathEvenWhenRawOmitsTheIdentity(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        // BOTH capabilities technically present on the wire (shouldn't happen in practice — mutually
        // exclusive by construction on the phone) — supportsDismissAck TRUE must win: no removal from
        // rawAlerts' absence.
        AppState.handle(statusReadMsg([], true, true, []));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "supportsDismissAck=true takes the ack-mode branch — the raw path never runs, even with rawAlerts=[] present");
        return true;
    }

    // Neither capability present ⇒ 14-08 fallback runs exactly as before (unchanged behavior).
    (:test)
    function neitherCapabilityRunsThe1408FallbackUnchanged(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);
        AppState.handle(statusReadMsg([], null, null, null));
        Test.assertEqualMessage(AppState.alerts.size(), 0,
            "neither capability ⇒ 14-08 filtered-absence fallback fires exactly as before");
        return true;
    }

    // supportsRawAlertSnapshot=true (dismissAck false/absent) selects the raw tier even when rawAlerts
    // is absent — it must NOT silently fall through to the 14-08 fallback.
    (:test)
    function rawCapabilitySelectsRawTierEvenWithAbsentRawAlertsNeverThe1408Fallback(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.markDismissSent(5, 1);   // if the 14-08 fallback ran, this WOULD get removed
        AppState.handle(statusReadMsg([], false, true, null));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "supportsRawAlertSnapshot=true selects the raw tier (keep-visible on absent rawAlerts), never the 14-08 fallback");
        return true;
    }

    // === ANTI-REGRESSION (truth #2): oracle-not-display ==========================================

    // An identity present in rawAlerts that the wearer NEVER dismissed (no provisional) is never added
    // to the displayed `alerts` — the raw list is an oracle, not a display feed.
    (:test)
    function rawAlertsIdentityNeverDismissedIsNeverAddedToTheDisplay(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [];   // the filtered list has nothing active
        // rawAlerts carries an identity the wearer never touched on the wrist.
        AppState.handle(statusReadMsg([], false, true, [ alertDict(7, 3, "Sensor error") ]));
        Test.assertEqualMessage(AppState.alerts.size(), 0,
            "a rawAlerts identity never dismissed by the wearer is never added to the display");
        return true;
    }

    // === RELAUNCH TIER PERSISTENCE ================================================================

    (:test)
    function relaunchRestoresTheRawCapabilityAndReconcilesOnTheRawPath(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsRawAlertSnapshot = true;
        Storage.setValue(AppState.KEY_SUPPORTS_RAW_ALERT_SNAPSHOT, true);
        AppState.markDismissSent(5, 1);   // if the 14-08 fallback ran post-relaunch, this WOULD get removed

        simulateRelaunch();
        Test.assertMessage(AppState.supportsRawAlertSnapshot, "loadPrefs restores the persisted raw-snapshot capability");
        Test.assertMessage(AppState.dismissProvisional.hasKey("1-5"), "loadPrefs restores the display provisional");

        // The FIRST post-relaunch statusRead: a FILTERED absence (local-snooze-contaminated) that also
        // carries the capability but OMITS rawAlerts (not-yet-polled window) — must keep it visible, not
        // fall through to the 14-08 fallback.
        AppState.handle(statusReadMsg([], null, true, null));
        Test.assertEqualMessage(AppState.alerts.size(), 1,
            "relaunch: the raw tier (not the 14-08 fallback) reconciles the first post-relaunch reply");
        return true;
    }

    // === 14-09 UNCHANGED ==========================================================================

    // An ack-mode (supportsDismissAck=true) sequence behaves exactly as DismissAckTest.mc expects,
    // driven through THIS test file too (belt-and-suspenders that the 3-way branch didn't disturb it).
    (:test)
    function ackModeSequenceUnchangedByTheThreeWayBranch(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.alerts = [ alertDict(5, 1, "Auto-off") ];
        var reqId = AppState.beginDismiss(5, 1, "Auto-off");
        AppState.supportsDismissAck = true;

        AppState.handle(statusReadMsg([], true, null, null));   // filtered-absence alone
        Test.assertEqualMessage(AppState.alerts.size(), 1, "ack-mode: filtered-absence alone never removes (unchanged)");

        AppState.handle({ "kind" => "dismissAck", "requestId" => reqId, "alertId" => 5, "alertKind" => 1 });
        Test.assertEqualMessage(AppState.alerts.size(), 0, "ack-mode: only the authenticated ack removes it (unchanged)");
        return true;
    }
}
