using Toybox.Lang;
using Toybox.Test;

// R2-15/VA-16 (V-Audit): the background service (BgService.onPhoneMessage) sent a statusRead and must
// publish + exit ONLY on the matching statusRead reply — a non-statusReply dict that lands first must be
// IGNORED (return without exiting), not mistaken for the reply. AppState.isStatusReply(dict) is the pure
// discriminator. AppState is compiled into the test binary (test.jungle). Style mirrors
// tests/CanBolusTest.mc.
module StatusReplyTest {

    // A statusRead dict is the awaited reply.
    (:test)
    function statusReadIsReply(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppState.isStatusReply({ "kind" => "statusRead" }),
            "kind==statusRead ⇒ true");
        return true;
    }

    // Out-of-band toggles, a stray bolusStatus echo, and an empty dict are NOT the reply.
    (:test)
    function nonStatusReadIsNotReply(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(!AppState.isStatusReply({ "type" => "eating_sense", "on" => true }),
            "eating_sense toggle ⇒ false (no kind)");
        Test.assertMessage(!AppState.isStatusReply({ "type" => "hr_ctl", "on" => true }),
            "hr_ctl toggle ⇒ false (no kind)");
        Test.assertMessage(!AppState.isStatusReply({ "kind" => "bolusStatus", "requestId" => "x" }),
            "bolusStatus echo ⇒ false");
        Test.assertMessage(!AppState.isStatusReply({}),
            "empty dict ⇒ false");
        return true;
    }

    // A non-string kind (malformed wire) is safely rejected — guards the instanceof check.
    (:test)
    function nonStringKindIsNotReply(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(!AppState.isStatusReply({ "kind" => 7 }),
            "non-string kind ⇒ false (never coerce / crash)");
        return true;
    }

    // R2-15 (V-Audit addendum): TRUE request-id correlation. The background service retains the requestId
    // it minted for its statusRead REQUEST; the phone now ECHOES that id in the reply
    // (faBolus AppModel.statusCommand(replyingTo:)). A reply is OURS iff it is a statusRead AND its echoed
    // requestId matches our minted id.
    (:test)
    function correlatedReplyMatchesMintedId(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            AppState.isCorrelatedStatusReply({ "kind" => "statusRead", "requestId" => "r-42" }, "r-42"),
            "matching echoed requestId ⇒ correlated");
        return true;
    }

    // A statusRead reply carrying a DIFFERENT requestId is someone else's / stale — rejected. And a
    // bolusStatus (or any non-statusRead) dict is never a correlated statusRead reply regardless of id.
    (:test)
    function mismatchedOrWrongKindIsNotCorrelated(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            !AppState.isCorrelatedStatusReply({ "kind" => "statusRead", "requestId" => "r-OTHER" }, "r-42"),
            "a statusRead reply with a different requestId is not ours");
        Test.assertMessage(
            !AppState.isCorrelatedStatusReply({ "kind" => "bolusStatus", "requestId" => "r-42" }, "r-42"),
            "bolusStatus is not a statusRead reply");
        return true;
    }

    // Backward-compat: a legacy phone that doesn't echo requestId ⇒ fall back to the kind discriminator;
    // a null minted id (we somehow didn't retain one) also falls back to kind so a real reply isn't dropped.
    (:test)
    function legacyOrNoMintedIdFallsBackToKind(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            AppState.isCorrelatedStatusReply({ "kind" => "statusRead" }, "r-42"),
            "no echoed requestId (legacy phone) ⇒ accept on kind");
        Test.assertMessage(
            AppState.isCorrelatedStatusReply({ "kind" => "statusRead", "requestId" => "r-42" }, null),
            "null minted id ⇒ kind fallback");
        return true;
    }

    // CX-G-03 (V-Audit): the FOREGROUND poll (FaBolusApp.pollTick + handlePhoneData) now correlates a
    // statusRead reply against AppState.fgPollMintedReqId BEFORE calling AppState.handle() — mirroring
    // BgServiceDelegate exactly. These drive the REAL dispatch path (not just the pure helpers above),
    // since FaBolusApp.onPhoneMessage itself can't be exercised directly (Comm.PhoneAppMessage has no
    // test-constructible instance) — handlePhoneData(data) is the extracted, directly-callable seam.
    // pollTick() mints + retains the real reqId (exactly as the shipping poll loop does), so these never
    // hardcode a minted id.

    // A reply whose echoed requestId does NOT match the poll's minted id is discarded BEFORE handle()
    // runs — glucose is left UNCHANGED and _pollOutstanding stays true (not cleared).
    (:test)
    function fgMismatchedReplyDiscardedBeforeMutation(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.pollTick();   // mints + retains AppState.fgPollMintedReqId; sets _pollOutstanding = true
        AppState.glucose = 111;
        app.handlePhoneData({ "kind" => "statusRead", "requestId" => "definitely-not-the-minted-id", "bgMgdl" => 222 });
        Test.assertEqualMessage(AppState.glucose, 111,
            "mismatched-reqId fg reply discarded ⇒ glucose unchanged (Addresses codex MEDIUM)");
        Test.assertMessage(app.pollOutstanding(), "mismatched-reqId fg reply ⇒ _pollOutstanding NOT cleared");
        return true;
    }

    // A reply whose echoed requestId MATCHES the poll's minted id is applied and clears poll-outstanding.
    (:test)
    function fgMatchedReplyAppliedAndClearsPollOutstanding(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.pollTick();
        var mintedId = AppState.fgPollMintedReqId;
        AppState.glucose = 111;
        app.handlePhoneData({ "kind" => "statusRead", "requestId" => mintedId, "bgMgdl" => 222 });
        Test.assertEqualMessage(AppState.glucose, 222, "matched fg reply ⇒ applied");
        Test.assertMessage(!app.pollOutstanding(), "matched fg reply ⇒ _pollOutstanding cleared");
        return true;
    }

    // LEGACY FALLBACK: a reply with NO echoed requestId (older phone) is still accepted and clears
    // poll-outstanding — retained backward-compat, see AppState.isCorrelatedStatusReply's either-id-
    // absent fallback and FaBolusApp.handlePhoneData's CX-G-03 comment for the rationale.
    (:test)
    function fgLegacyNoReqIdReplyStillAccepted(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.pollTick();
        AppState.glucose = 111;
        app.handlePhoneData({ "kind" => "statusRead", "bgMgdl" => 222 });   // no requestId echoed
        Test.assertEqualMessage(AppState.glucose, 222, "legacy no-reqId reply still accepted (backward-compat)");
        Test.assertMessage(!app.pollOutstanding(), "legacy reply still clears poll-outstanding");
        return true;
    }

    // A non-statusRead reply (e.g. a bolusStatus echo) is NEVER gated by the fg correlation check — it
    // always proceeds to handle() regardless of fgPollMintedReqId (which is keyed to the poll's OWN
    // requestId, unrelated to the bolus's pendingRequestId).
    (:test)
    function nonStatusReadReplyNeverGated(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.pollTick();   // mints an unrelated fgPollMintedReqId — must not interfere below
        AppState.pendingRequestId = "rid-bolus-1";
        AppState.status = "delivering";
        app.handlePhoneData({ "kind" => "bolusStatus", "requestId" => "rid-bolus-1", "status" => "delivered" });
        Test.assertEqualMessage(AppState.status, "delivered",
            "non-statusRead (bolusStatus) reply is never reqId-gated by the fg poll correlation");
        return true;
    }
}
