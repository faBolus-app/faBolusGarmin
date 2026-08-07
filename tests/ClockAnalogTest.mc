using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// P15 E4b (Garmin half): the clock screen's analog-vs-digital choice is now PHONE-DRIVEN — parsed from
// the statusRead reply and persisted under the "clockAnalog" Storage key that ClockView.analog() reads,
// replacing the old on-watch tap toggle. ClockView/ClockDelegate are NOT compiled into the test binary
// (see test.jungle), so the contract we pin here is exactly the parse: AppState.handle() persists a
// boolean clockAnalog to Storage, ignores a non-boolean (strict `instanceof Lang.Boolean` guard), and
// leaves the last-persisted value untouched when the key is absent (so a cold launch keeps the last
// phone-pushed choice). Style mirrors tests/CanBolusTest.mc + tests/BolusIntroTest.mc. AppState is
// compiled into the test binary (test.jungle).
module ClockAnalogTest {
    const KEY = "clockAnalog";

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // true / false both persist to the Storage key ClockView.analog() reads (phone = source of truth).
    (:test)
    function persistsBoolean(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({ "clockAnalog" => true }));
        Test.assertMessage(Storage.getValue(KEY) == true, "clockAnalog=true persisted");
        AppState.handle(statusRead({ "clockAnalog" => false }));
        Test.assertMessage(Storage.getValue(KEY) == false, "clockAnalog=false persisted");
        return true;
    }

    // Absent from the reply ⇒ the last-persisted value is left untouched (a cold launch keeps the last
    // phone-pushed choice; ClockView falls back to its digital default only when nothing was ever set).
    (:test)
    function absentLeavesPersisted(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(KEY, true);
        AppState.handle(statusRead({ "message" => "Connected" }));   // reply carries no clockAnalog
        Test.assertMessage(Storage.getValue(KEY) == true, "absent ⇒ prior persisted value kept");

        Storage.deleteValue(KEY);
        AppState.handle(statusRead({ "message" => "Connected" }));   // still no clockAnalog
        Test.assertMessage(Storage.getValue(KEY) == null, "absent + never set ⇒ stays unset (digital default)");
        return true;
    }

    // A non-boolean must be ignored (strict `instanceof Lang.Boolean` guard) — the last-persisted value
    // stands, mirroring the ignoresNonBoolean* parse tests. Guards against coercing garbage into the key.
    (:test)
    function ignoresNonBoolean(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(KEY, true);
        AppState.handle(statusRead({ "clockAnalog" => "yes" }));
        Test.assertMessage(Storage.getValue(KEY) == true, "string clockAnalog ignored (kept true)");

        Storage.setValue(KEY, false);
        AppState.handle(statusRead({ "clockAnalog" => 1 }));
        Test.assertMessage(Storage.getValue(KEY) == false, "numeric clockAnalog ignored (kept false)");

        Storage.deleteValue(KEY);   // leave the key clean for other tests
        return true;
    }
}
