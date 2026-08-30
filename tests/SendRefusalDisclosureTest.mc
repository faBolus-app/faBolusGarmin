using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// THE SILENT SEND-GATE REFUSAL on the 1-2-3 confirm screen.
//
// `AppState.sendBolusNow()` refuses a send on SIX distinct conditions, but it used to return a bare
// Boolean — so `HoldView.deliver()` could not tell WHICH one fired. `HoldView.onUpdate` renders a reason
// for only the two conditions `mustTeardownArmedBolus()` covers (bolusPolicyDisabled, stale eligibility
// gen). For the other four — !appLive(), armContextExpired(), !pumpBolusAllowed(), reattemptBlocked() —
// `deliver()` reset the tap progress to 0 and the screen repainted the ORDINARY three-grey-circle confirm
// with NO message at all. Because only the 3rd tap crosses the send gate (`tapped()` calls `deliver()`
// solely at `_progress >= 3`), taps 1 and 2 always "worked" and tap 3 always "did nothing" — a wearer on a
// delivery-authorising surface was refused in total silence.
//
// The fix does NOT loosen any of the six gates. It restores the information the Boolean threw away:
// `bolusSendRefusal()` holds the six guards verbatim, in the identical order, and returns a reason TOKEN;
// `sendBolusNow()` consumes THAT ONE function as its single decision point, so the gate and the disclosure
// can never diverge. What is pinned here is therefore the DISCLOSURE invariant:
//
//     every state in which sendBolusNow() refuses must yield a non-empty, honest, distinguishable
//     on-screen reason — and none of that copy may imply a dose was or will be delivered.
//
// Pinned on pure AppState functions, matching tests/HoldTeardownTest.mc / tests/CanBolusTest.mc /
// tests/ArmedDoseGenTest.mc: HoldView.deliver() reaches RemoteComm.newRequestId()/phoneReachable() and
// Ui.requestUpdate(), none of which are deterministically drivable from the unit harness, so the
// safety-critical DECISION is what gets asserted — not the pixels.
module SendRefusalDisclosureTest {

    // Every token bolusSendRefusal() can return. Kept as data so the copy/honesty cases below iterate
    // the WHOLE set — a future seventh refusal that forgets its copy fails `everyTokenHasHonestCopy`.
    const ALL_TOKENS = ["policyDisabled", "staleArm", "phoneNotLive", "armExpired",
                        "pumpBlocked", "outcomePending", "unresolvedPriorSend"];

    // A cleanly-armed, fully-eligible dose: no refusal condition holds. Every field the six guards read is
    // set explicitly so cases are order-independent regardless of what other test modules left behind.
    function eligible() as Void {
        AppState.status = null;
        AppState.message = null;
        AppState.pendingRequestId = null;
        AppState.sawPhoneBolusing = false;
        AppState.outcomeSentEpoch = 0;
        AppState.readOnly = false;                       // guard 1: policy
        AppState.garminBolusEnabled = true;              // guard 1: policy
        AppState.bolusEligibilityGen = 0;                // guard 2: gen
        AppState.armedEligibilityGen = 0;                // guard 2: gen
        AppState._prevEligibilityFp = null;
        AppState.lastReplyEpoch = Time.now().value();    // guard 3: appLive()
        AppState.armedAtEpoch = Time.now().value();      // guard 4: armContextExpired()
        AppState.hostCanBolus = true;                    // guard 5: pumpBolusAllowed()
        AppState.hostBolusBlockReason = null;
        AppState.connection = "Connected";
        AppState.bolusPasscodeRequired = false;
        AppState.lastBolus = -1.0;
        AppState.clearUnresolvedTombstone();             // guard 6: reattemptBlocked()
        AppState.lastSendRefusal = null;
        RemoteComm.testPhoneReachable = null;
    }

    // Leave no in-flight/durable residue for the other test modules.
    function tidy() as Void {
        RemoteComm.testPhoneReachable = null;
        AppState.clearInFlight();
        AppState.clearUnresolvedTombstone();
        AppState.lastSendRefusal = null;
    }

    // --- 1. the baseline: an eligible arm is not refused ------------------------------------------

    (:test)
    function eligibleArmHasNoRefusal(logger as Test.Logger) as Lang.Boolean {
        eligible();
        Test.assertMessage(AppState.bolusSendRefusal() == null, "eligible arm ⇒ no refusal token");
        tidy();
        return true;
    }

    // --- 2. each of the six guards yields its OWN token -------------------------------------------

    (:test)
    function readOnlyYieldsPolicyToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.readOnly = true;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "policyDisabled", "read-only ⇒ policyDisabled");
        eligible();
        AppState.garminBolusEnabled = false;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "policyDisabled",
            "Garmin bolusing off ⇒ policyDisabled");
        tidy();
        return true;
    }

    (:test)
    function movedGenYieldsStaleArmToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.bolusEligibilityGen = AppState.armedEligibilityGen + 1;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "staleArm", "gen moved since arm ⇒ staleArm");
        tidy();
        return true;
    }

    (:test)
    function lapsedLivenessYieldsPhoneNotLiveToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        Test.assertMessage(!AppState.appLive(), "liveness has lapsed");
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "phoneNotLive", "stale reply ⇒ phoneNotLive");
        tidy();
        return true;
    }

    (:test)
    function expiredArmYieldsArmExpiredToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        Test.assertMessage(AppState.armContextExpired(), "arm has aged past the window");
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "armExpired", "expired arm ⇒ armExpired");
        tidy();
        return true;
    }

    (:test)
    function pumpNotAllowedYieldsPumpBlockedToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.hostCanBolus = false;
        Test.assertMessage(!AppState.pumpBolusAllowed(), "pump side refuses");
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "pumpBlocked", "pump refuses ⇒ pumpBlocked");
        tidy();
        return true;
    }

    (:test)
    function inFlightOutcomeYieldsOutcomePendingToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.status = "delivering";
        Test.assertMessage(AppState.outcomePending(), "an outcome is pending");
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "outcomePending",
            "in-flight outcome ⇒ outcomePending");
        AppState.status = "cancelling";
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "outcomePending",
            "mid-cancel ⇒ outcomePending too");
        tidy();
        return true;
    }

    // The tombstone half of reattemptBlocked() must be DISTINGUISHABLE from the in-flight half: they have
    // different remedies (wait for the result vs. go and check the pump's own history), so collapsing them
    // into one message would mislead the wearer.
    (:test)
    function tombstoneYieldsItsOwnDistinctToken(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.persistUnresolvedTombstone("req-prior-1", Time.now().value(), "units:1.00");
        Test.assertMessage(AppState.hasUnresolvedTombstone(), "a prior dispatch is unresolved");
        Test.assertMessage(!AppState.outcomePending(), "but nothing is in flight in THIS process");
        var tombToken = AppState.bolusSendRefusal();
        Test.assertEqualMessage(tombToken, "unresolvedPriorSend", "durable tombstone ⇒ unresolvedPriorSend");
        // Now make the OTHER half of reattemptBlocked() true as well and confirm the tokens really differ
        // (not just that two literals differ) — same gate, two different remedies for the wearer.
        AppState.status = "delivering";
        var flightToken = AppState.bolusSendRefusal();
        Test.assertEqualMessage(flightToken, "outcomePending", "in-flight half reports its own token");
        Test.assertMessage(!(flightToken as Lang.String).equals(tombToken as Lang.String),
            "the two reattemptBlocked halves are distinguishable to the confirm screen");
        Test.assertMessage(!AppState.sendRefusalDetail(tombToken as Lang.String)
                .equals(AppState.sendRefusalDetail(flightToken as Lang.String)),
            "...and their detail lines give different remedies");
        tidy();
        return true;
    }

    // --- 3. THE BUG: the four guards mustTeardownArmedBolus() cannot see must still be DISCLOSED ---

    // This is the regression test for the reported defect. For each of the four conditions,
    // mustTeardownArmedBolus() is FALSE — so HoldView's pre-existing "Bolusing off" / "Status changed"
    // notice never renders — yet sendBolusNow() refuses. Before the fix that combination was silent by
    // construction. Now every one of them must produce a non-empty reason the confirm screen can draw.
    (:test)
    function everySilentGuardNowDiscloses(logger as Test.Logger) as Lang.Boolean {
        // guard 3 — liveness lapsed, and NO intervening statusRead ever bumped the gen (which is why the
        // teardown path cannot catch it; eligibilityFingerprint()'s own `live` token is a constant).
        eligible();
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        assertDisclosed(logger, "phoneNotLive");

        // guard 4 — the arm itself aged out, gens still matched.
        eligible();
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        assertDisclosed(logger, "armExpired");

        // guard 5 — the pump refused at transmit, arm was made after the flip so no gen bump.
        eligible();
        AppState.hostCanBolus = false;
        assertDisclosed(logger, "pumpBlocked");

        // guard 6 — a durable tombstone from a prior process; never folded into the fingerprint at all,
        // so this one was silent AND permanent across relaunches.
        eligible();
        AppState.persistUnresolvedTombstone("req-prior-2", Time.now().value(), "units:2.00");
        assertDisclosed(logger, "unresolvedPriorSend");

        tidy();
        return true;
    }

    // The shared assertion for the four gap conditions: teardown blind, refusal certain, copy present.
    function assertDisclosed(logger as Test.Logger, expected as Lang.String) as Void {
        Test.assertMessage(!AppState.mustTeardownArmedBolus(),
            expected + ": mustTeardownArmedBolus() is BLIND to this condition");
        Test.assertEqualMessage(AppState.bolusSendRefusal(), expected,
            expected + ": the send gate refuses with this token");
        Test.assertMessage(AppState.sendRefusalText(expected).length() > 0,
            expected + ": has a headline to draw");
        Test.assertMessage(AppState.sendRefusalDetail(expected).length() > 0,
            expected + ": has a detail line to draw");
    }

    // --- 4. the gate and the disclosure cannot diverge ---------------------------------------------

    // sendBolusNow() must refuse EXACTLY when bolusSendRefusal() reports a token, and must record it.
    // (The eligible case is driven through the deterministic outOfRange path — RemoteComm.testPhoneReachable
    // = false — so it returns true, mints no tombstone, and needs no real radio; mirrors
    // tests/UnresolvedDeliveryTombstoneTest.mc's use of the same seam.)
    (:test)
    function refusalTokenAgreesWithSendBolusNow(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.hostCanBolus = false;
        Test.assertMessage(!AppState.sendBolusNow(null), "a refusal token ⇒ sendBolusNow returns false");
        Test.assertEqualMessage(AppState.lastSendRefusal, "pumpBlocked",
            "sendBolusNow records the token it refused on");

        eligible();
        RemoteComm.testPhoneReachable = false;
        Test.assertMessage(AppState.bolusSendRefusal() == null, "no refusal token for an eligible arm");
        Test.assertMessage(AppState.sendBolusNow(null), "no token ⇒ sendBolusNow proceeds (true)");
        Test.assertMessage(AppState.lastSendRefusal == null, "a proceeding send clears any stale refusal");
        tidy();
        return true;
    }

    // A fresh arm owns a fresh refusal slot: re-entering the bolus flow must not inherit the last
    // screen's refusal notice.
    (:test)
    function armAndResetClearTheRecordedRefusal(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.hostCanBolus = false;
        Test.assertMessage(!AppState.sendBolusNow(null), "refused");
        Test.assertMessage(AppState.lastSendRefusal != null, "refusal recorded");
        AppState.armBolus();
        Test.assertMessage(AppState.lastSendRefusal == null, "a fresh arm clears the refusal");

        AppState.lastSendRefusal = "pumpBlocked";
        AppState.reset();
        Test.assertMessage(AppState.lastSendRefusal == null, "reset() clears the refusal");
        tidy();
        return true;
    }

    // --- 5. guard ORDER is the send gate's order ---------------------------------------------------

    // bolusSendRefusal() must short-circuit in sendBolusNow()'s exact order, so the reason shown is the
    // reason the gate actually stopped on. Peel the conditions off one at a time from the front.
    (:test)
    function refusalOrderMatchesTheSendGate(logger as Test.Logger) as Lang.Boolean {
        eligible();
        // All six conditions true at once.
        AppState.readOnly = true;
        AppState.bolusEligibilityGen = AppState.armedEligibilityGen + 1;
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        AppState.hostCanBolus = false;
        AppState.persistUnresolvedTombstone("req-order-1", Time.now().value(), "units:3.00");

        Test.assertEqualMessage(AppState.bolusSendRefusal(), "policyDisabled", "guard 1 wins");
        AppState.readOnly = false;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "staleArm", "guard 2 next");
        AppState.bolusEligibilityGen = AppState.armedEligibilityGen;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "phoneNotLive", "guard 3 next");
        AppState.lastReplyEpoch = Time.now().value();
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "armExpired", "guard 4 next");
        AppState.armedAtEpoch = Time.now().value();
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "pumpBlocked", "guard 5 next");
        AppState.hostCanBolus = true;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "unresolvedPriorSend", "guard 6 last");
        AppState.clearUnresolvedTombstone();
        Test.assertMessage(AppState.bolusSendRefusal() == null, "all six clear ⇒ no refusal");
        tidy();
        return true;
    }

    // --- 6. boundary neighbours on the two time windows -------------------------------------------

    // appLive() uses `<=`, so exactly CONNECTION_STALE_SEC is still LIVE and only +1 refuses. Pinning both
    // sides stops a future edit from silently shifting the window by one second in either direction.
    (:test)
    function livenessWindowBoundaryNeighbours(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC - 1);
        Test.assertMessage(AppState.bolusSendRefusal() == null, "inside the window ⇒ no refusal");
        AppState.lastReplyEpoch = Time.now().value() - AppState.CONNECTION_STALE_SEC;
        Test.assertMessage(AppState.bolusSendRefusal() == null, "exactly at the window ⇒ still live");
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "phoneNotLive", "one past ⇒ refused");
        // 0 (never replied / cold launch) fails closed.
        AppState.lastReplyEpoch = 0;
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "phoneNotLive", "cold launch ⇒ refused");
        tidy();
        return true;
    }

    // armContextExpired() uses `>`, so exactly ARM_CONTEXT_STALE_SEC is NOT yet expired.
    (:test)
    function armWindowBoundaryNeighbours(logger as Test.Logger) as Lang.Boolean {
        eligible();
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC - 1);
        Test.assertMessage(AppState.bolusSendRefusal() == null, "inside the window ⇒ no refusal");
        AppState.armedAtEpoch = Time.now().value() - AppState.ARM_CONTEXT_STALE_SEC;
        Test.assertMessage(AppState.bolusSendRefusal() == null, "exactly at the window ⇒ not yet expired");
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        Test.assertEqualMessage(AppState.bolusSendRefusal(), "armExpired", "one past ⇒ refused");
        // Never armed (0) must never read as expired.
        AppState.armedAtEpoch = 0;
        Test.assertMessage(AppState.bolusSendRefusal() == null, "never armed ⇒ never spuriously expired");
        tidy();
        return true;
    }

    // --- 7. the copy itself: present, and honest ---------------------------------------------------

    // EVERY reachable token must have both lines. An empty string here is the original bug: a refusal the
    // wearer cannot see.
    (:test)
    function everyTokenHasHonestCopy(logger as Test.Logger) as Lang.Boolean {
        eligible();
        for (var i = 0; i < ALL_TOKENS.size(); i += 1) {
            var t = ALL_TOKENS[i] as Lang.String;
            Test.assertMessage(AppState.sendRefusalText(t).length() > 0, t + " has a headline");
            Test.assertMessage(AppState.sendRefusalDetail(t).length() > 0, t + " has a detail line");
        }
        // Unknown / absent tokens degrade to "" (mirrors bolusReasonText) rather than crashing the
        // confirm screen's draw.
        Test.assertEqualMessage(AppState.sendRefusalText(null), "", "null token ⇒ empty headline");
        Test.assertEqualMessage(AppState.sendRefusalDetail(null), "", "null token ⇒ empty detail");
        Test.assertEqualMessage(AppState.sendRefusalText("nonsense"), "", "unknown token ⇒ empty headline");
        tidy();
        return true;
    }

    // On a delivery-authorising surface the copy must never let the wearer believe insulin went in. Every
    // detail line states "not sent"; no line may contain a delivery word.
    (:test)
    function noCopyImpliesDelivery(logger as Test.Logger) as Lang.Boolean {
        eligible();
        for (var i = 0; i < ALL_TOKENS.size(); i += 1) {
            var t = ALL_TOKENS[i] as Lang.String;
            var detail = AppState.sendRefusalDetail(t);
            Test.assertMessage(detail.toLower().find("not sent") != null,
                t + ": the detail line says 'not sent'");
            assertNoDeliveryWord(logger, t, AppState.sendRefusalText(t));
            assertNoDeliveryWord(logger, t, detail);
        }
        tidy();
        return true;
    }

    // "deliver" catches delivered/delivering/delivery; the rest catch the other ways copy drifts into
    // implying a completed dose. Applies to EVERY headline and detail line, all of which are fixed
    // literals in sendRefusalText/sendRefusalDetail — including pumpBlocked's "Pump not ready", which is
    // deliberately NOT sourced from bolusReasonText(hostBolusBlockReason): that map's longest string
    // ("Phone not connected", 19 chars) would clip the 14-char FONT_SMALL headline budget, and the wearer
    // already gets the host's specific reason on the main screen via bolusBlockLabel().
    function assertNoDeliveryWord(logger as Test.Logger, token as Lang.String, s as Lang.String) as Void {
        var lower = s.toLower();
        Test.assertMessage(lower.find("deliver") == null, token + ": copy must not say 'deliver' — " + s);
        Test.assertMessage(lower.find("success") == null, token + ": copy must not say 'success' — " + s);
        Test.assertMessage(lower.find("dosed") == null, token + ": copy must not say 'dosed' — " + s);
        Test.assertMessage(lower.find("complete") == null, token + ": copy must not say 'complete' — " + s);
    }

    // The two conditions HoldView ALREADY disclosed must keep their exact original wording, so this fix
    // cannot regress the pre-existing "Bolusing off" / "Status changed" notices.
    (:test)
    function preExistingNoticeWordingUnchanged(logger as Test.Logger) as Lang.Boolean {
        eligible();
        Test.assertEqualMessage(AppState.sendRefusalText("policyDisabled"), "Bolusing off",
            "the policy notice keeps its original headline");
        Test.assertEqualMessage(AppState.sendRefusalText("staleArm"), "Status changed",
            "the stale-arm notice keeps its original headline");
        tidy();
        return true;
    }

    // A refusal notice that CLIPS off the edge of a 390 px round watch face is barely better than the
    // silence it replaces, so the copy is held to what this tree already ships: 14 chars at FONT_SMALL
    // (the longest existing literal anywhere is "Status changed" / "Cancel (START)") and DetailsView's
    // documented ~28-char FONT_XTINY row budget. This is the reason the host's own specific reason
    // (bolusReasonText, up to 19 chars) is NOT promoted onto the headline.
    (:test)
    function everyLineFitsTheConfirmScreen(logger as Test.Logger) as Lang.Boolean {
        eligible();
        for (var i = 0; i < ALL_TOKENS.size(); i += 1) {
            var t = ALL_TOKENS[i] as Lang.String;
            var head = AppState.sendRefusalText(t);
            var detail = AppState.sendRefusalDetail(t);
            Test.assertMessage(head.length() <= AppState.REFUSAL_HEAD_MAX_CHARS,
                t + ": headline fits FONT_SMALL — " + head);
            Test.assertMessage(detail.length() <= AppState.REFUSAL_DETAIL_MAX_CHARS,
                t + ": detail fits FONT_XTINY — " + detail);
        }
        tidy();
        return true;
    }
}
