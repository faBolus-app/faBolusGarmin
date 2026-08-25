using Toybox.Lang;
using Toybox.Test;

// CX-G-11 (V-Audit): FaBolusApp.handlePhoneData (extracted from onPhoneMessage — see tests/
// StatusReplyTest.mc's CX-G-03 header for why the extraction was needed: Comm.PhoneAppMessage has no
// test-constructible instance) read the inbound `type` field as `(type as Lang.String)` after only a
// `type != null` null-check — a non-null, non-String `type` (a malformed/hostile wire dict) hit an
// UNGUARDED cast and would crash the phone-message handler (a watch-side denial-of-service). The exact
// site: FaBolusApp.mc's onPhoneMessage (now handlePhoneData), the `type != null && (type as
// Lang.String).equals("eating_sense")` / `...equals("hr_ctl")` checks — confirmed via `grep -n "as
// Lang\." source/app/FaBolusApp.mc` before editing (RESEARCH Open Question 1). Fixed by instanceof-
// guarding before the cast, mirroring BgService.mc's already-guarded pattern. AppState.handle()'s own
// `data["kind"] as Lang.String?` (a second, independent unguarded-cast site found via the same grep
// sweep across AppState.mc) is fixed the same way, reusing the existing strCap() helper (GA-09).
// Style mirrors tests/RelayResilienceTest.mc (constructs a real `new FaBolusApp()`).
module PhoneMessageCastGuardTest {

    // A non-String `type` (e.g. a Number, as a malformed/hostile phone might send) must not crash the
    // handler — reaching `return true` below (no uncaught exception) IS the assertion.
    (:test)
    function malformedTypeFieldDoesNotCrash(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.handlePhoneData({ "type" => 7, "on" => true });
        return true;
    }

    // A non-String `kind` (e.g. a Dictionary) must not crash AppState.handle()'s cast either.
    (:test)
    function malformedKindFieldDoesNotCrash(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.handlePhoneData({ "kind" => { "nested" => true } });
        return true;
    }

    // Both malformed fields at once — still no crash, and AppState.handle() safely no-ops (a
    // non-String kind resolves to null, same as an absent kind).
    (:test)
    function bothMalformedFieldsAtOnceDoesNotCrash(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        AppState.glucose = 111;
        app.handlePhoneData({ "type" => false, "kind" => 42, "bgMgdl" => 999 });
        Test.assertEqualMessage(AppState.glucose, 111,
            "malformed kind ⇒ handle() no-ops (same as an absent kind) — no garbage adopted");
        return true;
    }

    // Positive path: a well-formed eating_sense toggle behaves exactly as before (no crash, and the
    // instanceof guard does not reject a genuine String type).
    (:test)
    function wellFormedEatingSenseToggleStillWorks(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.handlePhoneData({ "type" => "eating_sense", "on" => true });
        app.handlePhoneData({ "type" => "eating_sense", "on" => false });
        return true;
    }

    // Positive path: a well-formed hr_ctl toggle behaves exactly as before.
    (:test)
    function wellFormedHrCtlToggleStillWorks(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.handlePhoneData({ "type" => "hr_ctl", "on" => true });
        return true;
    }

    // Positive path: a well-formed statusRead reply (no `type` field at all, a real `kind`) is still
    // parsed and applied exactly as before — confirms the guards don't reject a genuine message.
    (:test)
    function wellFormedStatusReadStillApplied(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        AppState.glucose = 111;
        app.handlePhoneData({ "kind" => "statusRead", "bgMgdl" => 145 });
        Test.assertEqualMessage(AppState.glucose, 145, "well-formed statusRead is still applied as before");
        return true;
    }
}
