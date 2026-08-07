using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// G5 (Garmin half): the one-time bolus-enable notice must appear on the first bolus-flow open and never
// again — even across restarts. The view/delegate (BolusIntroView/BolusIntroDelegate) aren't compiled
// into the test binary (see test.jungle); the persisted decision lives on AppState, so that is what we
// pin here: bolusIntroShown() reflects a PERSISTED flag that markBolusIntroShown() sets. Each case resets
// the key first so it is deterministic regardless of test order / a prior simulator session. Style
// mirrors tests/CanBolusTest.mc. AppState is compiled into the test binary (test.jungle).
module BolusIntroTest {

    // Not-yet-shown ⇒ false; after marking ⇒ true, and it STAYS true on a second read (persisted, not a
    // one-shot in-memory latch) — that is what guarantees "exactly once for the life of the install".
    (:test)
    function showsExactlyOnce(logger as Test.Logger) as Lang.Boolean {
        Storage.deleteValue(AppState.KEY_BOLUS_INTRO_SHOWN);
        Test.assertMessage(!AppState.bolusIntroShown(), "unshown by default (nothing persisted)");

        AppState.markBolusIntroShown();
        Test.assertMessage(AppState.bolusIntroShown(), "shown after marking");
        Test.assertMessage(AppState.bolusIntroShown(), "still shown on a re-read (persisted, not one-shot)");
        return true;
    }

    // A non-true persisted value (corrupt / legacy) reads as NOT shown — the notice errs toward showing
    // rather than being silently suppressed. Guards the `== true` check in bolusIntroShown().
    (:test)
    function nonTrueValueReadsAsUnshown(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(AppState.KEY_BOLUS_INTRO_SHOWN, "yes");
        Test.assertMessage(!AppState.bolusIntroShown(), "non-boolean ⇒ treated as unshown");
        Storage.setValue(AppState.KEY_BOLUS_INTRO_SHOWN, false);
        Test.assertMessage(!AppState.bolusIntroShown(), "explicit false ⇒ unshown");
        Storage.deleteValue(AppState.KEY_BOLUS_INTRO_SHOWN);   // leave clean for other tests
        return true;
    }
}
