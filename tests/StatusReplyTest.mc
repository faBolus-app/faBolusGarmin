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
}
