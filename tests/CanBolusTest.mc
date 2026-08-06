using Toybox.Lang;
using Toybox.Test;

// P12 group D: the Garmin START-bolus gate now prefers the host's semantic `canBolus` flag (schema),
// with the connection-string derivation only as a fallback for an older host — instead of treating a
// substring match of the localized display string ("Delivering…") as load-bearing safety logic. These
// pin: the parse of `canBolus` / `bolusBlockReason`, the host-flag-over-string precedence in
// pumpBolusAllowed(), and the reason-token → display-text mapping. pumpBolusAllowed() deliberately
// EXCLUDES phone reachability (System.getDeviceSettings().phoneConnected, not controllable in the
// simulator), so it is deterministic; canBolus() ANDs reachability in on-device. Style mirrors
// tests/HistoryEpochsTest.mc. AppState + RemoteComm are compiled into the test binary (test.jungle).
module CanBolusTest {

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // The host's `canBolus` flag is parsed and is AUTHORITATIVE over the connection string. (The
    // contradictory string/flag combos below can't come from a correct host — which computes canBolus
    // from the same pump state it renders into the string — they only prove the flag wins.)
    (:test)
    function hostFlagOverridesString(logger as Test.Logger) as Lang.Boolean {
        // String says "Delivering…" (string-derivation → blocked), host says canBolus=true → flag wins.
        AppState.handle(statusRead({ "message" => "Delivering…", "canBolus" => true }));
        Test.assertMessage(AppState.hostCanBolus == true, "parsed canBolus=true");
        Test.assertMessage(AppState.pumpBolusAllowed(), "host flag true overrides the string");

        // String says "Connected" (string-derivation → allowed), host says canBolus=false → flag wins.
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => false,
                                     "bolusBlockReason" => "accessDenied" }));
        Test.assertMessage(!AppState.pumpBolusAllowed(), "host flag false overrides the string");
        Test.assertEqualMessage(AppState.hostBolusBlockReason, "accessDenied", "parsed reason token");
        return true;
    }

    // Older host (never sends `canBolus`) → fall back to deriving from the connection string.
    (:test)
    function fallsBackToStringWhenNoHostFlag(logger as Test.Logger) as Lang.Boolean {
        AppState.hostCanBolus = null;   // an older host that never sent the field
        AppState.handle(statusRead({ "message" => "Connected" }));
        Test.assertMessage(AppState.pumpBolusAllowed(), "Connected + no host flag → allowed via string");

        AppState.hostCanBolus = null;
        AppState.handle(statusRead({ "message" => "Disconnected" }));
        Test.assertMessage(!AppState.pumpBolusAllowed(), "Disconnected + no host flag → blocked via string");

        AppState.hostCanBolus = null;
        AppState.handle(statusRead({ "message" => "Delivering…" }));
        Test.assertMessage(!AppState.pumpBolusAllowed(), "in-flight + no host flag → blocked via string");
        return true;
    }

    // A non-boolean `canBolus` must be ignored (leaves the last value / stays null) — never crash or
    // coerce. Guards the `instanceof Lang.Boolean` check in the parse.
    (:test)
    function ignoresNonBooleanCanBolus(logger as Test.Logger) as Lang.Boolean {
        AppState.hostCanBolus = null;
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => "yes" }));
        Test.assertMessage(AppState.hostCanBolus == null, "string canBolus ignored (stays null)");
        Test.assertMessage(AppState.pumpBolusAllowed(), "so it falls back to the string (Connected → allowed)");
        return true;
    }

    // The reason token maps to short display text (pure, deterministic — no reachability dependency).
    (:test)
    function reasonTextMapsTokens(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.bolusReasonText("pumpNotLinked"), "Pump not connected", "pumpNotLinked");
        Test.assertEqualMessage(AppState.bolusReasonText("bolusInFlight"), "Bolus in progress", "bolusInFlight");
        Test.assertEqualMessage(AppState.bolusReasonText("accessDenied"), "Read-only", "accessDenied");
        Test.assertEqualMessage(AppState.bolusReasonText("remoteUnreachable"), "Phone not connected", "remoteUnreachable");
        Test.assertEqualMessage(AppState.bolusReasonText(null), "", "null token → empty");
        Test.assertEqualMessage(AppState.bolusReasonText("bogus"), "", "unknown token → empty");
        return true;
    }
}
