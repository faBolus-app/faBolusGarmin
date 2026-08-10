using Toybox.Lang;
using Toybox.Test;

// C2 §2.3: the entered 4-digit bolus passcode is added to the wire ONLY when a code was actually entered
// — the outbound "bolusPasscode" key is present when the builder is given a non-null code, and OMITTED
// entirely when the code is null (no passcode required). The phone is the sole authority: it verifies the
// code and denies a wrong/absent one; the watch only collects + transmits it, never verifies or persists.
// These pin the additive-field contract on exactly the two delivery-authorizing builders (bolusRequest /
// bolusRequestCarbs) and its ABSENCE on the non-passcode builders (cancel/suspend/resume). RemoteComm.mc
// is compiled into the test binary (test.jungle); the View/Delegate UI is not, so the testable logic
// lives in the builder. Style mirrors tests/SentAtTest.mc.
module BolusPasscodeTest {

    // A code passed ⇒ "bolusPasscode" present, a String, and exactly the value passed (verbatim; the
    // watch does no transform — the phone compares against the real passcode).
    (:test)
    function bolusRequestIncludesCodeWhenPresent(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.bolusRequest(2.5, "rid-1", "1234");
        Test.assertMessage(cmd.hasKey("bolusPasscode"), "bolusRequest: bolusPasscode present when a code is passed");
        Test.assertMessage(cmd["bolusPasscode"] instanceof Lang.String, "bolusPasscode is a Lang.String");
        Test.assertEqualMessage(cmd["bolusPasscode"], "1234", "bolusPasscode is the entered code verbatim");
        return true;
    }

    // No code (null) ⇒ the key is OMITTED entirely (not present-but-empty) so the phone can tell "no
    // passcode entered" from "empty passcode". Guards against always-emitting the key.
    (:test)
    function bolusRequestOmitsCodeWhenNull(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.bolusRequest(2.5, "rid-2", null);
        Test.assertMessage(!cmd.hasKey("bolusPasscode"), "bolusRequest: bolusPasscode OMITTED when code is null");
        return true;
    }

    // Carb variant: same additive contract — present with the value when a code is passed.
    (:test)
    function bolusRequestCarbsIncludesCodeWhenPresent(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.bolusRequestCarbs(30, 120, 1.8, "rid-3", "0000", false);
        Test.assertMessage(cmd.hasKey("bolusPasscode"), "bolusRequestCarbs: bolusPasscode present when a code is passed");
        Test.assertEqualMessage(cmd["bolusPasscode"], "0000", "bolusPasscode is the entered code verbatim");
        // The carb builder still omits bgMgdl when bg is null (unrelated additive field) — sanity that the
        // passcode addition didn't disturb the existing bg-omission contract. (includeStale=false: carbs-only.)
        var noBg = RemoteComm.bolusRequestCarbs(30, null, 1.8, "rid-3b", "0000", false);
        Test.assertMessage(!noBg.hasKey("bgMgdl"), "bgMgdl still omitted when bg is null");
        Test.assertMessage(noBg.hasKey("bolusPasscode"), "bolusPasscode still present alongside an omitted bgMgdl");
        return true;
    }

    // Carb variant: OMITTED when the code is null.
    (:test)
    function bolusRequestCarbsOmitsCodeWhenNull(logger as Test.Logger) as Lang.Boolean {
        var cmd = RemoteComm.bolusRequestCarbs(30, 120, 1.8, "rid-4", null, false);
        Test.assertMessage(!cmd.hasKey("bolusPasscode"), "bolusRequestCarbs: bolusPasscode OMITTED when code is null");
        return true;
    }

    // The passcode is NEVER attached to the non-bolus (non-delivery-authorizing) builders — those take no
    // code param at all, so a passcode can't leak onto a cancel/suspend/resume command.
    (:test)
    function nonBolusBuildersNeverCarryCode(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(!RemoteComm.cancelBolus("rid-5").hasKey("bolusPasscode"), "cancelBolus carries no bolusPasscode");
        Test.assertMessage(!RemoteComm.suspendPump("rid-6").hasKey("bolusPasscode"), "suspendPump carries no bolusPasscode");
        Test.assertMessage(!RemoteComm.resumePump("rid-7").hasKey("bolusPasscode"), "resumePump carries no bolusPasscode");
        return true;
    }
}
