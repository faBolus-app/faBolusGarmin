using Toybox.Lang;
using Toybox.Test;

// VA-07: an armed Garmin dose freezes `deliverUnits` at compose and used to survive an intervening
// therapy/policy change (a second bolus could then be accepted by the host once its in-flight mutex
// cleared). The fix stamps an eligibility GENERATION at arm (armBolus, from BolusEntryDelegate.
// captureDose) and bumps `bolusEligibilityGen` whenever the eligibility fingerprint changes on a
// statusRead — so a stale arm is torn down (mustTeardownArmedBolus) and refused at send (sendBolusNow),
// with an independent pump-allowance re-check at send. The safety-critical DECISIONS are pure AppState
// functions (the view/delegate wiring isn't in the test binary — see test.jungle), so we pin THOSE.
// Style mirrors tests/CanBolusTest.mc / tests/HoldTeardownTest.mc. AppState + RemoteComm are test-compiled.
module ArmedDoseGenTest {

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Reset ALL shared state VA-07 reads so cases are order-independent regardless of prior tests: the
    // in-flight/delivery vars, the eligibility generations + last-seen fingerprint, and a safe,
    // bolus-eligible set of inputs (read-only off, Garmin bolusing on, pump allowed via the connection
    // string, no passcode, no known last bolus).
    function baseline() as Void {
        AppState.status = null;
        AppState.message = null;
        AppState.pendingRequestId = null;
        AppState.sawPhoneBolusing = false;
        AppState.outcomeSentEpoch = 0;
        AppState.bolusEligibilityGen = 0;
        AppState.armedEligibilityGen = 0;
        AppState._prevEligibilityFp = null;
        AppState.readOnly = false;
        AppState.garminBolusEnabled = true;
        AppState.hostCanBolus = null;          // derive pumpBolusAllowed() from the connection string
        AppState.hostBolusBlockReason = null;
        AppState.bolusPasscodeRequired = false;
        AppState.connection = "Connected";
        AppState.lastBolus = -1.0;
    }

    // Unchanged eligibility across a repeat statusRead ⇒ no gen bump, no teardown, send proceeds (true).
    // (sendBolusNow returns true whether or not the phone is reachable — outOfRange is still a completed,
    // status-owning outcome — so this assertion is deterministic in the simulator.)
    (:test)
    function unchangedEligibilityAllowsSend(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));   // establish the baseline fingerprint
        AppState.armBolus();                                    // snapshot the generation
        var g0 = AppState.bolusEligibilityGen;
        AppState.handle(statusRead({ "canBolus" => true }));   // identical fingerprint → must NOT bump
        Test.assertEqualMessage(AppState.bolusEligibilityGen, g0, "unchanged fingerprint ⇒ no gen bump");
        Test.assertMessage(AppState.armedEligibilityGen == AppState.bolusEligibilityGen, "gens still equal");
        Test.assertMessage(!AppState.mustTeardownArmedBolus(), "unchanged eligibility ⇒ no teardown");
        Test.assertMessage(AppState.sendBolusNow(null), "eligible arm ⇒ send proceeds (true)");
        return true;
    }

    // Arm, then a bolus starts on the pump mid-arm (host canBolus flips false / pumpBolusAllowed changes)
    // ⇒ the fingerprint changes, the gen bumps past the arm, and the send is refused.
    (:test)
    function armThenInterveningBolusRefusesSend(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        // An intervening bolus started elsewhere → the pump no longer allows a new one.
        AppState.handle(statusRead({ "canBolus" => false, "bolusBlockReason" => "bolusInFlight" }));
        Test.assertMessage(AppState.bolusEligibilityGen != AppState.armedEligibilityGen,
            "intervening pump-state change bumped the gen past the arm");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "stale arm ⇒ must tear down");
        Test.assertMessage(!AppState.sendBolusNow(null), "stale arm ⇒ send refused (false)");
        return true;
    }

    // Arm, then the phone flips passcode-required on ⇒ fingerprint change ⇒ invalidated.
    (:test)
    function passcodeRequiredChangeInvalidates(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        AppState.handle(statusRead({ "canBolus" => true, "bolusPasscodeRequired" => true }));
        Test.assertMessage(AppState.bolusPasscodeRequired, "passcode-required flipped on");
        Test.assertMessage(AppState.bolusEligibilityGen != AppState.armedEligibilityGen, "gen bumped");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "passcode change ⇒ tear down");
        Test.assertMessage(!AppState.sendBolusNow(null), "passcode change ⇒ send refused");
        return true;
    }

    // Arm, then an OBSERVED completed bolus (lastBolus changes) ⇒ fingerprint change ⇒ invalidated.
    (:test)
    function lastBolusChangeInvalidates(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        AppState.handle(statusRead({ "canBolus" => true, "lastBolusUnits" => 3.0 }));
        Test.assertMessage(AppState.lastBolus == 3.0, "last bolus updated to the observed amount");
        Test.assertMessage(AppState.bolusEligibilityGen != AppState.armedEligibilityGen, "gen bumped");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "observed bolus ⇒ tear down");
        Test.assertMessage(!AppState.sendBolusNow(null), "observed bolus ⇒ send refused");
        return true;
    }

    // The gens can MATCH (no intervening statusRead) yet the pump not permit a bolus — sendBolusNow's own
    // pumpBolusAllowed() re-check must still refuse. This is the at-send defense independent of the gen.
    (:test)
    function pumpNotAllowedRecheckAtSend(logger as Test.Logger) as Lang.Boolean {
        baseline();
        // Arm while the pump is NOT allowing a bolus (disconnected), but Garmin policy IS enabled.
        AppState.handle(statusRead({ "canBolus" => false, "bolusBlockReason" => "pumpNotLinked" }));
        AppState.armBolus();
        Test.assertMessage(!AppState.pumpBolusAllowed(), "pump not allowed at arm");
        Test.assertMessage(!AppState.bolusPolicyDisabled(), "but Garmin policy is enabled (not policy-blocked)");
        Test.assertMessage(AppState.armedEligibilityGen == AppState.bolusEligibilityGen,
            "gens match (no intervening statusRead)");
        Test.assertMessage(!AppState.mustTeardownArmedBolus(),
            "gens+policy look valid ⇒ mustTeardown does NOT fire (the at-send re-check is the guard)");
        Test.assertMessage(!AppState.sendBolusNow(null), "pump-not-allowed re-check at send ⇒ refused");
        return true;
    }
}
