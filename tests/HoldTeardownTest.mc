using Toybox.Lang;
using Toybox.Test;

// P15 §2.3 / G4: when the phone flips read-only ON or Garmin bolusing OFF, an already-armed HoldView
// must tear its primed confirm down. The field-clearing is view-local (HoldView.disabledMidArm), but the
// safety-critical DECISION — "must I tear this down right now?" — is a pure function on AppState, so it's
// what we pin here. (test.jungle takes source/app WHOLESALE — see its own header — so HoldView IS
// compiled in; the reason to pin the pure decision is that disabledMidArm() reaches Ui, not absence.)
// These assert the two
// phone-pushed policy flags gate the teardown, and crucially that an IN-FLIGHT bolus is never torn down.
// Style mirrors tests/CanBolusTest.mc. AppState is compiled into the test binary (test.jungle).
module HoldTeardownTest {

    // Restore the safe, bolus-enabled baseline (read-only off, Garmin bolusing on, nothing in flight) so
    // each case starts deterministically regardless of test order / prior state. Also SYNC the
    // eligibility generations (armBolus() snapshots the current gen) so the new stale-arm dimension is
    // neutral here — these cases exercise the POLICY dimension of mustTeardownArmedBolus(); the eligibility
    // dimension is pinned in ArmedDoseGenTest. Without this sync a prior test's statusRead could leave
    // bolusEligibilityGen ahead of the never-armed armedEligibilityGen and spuriously force a teardown.
    function armedBaseline() as Void {
        AppState.readOnly = false;
        AppState.garminBolusEnabled = true;
        AppState.status = null;
        AppState.armBolus();   // armedEligibilityGen = bolusEligibilityGen → no stale-arm teardown
    }

    // Enabled + not read-only + pre-delivery ⇒ nothing to tear down.
    (:test)
    function noTeardownWhenEnabled(logger as Test.Logger) as Lang.Boolean {
        armedBaseline();
        Test.assertMessage(!AppState.bolusPolicyDisabled(), "enabled + not read-only ⇒ policy allows");
        Test.assertMessage(!AppState.mustTeardownArmedBolus(), "enabled ⇒ no teardown");
        return true;
    }

    // Phone flips READ-ONLY on mid-arm ⇒ tear the primed confirm down.
    (:test)
    function readOnlyFlipTearsDown(logger as Test.Logger) as Lang.Boolean {
        armedBaseline();
        AppState.readOnly = true;
        Test.assertMessage(AppState.bolusPolicyDisabled(), "read-only ⇒ policy disabled");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "read-only + pre-delivery ⇒ tear down");
        return true;
    }

    // Phone turns GARMIN BOLUSING off mid-arm ⇒ tear the primed confirm down.
    (:test)
    function bolusDisabledFlipTearsDown(logger as Test.Logger) as Lang.Boolean {
        armedBaseline();
        AppState.garminBolusEnabled = false;
        Test.assertMessage(AppState.bolusPolicyDisabled(), "Garmin bolusing off ⇒ policy disabled");
        Test.assertMessage(AppState.mustTeardownArmedBolus(), "bolus off + pre-delivery ⇒ tear down");
        return true;
    }

    // CRITICAL: once a request is out (status != null), a policy flip must NOT tear anything down — the
    // in-flight bolus / its outcome screen is owned by the delivery flow and a cancel is a deliberate act.
    (:test)
    function inFlightBolusNeverTornDown(logger as Test.Logger) as Lang.Boolean {
        armedBaseline();
        AppState.readOnly = true;             // policy IS disabled...
        AppState.status = "delivering";       // ...but a bolus is already in flight
        Test.assertMessage(AppState.bolusPolicyDisabled(), "policy disabled");
        Test.assertMessage(!AppState.mustTeardownArmedBolus(), "in-flight ⇒ never torn down");
        AppState.status = "cancelling";
        Test.assertMessage(!AppState.mustTeardownArmedBolus(), "mid-cancel ⇒ never torn down");
        AppState.status = null;               // restore for later tests
        return true;
    }
}
