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

    // P15 §2.3: the phone's `garminBolusEnabled` gates canBolus() (fail-closed) and the block label.
    // canBolus() ANDs phoneReachable() (not sim-controllable), so we lean on the deterministic facts:
    //   • disabled ⇒ canBolus() is false no matter what reachability is (false && anything == false);
    //   • the block label is the disabled reason WHEN reachable, else the phone-not-connected reason —
    //     asserted in BOTH reachability states so the test is deterministic either way.
    (:test)
    function garminBolusEnabledGatesBolus(logger as Test.Logger) as Lang.Boolean {
        // Bolusing DISABLED on the phone (default/fail-closed), even though the host says canBolus=true.
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => true,
                                     "garminBolusEnabled" => false }));
        Test.assertMessage(!AppState.garminBolusEnabled, "parsed garminBolusEnabled=false");
        Test.assertMessage(!AppState.canBolus(), "disabled ⇒ canBolus() false regardless of reachability");
        if (RemoteComm.phoneReachable()) {
            Test.assertEqualMessage(AppState.bolusBlockLabel(), "Bolusing off (enable on phone)",
                "reachable + disabled ⇒ the disabled reason");
        } else {
            Test.assertEqualMessage(AppState.bolusBlockLabel(), "Phone not connected",
                "unreachable ⇒ the phone reason wins first");
        }

        // Now ENABLE it (host allows, pump connected). The block label is never the disabled one; when the
        // phone is reachable a bolus is possible (empty label + canBolus() true).
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => true,
                                     "garminBolusEnabled" => true }));
        Test.assertMessage(AppState.garminBolusEnabled, "parsed garminBolusEnabled=true");
        Test.assertMessage(!AppState.bolusBlockLabel().equals("Bolusing off (enable on phone)"),
            "enabled ⇒ never the disabled reason");
        if (RemoteComm.phoneReachable()) {
            Test.assertMessage(AppState.canBolus(), "enabled + reachable + host-allowed ⇒ canBolus()");
            Test.assertEqualMessage(AppState.bolusBlockLabel(), "", "canBolus ⇒ empty block label");
        }
        return true;
    }

    // A non-boolean `garminBolusEnabled` must be ignored — the safe default (false) stands (fail-closed),
    // mirroring ignoresNonBooleanCanBolus. Guards the `instanceof Lang.Boolean` check in the parse.
    (:test)
    function ignoresNonBooleanGarminBolusEnabled(logger as Test.Logger) as Lang.Boolean {
        AppState.garminBolusEnabled = false;   // start from the safe default
        AppState.handle(statusRead({ "message" => "Connected", "garminBolusEnabled" => "yes" }));
        Test.assertMessage(!AppState.garminBolusEnabled, "non-boolean ignored (stays false, fail-closed)");
        return true;
    }

    // MainView's disabled glance bolus button now surfaces AppState.bolusBlockLabel() beneath it,
    // the same way BolusOnlyView already does. That presentation is only useful if the label is never
    // empty while the button is disabled — pin that invariant, including the ultimate "Unavailable"
    // fallback (host withholds the bolus with NO reason token, pump link up, not delivering), the one
    // bolusBlockLabel() branch no other test exercises. canBolus() ANDs phoneReachable() (not
    // sim-controllable), so the non-empty check is guarded on it and stays deterministic either way
    // (unreachable ⇒ the phone reason, still non-empty).
    (:test)
    function blockLabelNeverEmptyWhenBlocked(logger as Test.Logger) as Lang.Boolean {
        AppState.hostBolusBlockReason = null;   // clear any token leaked from a prior test (handle() never resets it)
        // Pump link up + Garmin bolusing on, but the host withholds the bolus (canBolus=false) with no
        // reason token → the disabled branch MainView reaches, falling through to "Unavailable". handle()
        // stamps lastReplyEpoch, so appLive() is true (no "Reconnecting…").
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => false,
                                     "garminBolusEnabled" => true }));
        Test.assertMessage(!AppState.canBolus(), "host withholds ⇒ canBolus() false (button disabled)");
        var why = AppState.bolusBlockLabel();
        if (RemoteComm.phoneReachable()) {
            Test.assertMessage(!why.equals(""), "blocked + reachable ⇒ a reason is always shown, never a silent gray button");
            Test.assertEqualMessage(why, "Unavailable", "no token + pump up + live ⇒ the Unavailable fallback");
        } else {
            Test.assertEqualMessage(why, "Phone not connected", "unreachable ⇒ the phone reason (still non-empty)");
        }
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
