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
}
