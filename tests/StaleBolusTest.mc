using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// AB4 (Addendum B): the three-way stale-CGM bolus choice. The view/delegate (StaleBolusView/Delegate)
// aren't compiled into the test binary (see test.jungle) — as with HoldView, the safety-critical DECISIONS
// are pure AppState functions mirroring faBolusCore StaleBolusPrompt, so those are what we pin here:
//   • staleBolusShouldWarn — warn iff there IS a reading AND it is stale (fresh / no-reading bypass);
//   • bgForBolus — the include/exclude BG feed (stale is dropped unless the per-attempt flag is set);
//   • computeUnits — the decision end-to-end (include recovers the correction the drop removed);
//   • bolusRequestCarbs — the WIRE round-trip (Option B): the explicit include-stale intent
//     (includeStaleBG => true) AND the stale correction bg (bgMgdl) are on the dict iff the per-attempt
//     flag is set, and NEITHER is present otherwise (never sent as false; carbs-only fail-closed);
//   • staleChoiceProceeds / staleChoiceIncludesBg — cancel composes/sends NOTHING; only include carries BG;
//   • reset — the include flag is per-attempt, never sticky.
// Style mirrors tests/CanBolusTest.mc. AppState is compiled into the test binary (test.jungle).
module StaleBolusTest {

    // Deterministic compose state: a real reading, carbs calculator settings, no IOB. `staleAgeSec` sets
    // how old the reading is (0 = now/fresh); staleSec is pinned so freshness is decided purely by age.
    function seed(glucoseVal as Lang.Number?, staleAgeSec as Lang.Number) as Void {
        AppState.staleSec = 360;                       // 6 min threshold
        AppState.glucose = glucoseVal;
        AppState.readingEpoch = Time.now().value() - staleAgeSec;
        AppState.mode = "carbs";
        AppState.carbsValue = 0;                       // isolate the correction term (no carb component)
        AppState.carbRatio = 10.0;
        AppState.isf = 50;
        AppState.targetBg = 100;
        AppState.iob = 0.0;
        AppState.includeStaleBg = false;               // start every case from the safe default
    }

    // shouldWarn: a stale reading warns; a fresh reading and a missing reading both bypass the prompt.
    (:test)
    function warnsOnlyWhenStaleReadingPresent(logger as Test.Logger) as Lang.Boolean {
        seed(200, 0);                                  // fresh
        Test.assertMessage(!AppState.staleBolusShouldWarn(), "fresh reading ⇒ no warn (composes normally)");

        seed(200, 1000);                               // clearly older than staleSec
        Test.assertMessage(AppState.staleBolusShouldWarn(), "stale reading present ⇒ warn");

        seed(null, 1000);                              // no reading at all
        Test.assertMessage(!AppState.staleBolusShouldWarn(), "no reading ⇒ no warn (just carbs-only)");
        return true;
    }

    // bgForBolus: fresh → the reading; stale → dropped by default, included only with the per-attempt flag;
    // no reading → nil. A nil result is what makes the carb request omit bgMgdl (carbs-only on both sides).
    (:test)
    function bgForBolusHonorsFreshnessAndChoice(logger as Test.Logger) as Lang.Boolean {
        seed(200, 0);
        Test.assertEqualMessage(AppState.bgForBolus(), 200, "fresh ⇒ the reading");

        seed(200, 1000);
        Test.assertMessage(AppState.bgForBolus() == null, "stale + not included ⇒ dropped (nil)");
        AppState.includeStaleBg = true;
        Test.assertEqualMessage(AppState.bgForBolus(), 200, "stale + included ⇒ the reading");

        seed(null, 1000);
        AppState.includeStaleBg = true;                // even if set, nothing to include
        Test.assertMessage(AppState.bgForBolus() == null, "no reading ⇒ nil regardless of the flag");
        return true;
    }

    // The decision end-to-end: with carbsValue 0 the dose is purely the correction. A stale BG dropped ⇒
    // 0 U (carbs-only); including the same stale BG recovers the (200-100)/50 = 2.0 U correction. This is
    // the insulin-INCREASING override the prompt gates behind an explicit, per-attempt choice.
    (:test)
    function computeUnitsReflectsInclude(logger as Test.Logger) as Lang.Boolean {
        seed(200, 1000);                               // stale, not included
        Test.assertEqualMessage(AppState.computeUnits(), 0.0, "stale dropped ⇒ carbs-only (0 U here)");

        AppState.includeStaleBg = true;
        Test.assertEqualMessage(AppState.computeUnits(), 2.0, "stale included ⇒ correction restored");

        seed(200, 0);                                  // fresh always corrects, no flag needed
        Test.assertEqualMessage(AppState.computeUnits(), 2.0, "fresh ⇒ correction applied");
        return true;
    }

    // Option B WIRE round-trip: the carb bolusRequest carries the explicit include-stale INTENT
    // (includeStaleBG => true) alongside the stale correction bg (bgMgdl) ONLY on the per-attempt
    // "include" choice; with the flag off it carries NEITHER — the intent is never sent as false and the
    // stale bg is dropped (host fails closed to carbs-only, today's behavior). Composes exactly as
    // AppState.sendBolusNow does: bg = bgForBolus(), then RemoteComm.bolusRequestCarbs(..., includeStaleBg).
    (:test)
    function bolusRequestCarbsCarriesIncludeStaleIntent(logger as Test.Logger) as Lang.Boolean {
        seed(200, 1000);                               // stale reading present
        AppState.includeStaleBg = true;                // wearer chose "include" this attempt
        var bgInc = AppState.bgForBolus();
        var dInc = RemoteComm.bolusRequestCarbs(AppState.carbsValue, bgInc, 2.0, "r-inc", null, AppState.includeStaleBg);
        Test.assertMessage(dInc.hasKey("includeStaleBG"), "included ⇒ intent key present");
        Test.assertEqualMessage(dInc["includeStaleBG"], true, "included ⇒ includeStaleBG => true");
        Test.assertMessage(dInc.hasKey("bgMgdl"), "included ⇒ correction bg present");
        Test.assertEqualMessage(dInc["bgMgdl"], 200, "included ⇒ bgMgdl is the (stale) reading");

        seed(200, 1000);                               // seed() resets includeStaleBg to false (carbs-only)
        var bgOff = AppState.bgForBolus();
        var dOff = RemoteComm.bolusRequestCarbs(AppState.carbsValue, bgOff, 0.0, "r-off", null, AppState.includeStaleBg);
        Test.assertMessage(!dOff.hasKey("includeStaleBG"), "not included ⇒ NO includeStaleBG key (never false)");
        Test.assertMessage(!dOff.hasKey("bgMgdl"), "not included ⇒ NO correction bg (carbs-only)");
        return true;
    }

    // Cancel is a pure UI back-out: it must NOT proceed to compose/send anything. Only "include" carries
    // the stale BG into the dose. (Pure proxy for the delegate, which isn't in the test binary.)
    (:test)
    function choiceSemanticsMatchPrompt(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppState.staleChoiceProceeds(AppState.STALE_INCLUDE), "include ⇒ proceeds");
        Test.assertMessage(AppState.staleChoiceProceeds(AppState.STALE_CARBS_ONLY), "carbs-only ⇒ proceeds");
        Test.assertMessage(!AppState.staleChoiceProceeds(AppState.STALE_CANCEL), "cancel ⇒ sends NOTHING");

        Test.assertMessage(AppState.staleChoiceIncludesBg(AppState.STALE_INCLUDE), "include ⇒ carries BG");
        Test.assertMessage(!AppState.staleChoiceIncludesBg(AppState.STALE_CARBS_ONLY), "carbs-only ⇒ no BG");
        Test.assertMessage(!AppState.staleChoiceIncludesBg(AppState.STALE_CANCEL), "cancel ⇒ no BG");
        return true;
    }

    // The include flag is per-attempt: reset() (called before every compose) clears it, so a prior
    // "include" can never silently carry into the next bolus.
    (:test)
    function includeFlagIsNeverSticky(logger as Test.Logger) as Lang.Boolean {
        AppState.includeStaleBg = true;
        AppState.reset();
        Test.assertMessage(!AppState.includeStaleBg, "reset ⇒ include flag cleared (per-attempt)");
        return true;
    }
}
