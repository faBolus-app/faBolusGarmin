using Toybox.Lang;
using Toybox.Test;

// Insulin Stacking Guard (SG1 + SG3a, task #93) — a Monkey C hand-port of faBolusCore.StackingGuard
// (Packages/faBolusCore/Sources/faBolusCore/StackingGuard.swift). These tests pin the SAME facts the
// Swift StackingGuardTests do: the calc-override trigger (entered > recommended, glucose above the
// pump's OWN op-115 target), the recommendedUnits==0 full-override branch (no ratio ever computed), the
// §13 Rule-1 displaysNumericDose guard, the SG3a escalation ladder's exact boundaries
// (confirmExtraOverrideRatio/reenterOverrideRatio default 1.5/2.0), the SG2 max-proximity floor, and the
// verbatim contract copy. DISPLAY-ONLY: every function returns a string to show (or "") — nothing here
// gates a bolus, and `computeUnits()`/`deliverUnits` are never mutated by any test here. Style mirrors
// tests/ControllerDisclosureTest.mc / tests/StaleBolusTest.mc. AppState is compiled into the test binary
// (test.jungle).
module StackingGuardTest {

    // Deterministic baseline: Carbs mode with a real calculator (carbRatio synced), glucose above the
    // pump's own target, no IOB, no max-bolus disclosed unless a test raises entered near/above it.
    // `mode`/`carbsValue`/`unitsValue` are left for each test to set explicitly (the override signal is
    // keyed on the CURRENT mode's computeUnits() vs. the mode-independent recommendedUnits()).
    function seed() as Void {
        AppState.mode = "carbs";
        AppState.carbsValue = 0;
        AppState.unitsValue = 0.0;
        AppState.carbRatio = 10.0;    // 10 g/U
        AppState.isf = 0;             // isolate the carbs-only term unless a test opts into correction
        AppState.targetBg = 100;
        AppState.iob = 0.0;
        AppState.glucose = 200;       // above target by default (SG1's glucose gate)
        AppState.includeStaleBg = false;
        AppState.maxUnits = 25.0;     // a real (non-triggering) pump max unless a test lowers it
        AppState.sgConfirmExtraOverrideRatio = 1.5;
        AppState.sgReenterOverrideRatio = 2.0;
    }

    // Carbs mode: computeUnits() and recommendedUnits() run the IDENTICAL carbCorrectionTotal() math, so
    // entered == recommended by construction, at ANY carbs size — SG can never fire in Carbs mode on
    // this watch (there is no separate manual-override step within Carbs mode, unlike Units mode below).
    (:test)
    function carbsModeNeverFiresRegardlessOfSize(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 90;    // 9.0 U — a large carb bolus, still exactly the calculator's number
        Test.assertEqualMessage(AppState.computeUnits(), AppState.recommendedUnits(),
            "carbs mode: entered == recommended by construction");
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "carbs mode never discloses SG1");
        Test.assertEqualMessage(AppState.sgDisclosureLine(), "", "carbs mode never discloses SG3a");
        return true;
    }

    // Units mode: the wearer picks unitsValue independent of the carbs-based recommendation — the real
    // override scenario SG1 discloses. carbsValue=50 @ 10 g/U ⇒ recommendedUnits()=5.0 U; entering 6.0 U
    // in Units mode is a genuine override (glucose above target).
    (:test)
    function unitsModeOverrideFiresSG1(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 50;                 // recommendedUnits() = 5.0 U
        AppState.mode = "units";
        AppState.unitsValue = 6.0;                // entered > recommended
        Test.assertEqualMessage(AppState.recommendedUnits(), 5.0, "recommendedUnits reads the carb calc");
        Test.assertEqualMessage(AppState.computeUnits(), 6.0, "units mode: entered is the raw unitsValue");
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(),
            "You're entering more than the pump's calculator suggested.", "SG1 fires on the override");
        return true;
    }

    // Exact-match is NOT an override, at any size (mirrors calcOverride's own false-positive guard).
    (:test)
    function exactMatchNeverFiresRegardlessOfSize(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 200;                // recommendedUnits() = 20.0 U
        AppState.mode = "units";
        AppState.unitsValue = 20.0;               // entered == recommended exactly
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "exact match never fires");
        return true;
    }

    // SG1's glucose gate: absent or at/below target never fires, even with a clear override.
    (:test)
    function glucoseGateSuppressesSG1(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 50; AppState.mode = "units"; AppState.unitsValue = 9.0;
        AppState.glucose = 100;                   // == target, not strictly above
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "at target ⇒ no SG1");
        AppState.glucose = 99;
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "below target ⇒ no SG1");
        AppState.glucose = null;
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "no reading ⇒ no SG1");
        AppState.glucose = 101;
        Test.assertMessage(!AppState.sgCalcOverrideLine().equals(""), "strictly above target ⇒ SG1 can fire");
        return true;
    }

    // §13 Rule-1: no calculator settings synced yet (carbRatio<=0) ⇒ displaysNumericDose is false ⇒ SG1
    // never fires, however large the entered dose — never cite an override against a placeholder guess.
    (:test)
    function noCalculatorSettingsSuppressesSG1(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbRatio = 0.0;
        AppState.mode = "units"; AppState.unitsValue = 20.0;
        Test.assertMessage(!AppState.sgDisplaysNumericDose(), "no carb ratio ⇒ displaysNumericDose false");
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(), "", "no calc settings ⇒ SG1 suppressed");
        return true;
    }

    // recommendedUnits==0 full-override branch — checked BEFORE any ratio, mirroring calcOverride's own
    // zero-recommendation guard (no NaN/inf, never a divide-by-zero in the escalation ratio either).
    (:test)
    function zeroRecommendationGoesToFullOverrideThenReenter(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 0;                  // recommendedUnits() = 0.0 (carbs=0, no correction)
        AppState.mode = "units"; AppState.unitsValue = 3.0;
        Test.assertEqualMessage(AppState.recommendedUnits(), 0.0, "zero carbs ⇒ zero recommendation");
        Test.assertEqualMessage(AppState.sgCalcOverrideLine(),
            "You're entering 3.00 U — the pump's calculator did not suggest a dose.",
            "SG1 full-override message, verbatim");
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "You're entering 3.00 U with no calculator suggestion to compare against — please re-enter to confirm.",
            "SG3a escalates zero-recommendation straight to reenter, verbatim");
        Test.assertMessage(AppState.sgDisclosureIsCaution(), "reenter tier is a caution");
        return true;
    }

    // SG3a escalation ladder boundaries: disclose below confirmExtraOverrideRatio, confirmExtra at/above
    // it (but below reenterOverrideRatio), reenter at/above reenterOverrideRatio. recommendedUnits()=5.0
    // (carbsValue=50 @ 10 g/U) throughout; only unitsValue (entered) varies.
    (:test)
    function escalationLadderStepsAtExactBoundaries(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 50;                 // recommendedUnits() = 5.0 U
        AppState.mode = "units";

        AppState.unitsValue = 6.0;                // ratio 1.2 — below 1.5
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "You're entering more than the pump's calculator suggested.",
            "ratio 1.2 → disclose tier (reuses SG1's own message)");
        Test.assertMessage(!AppState.sgDisclosureIsCaution(), "disclose tier is not a caution");

        AppState.unitsValue = 7.5;                // ratio 1.5 — boundary (>=)
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "This dose is well above what the pump's calculator suggested — please confirm before delivering.",
            "ratio 1.5 boundary → confirmExtra");
        Test.assertMessage(AppState.sgDisclosureIsCaution(), "confirmExtra tier is a caution");

        AppState.unitsValue = 9.95;               // ratio 1.99 — just below 2.0
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "This dose is well above what the pump's calculator suggested — please confirm before delivering.",
            "ratio 1.99 → still confirmExtra");

        AppState.unitsValue = 10.0;               // ratio 2.0 — boundary (>=)
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "This dose is far above what the pump's calculator suggested — please re-enter to confirm.",
            "ratio 2.0 boundary → reenter");
        Test.assertMessage(AppState.sgDisclosureIsCaution(), "reenter tier is a caution");
        return true;
    }

    // SG2's max-proximity floor: reaching the pump's OWN reported max forces at least confirmExtra even
    // at a modest override ratio that alone would only disclose.
    (:test)
    function maxProximityFloorsAtConfirmExtra(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 50;                 // recommendedUnits() = 5.0 U
        AppState.mode = "units";
        AppState.maxUnits = 6.0;                  // pump's own max, deliberately low
        AppState.unitsValue = 6.0;                // ratio 1.2 (would be disclose alone) AND == max
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "This dose is well above what the pump's calculator suggested — please confirm before delivering.",
            "at pump max ⇒ confirmExtra even at a modest ratio");

        AppState.maxUnits = 25.0;                 // remove the floor — same ratio now only discloses
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "You're entering more than the pump's calculator suggested.",
            "same modest ratio without the max floor ⇒ disclose only");
        return true;
    }

    // The §13 owner-confirmable cut-points are read live, not baked-in literals — mutating them changes
    // where the SAME entered/recommended pair lands on the ladder.
    (:test)
    function boundariesTrackTheMutableVarsNotHardcodedLiterals(logger as Test.Logger) as Lang.Boolean {
        seed();
        AppState.carbsValue = 50; AppState.mode = "units"; AppState.unitsValue = 6.0;   // ratio 1.2
        Test.assertMessage(!AppState.sgDisclosureLine().equals(
            "This dose is well above what the pump's calculator suggested — please confirm before delivering."),
            "ratio 1.2 is below the DEFAULT confirmExtra cut-point");

        AppState.sgConfirmExtraOverrideRatio = 1.1;   // lower the cut-point below the same 1.2 ratio
        Test.assertEqualMessage(AppState.sgDisclosureLine(),
            "This dose is well above what the pump's calculator suggested — please confirm before delivering.",
            "same ratio now crosses the LOWERED cut-point");
        return true;
    }
}
