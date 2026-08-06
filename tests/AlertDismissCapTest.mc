using Toybox.Lang;
using Toybox.Test;

// P13 capability channel: the Garmin remote learns from the phone (schema `supportsRemoteAlertDismiss`)
// whether a REMOTE alert dismissal actually clears on the pump (Mobi) or only snoozes locally (t:slim),
// and labels its alert-dismiss confirmation "Clear" vs "Snooze" accordingly — matching the phone, so a
// t:slim user isn't told an alert cleared on the pump when it only snoozed. These pin the parse (strict
// boolean guard + keep-current on absent) and the pure verb mapping. Style mirrors tests/CanBolusTest.mc.
module AlertDismissCapTest {

    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Default is the safe/honest "Snooze" (false); a Mobi host flips it to "Clear".
    (:test)
    function defaultsToSnoozeThenParsesTrue(logger as Test.Logger) as Lang.Boolean {
        AppState.supportsRemoteAlertDismiss = false;   // fresh-launch default
        Test.assertEqualMessage(AppState.alertActionWord(), "Snooze", "safe default is Snooze");

        AppState.handle(statusRead({ "supportsRemoteAlertDismiss" => true }));
        Test.assertMessage(AppState.supportsRemoteAlertDismiss, "parsed true (Mobi)");
        Test.assertEqualMessage(AppState.alertActionWord(), "Clear", "Mobi ⇒ Clear");
        return true;
    }

    // A t:slim host sets it false ⇒ the verb is "Snooze".
    (:test)
    function tslimHostGivesSnooze(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({ "supportsRemoteAlertDismiss" => true }));
        AppState.handle(statusRead({ "supportsRemoteAlertDismiss" => false }));
        Test.assertMessage(!AppState.supportsRemoteAlertDismiss, "parsed false (t:slim)");
        Test.assertEqualMessage(AppState.alertActionWord(), "Snooze", "t:slim ⇒ Snooze");
        return true;
    }

    // Absent field keeps the last-known value (keep-current idiom); a non-boolean is ignored (never
    // crash or coerce) — guards the `instanceof Lang.Boolean` check in the parse.
    (:test)
    function keepsCurrentOnAbsentAndIgnoresNonBoolean(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({ "supportsRemoteAlertDismiss" => true }));
        AppState.handle(statusRead({ "message" => "Connected" }));   // omits the field
        Test.assertMessage(AppState.supportsRemoteAlertDismiss, "absent ⇒ keep last (still true)");

        AppState.handle(statusRead({ "supportsRemoteAlertDismiss" => "yes" }));   // non-boolean
        Test.assertMessage(AppState.supportsRemoteAlertDismiss, "non-boolean ignored (stays true)");
        return true;
    }
}
