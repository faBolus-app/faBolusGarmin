using Toybox.Lang;
using Toybox.Test;

// FaBolusApp.handlePhoneData (extracted from onPhoneMessage — see tests/
// StatusReplyTest.mc's header for why the extraction was needed: Comm.PhoneAppMessage has no
// test-constructible instance) reads the inbound `kind` field with an instanceof-guard before the
// cast — a non-null, non-String `kind` (a malformed/hostile wire dict) used to hit an UNGUARDED cast
// and would crash the phone-message handler (a watch-side denial-of-service). AppState.handle()'s own
// `data["kind"] as Lang.String?` (a second, independent unguarded-cast site) is guarded the same way,
// reusing the existing strCap() helper.
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

    // Positive path: a well-formed, non-statusRead `kind` (a bolusStatus echo) still applies — the
    // instanceof guard does not reject a genuine String kind, and this branch bypasses the statusRead
    // correlation gate entirely (mirrors tests/StatusReplyTest.mc's nonStatusReadReplyNeverGated).
    (:test)
    function wellFormedBolusStatusStillApplied(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        AppState.pendingRequestId = "rid-1";
        AppState.status = "delivering";
        app.handlePhoneData({ "kind" => "bolusStatus", "requestId" => "rid-1", "status" => "delivered" });
        Test.assertEqualMessage(AppState.status, "delivered", "well-formed bolusStatus is still applied");
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
