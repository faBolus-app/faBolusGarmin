using Toybox.Lang;
using Toybox.Test;

// P-mmol (Phase 4 "mmol/L display-unit support", D-02): drift-guard pinning the Garmin hand-port
// (AppState.formatMgdl()/displayGlucose()/glucoseUnitLabel()/isfUnitLabel(), plus their pure
// displayGlucoseForUnit()/glucoseUnitLabelForToken() siblings) against the SAME expected outputs the
// canonical Swift funnel asserts (Packages/faBolusCore/Tests/faBolusCoreTests/GlucoseUnitTests.swift —
// formatMmolIsExactlyOneDecimal / roundTripWithinOneMgdl). The value spread (54, 70, 100, 124, 180,
// 250, 400) is the SAME array `roundTripWithinOneMgdl` iterates; the expected 1-decimal strings below
// are hand-transcribed from that funnel (mirror-plus-guard, exactly like RangeColorTest.mc pins
// AppState.rangeColor against faBolusCore.GlucoseThresholds' closed-boundary convention). A future
// drift in either side's rounding/factor breaks this test, not silently. Style mirrors
// tests/RangeColorTest.mc + tests/ClockAnalogTest.mc. AppState is compiled into the test binary
// (test.jungle).
module GlucoseUnitTest {

    // mg/dL path: the plain integer string, byte-identical to the pre-existing "\(mgdl)" call sites —
    // matches faBolusCore.GlucoseUnit.mgdl.format(mgdl:)'s formatMgdlIsPlainInteger expectation.
    (:test)
    function mgdlFormatIsPlainInteger(logger as Test.Logger) as Lang.Boolean {
        var prior = AppState.glucoseUnit;
        AppState.glucoseUnit = "mgdl";
        var spread = [54, 70, 100, 124, 180, 250, 400];
        for (var i = 0; i < spread.size(); i += 1) {
            var v = spread[i];
            Test.assertEqualMessage(AppState.formatMgdl(v), v.toString(), v.toString() + " mg/dL -> plain integer");
        }
        AppState.glucoseUnit = prior;
        return true;
    }

    // mmol path: the SAME value spread + expected 1-decimal strings as
    // GlucoseUnitTests.swift's roundTripWithinOneMgdl/formatMmolIsExactlyOneDecimal (hand-transcribed,
    // cross-checked in the SUMMARY). This is the drift-guard: if the Garmin factor/rounding ever
    // diverges from faBolusCore.GlucoseUnit.mgdlPerMmol (18.0182), this test catches it here.
    (:test)
    function mmolFormatMatchesCanonicalFunnel(logger as Test.Logger) as Lang.Boolean {
        var prior = AppState.glucoseUnit;
        AppState.glucoseUnit = "mmol";
        Test.assertEqualMessage(AppState.formatMgdl(54),  "3.0",  "54 mg/dL -> 3.0 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(70),  "3.9",  "70 mg/dL -> 3.9 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(100), "5.5",  "100 mg/dL -> 5.5 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(124), "6.9",  "124 mg/dL -> 6.9 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(180), "10.0", "180 mg/dL -> 10.0 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(250), "13.9", "250 mg/dL -> 13.9 mmol/L");
        Test.assertEqualMessage(AppState.formatMgdl(400), "22.2", "400 mg/dL -> 22.2 mmol/L");
        AppState.glucoseUnit = prior;
        return true;
    }

    // displayGlucose() itself (the null-guarded caller-facing funnel, not just the raw formatter) —
    // pins the "--" no-reading behavior AND the unit-aware conversion together.
    (:test)
    function displayGlucoseHonorsActiveUnit(logger as Test.Logger) as Lang.Boolean {
        var priorU = AppState.glucoseUnit;
        var priorG = AppState.glucose;

        AppState.glucoseUnit = "mgdl";
        AppState.glucose = 124;
        Test.assertEqualMessage(AppState.displayGlucose(), "124", "mgdl displayGlucose is plain integer");
        AppState.glucose = null;
        Test.assertEqualMessage(AppState.displayGlucose(), "--", "no reading -> --");

        AppState.glucoseUnit = "mmol";
        AppState.glucose = 124;
        Test.assertEqualMessage(AppState.displayGlucose(), "6.9", "mmol displayGlucose is 1-decimal");
        AppState.glucose = null;
        Test.assertEqualMessage(AppState.displayGlucose(), "--", "no reading -> -- regardless of unit");

        AppState.glucoseUnit = priorU;
        AppState.glucose = priorG;
        return true;
    }

    // glucoseUnitLabel()/isfUnitLabel() — the unit-suffix strings every converted call site composes
    // alongside displayGlucose()/formatMgdl() instead of ever hardcoding "mg/dL".
    (:test)
    function unitLabelsMatchExpectedStrings(logger as Test.Logger) as Lang.Boolean {
        var prior = AppState.glucoseUnit;

        AppState.glucoseUnit = "mgdl";
        Test.assertEqualMessage(AppState.glucoseUnitLabel(), "mg/dL", "mgdl glucose label");
        Test.assertEqualMessage(AppState.isfUnitLabel(), "mg/dL/U", "mgdl isf label");

        AppState.glucoseUnit = "mmol";
        Test.assertEqualMessage(AppState.glucoseUnitLabel(), "mmol/L", "mmol glucose label");
        Test.assertEqualMessage(AppState.isfUnitLabel(), "mmol/L/U", "mmol isf label");

        AppState.glucoseUnit = prior;
        return true;
    }

    // The pure, token-parameterized siblings (displayGlucoseForUnit()/glucoseUnitLabelForToken()) used
    // by FaBolusGlanceView's Storage-direct (:glance) context — asserted independently of the instance
    // field so a future edit to one funnel path can't silently diverge from the other.
    (:test)
    function pureTokenVariantsMatchInstanceVariants(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.displayGlucoseForUnit(124, "mgdl"), "124", "pure mgdl format");
        Test.assertEqualMessage(AppState.displayGlucoseForUnit(124, "mmol"), "6.9", "pure mmol format");
        Test.assertEqualMessage(AppState.glucoseUnitLabelForToken("mgdl"), "mg/dL", "pure mgdl label");
        Test.assertEqualMessage(AppState.glucoseUnitLabelForToken("mmol"), "mmol/L", "pure mmol label");
        return true;
    }

    // isValidUnitToken() — the frozen wire-token guard (Pitfall 6): only "mgdl"/"mmol" are recognized;
    // anything else (garbage, legacy display strings) is rejected so handle()/loadPrefs() fail closed.
    (:test)
    function isValidUnitTokenRejectsGarbage(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppState.isValidUnitToken("mgdl"), "mgdl is valid");
        Test.assertMessage(AppState.isValidUnitToken("mmol"), "mmol is valid");
        Test.assertMessage(!AppState.isValidUnitToken("mg/dL"), "display string is NOT a valid wire token");
        Test.assertMessage(!AppState.isValidUnitToken(""), "empty string is not valid");
        Test.assertMessage(!AppState.isValidUnitToken("MMOL"), "wrong case is not valid");
        return true;
    }

    // handle() statusRead parse+persist: strict guard mirrors clockAnalog/garminComplicationDisplay
    // (ClockAnalogTest.mc style) — a recognized token is adopted+persisted; an absent/unrecognized
    // token leaves the last value untouched (T-04-02 fail-closed-to-mgdl via the default + keep-last).
    (:test)
    function handleAdoptsValidTokenAndIgnoresGarbage(logger as Test.Logger) as Lang.Boolean {
        var prior = AppState.glucoseUnit;

        AppState.glucoseUnit = "mgdl";
        AppState.handle({ "kind" => "statusRead", "glucoseDisplayUnit" => "mmol" });
        Test.assertEqualMessage(AppState.glucoseUnit, "mmol", "valid mmol token adopted");

        AppState.handle({ "kind" => "statusRead", "glucoseDisplayUnit" => "mg/dL" });
        Test.assertEqualMessage(AppState.glucoseUnit, "mmol", "garbage token ignored, keeps last (mmol)");

        AppState.handle({ "kind" => "statusRead", "message" => "Connected" });   // no glucoseDisplayUnit key
        Test.assertEqualMessage(AppState.glucoseUnit, "mmol", "absent token ignored, keeps last (mmol)");

        AppState.handle({ "kind" => "statusRead", "glucoseDisplayUnit" => "mgdl" });
        Test.assertEqualMessage(AppState.glucoseUnit, "mgdl", "valid mgdl token adopted back");

        AppState.glucoseUnit = prior;
        return true;
    }
}
