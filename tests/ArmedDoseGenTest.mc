using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// An armed Garmin dose freezes `deliverUnits` at compose and used to survive an intervening
// therapy/policy change (a second bolus could then be accepted by the host once its in-flight mutex
// cleared). The fix stamps an eligibility GENERATION at arm (armBolus, from BolusEntryDelegate.
// captureDose) and bumps `bolusEligibilityGen` whenever the eligibility fingerprint changes on a
// statusRead — so a stale arm is torn down (mustTeardownArmedBolus) and refused at send (sendBolusNow),
// with an independent pump-allowance re-check at send. The safety-critical DECISIONS are pure AppState
// functions, so we pin THOSE — the view/delegate wiring IS test-compiled (test.jungle takes source/app
// wholesale; see its header) but reaches Ui/RemoteComm and is not deterministically drivable headlessly.
// Style mirrors tests/CanBolusTest.mc / tests/HoldTeardownTest.mc. AppState + RemoteComm are test-compiled.
module ArmedDoseGenTest {

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Reset ALL shared state the eligibility-gen path reads so cases are order-independent: the
    // in-flight/delivery vars, the eligibility generations + last-seen fingerprint, and a safe,
    // bolus-eligible set of inputs (read-only off, Garmin bolusing on, pump allowed via the
    // phone-authoritative hostCanBolus flag, no passcode, no known last bolus).
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
        AppState.hostCanBolus = true;          // phone-authoritative allow
        AppState.hostBolusBlockReason = null;
        AppState.bolusPasscodeRequired = false;
        AppState.connection = "Connected";
        AppState.lastBolus = -1.0;
        // keep this baseline forward-compatible with the liveness +
        // elapsed-time-since-arm re-checks landing in sendBolusNow/armBolus — a fresh reply + a zeroed
        // arm-anchor mean every EXISTING case here (none of which are about liveness/elapsed-time) keeps
        // its original pass/fail shape.
        AppState.lastReplyEpoch = Time.now().value();
        AppState.armedAtEpoch = 0;
        AppState.clearUnresolvedTombstone();
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

    // Elapsed-time half: arm, then let the CURRENTLY-armed context age past
    // ARM_CONTEXT_STALE_SEC (simulated directly via armedAtEpoch, mirroring how AppLivenessTest
    // manipulates lastReplyEpoch directly). No intervening statusRead lands — gens still match — yet the
    // direct armContextExpired() re-check at sendBolusNow's final send must refuse it regardless.
    (:test)
    function armContextExpiredRefusesSendEvenWithMatchingGens(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        Test.assertMessage(!AppState.armContextExpired(), "fresh arm ⇒ not yet expired");
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        Test.assertMessage(AppState.armContextExpired(), "arm has now aged past the window");
        Test.assertMessage(AppState.armedEligibilityGen == AppState.bolusEligibilityGen,
            "gens still match — no intervening statusRead ever bumped them");
        Test.assertMessage(!AppState.sendBolusNow(null), "expired arm context ⇒ send refused");
        return true;
    }

    // The fingerprint-fold half: an intervening statusRead landing AFTER the arm has expired changes
    // eligibilityFingerprint()'s "expired" token relative to the last-seen one, bumping the gen and
    // tearing the stale arm down — even though nothing else (readOnly/garminBolusEnabled/pumpBolusAllowed/
    // bolusPasscodeRequired/connection/lastBolus) changed at all.
    (:test)
    function interveningStatusReadAfterExpiryBumpsGenViaFingerprint(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        var g0 = AppState.bolusEligibilityGen;
        AppState.armedAtEpoch = Time.now().value() - (AppState.ARM_CONTEXT_STALE_SEC + 1);
        AppState.handle(statusRead({ "canBolus" => true }));   // otherwise IDENTICAL fingerprint inputs
        Test.assertMessage(AppState.bolusEligibilityGen != g0,
            "the expired-context token flipped ⇒ fingerprint changed ⇒ gen bumped");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "stale arm ⇒ must tear down");
        Test.assertMessage(!AppState.sendBolusNow(null), "stale arm ⇒ send refused");
        return true;
    }

    // Positive companion: an unchanged, in-window arm across a repeat statusRead does NOT bump the gen
    // due to the newly-folded expired/live tokens (they must stay stable across two back-to-back calls).
    (:test)
    function inWindowArmAcrossRepeatStatusReadStillUnchanged(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "canBolus" => true }));
        AppState.armBolus();
        var g0 = AppState.bolusEligibilityGen;
        AppState.handle(statusRead({ "canBolus" => true }));   // still well within ARM_CONTEXT_STALE_SEC
        Test.assertEqualMessage(AppState.bolusEligibilityGen, g0,
            "in-window arm ⇒ the liveness/expired tokens stay stable ⇒ no spurious gen bump");
        Test.assertMessage(AppState.sendBolusNow(null), "in-window, eligible arm ⇒ send still proceeds");
        return true;
    }
}
