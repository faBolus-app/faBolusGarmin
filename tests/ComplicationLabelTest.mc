using Toybox.Lang;
using Toybox.Test;

// P16 §1.3 (fail-graceful): the numeric BG complication cannot render "--" in its numeric :value slot,
// so a stale glucose would otherwise look current on any face. BgComplication.shortLabelFor is the text
// sub-surface where staleness is made honest, so this pins the label matrix so a future one-sided edit
// can't silently reintroduce the "stale looks current" bug:
//   • stringTrend  → "--" when stale (the whole value is replaced);
//   • numericColor → keeps the number (so the face can range-color it) but appends an explicit stale
//     marker, so a string-rendering face can't show a stale reading as current;
//   • fresh (both modes) → "<value><arrow>", with NO stale marker.
// Style mirrors tests/RangeColorTest.mc.
module ComplicationLabelTest {

    (:test)
    function staleAndFreshLabels(logger as Test.Logger) as Lang.Boolean {
        // stringTrend: stale replaces the value with the honest "--"; fresh shows value + arrow.
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", true,  true),  "--",   "stringTrend stale -> --");
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", false, true),  "124^", "stringTrend fresh -> value+arrow");

        // numericColor: keep the number for range color, but a stale reading MUST carry a marker so a
        // string-rendering face can't read it as current; fresh shows value + arrow with no marker.
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", true,  false), "124 old", "numericColor stale -> value + explicit stale marker");
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", false, false), "124^",     "numericColor fresh -> value+arrow, no marker");

        // The numeric value itself is always preserved in the label (the "reads 0" fix must stand).
        Test.assertMessage(BgComplication.shortLabelFor(90, "", true,  false).find("90") == 0, "numericColor stale label still leads with the reading");
        // Stale marker present iff stale (guards a future one-sided edit to shortLabelFor).
        Test.assertMessage(BgComplication.shortLabelFor(90, "", true,  false).find("old") != null, "numericColor stale label carries the stale marker");
        Test.assertMessage(BgComplication.shortLabelFor(90, "", false, false).find("old") == null, "numericColor fresh label has NO stale marker");
        return true;
    }

    // C5-03 (V-Audit): shortLabelFor's `value` now renders via AppState.formatMgdl instead of a raw
    // `.toString()`, so this text sub-surface honors the phone's selected unit. This test pins that
    // conversion actually happens (default "mgdl" is unchanged, byte-for-byte, by design — see
    // staleAndFreshLabels above, which never sets glucoseUnit and still expects "124"/"90"). Saves/
    // restores AppState.glucoseUnit around the mutation, mirroring GlucoseUnitTest.mc's own idiom, so
    // this test can't leak state into any test that runs after it.
    (:test)
    function mmolUnitConversionRoutesThroughFormatMgdl(logger as Test.Logger) as Lang.Boolean {
        var prior = AppState.glucoseUnit;
        AppState.glucoseUnit = "mmol";
        // 124 mg/dL / 18.0182 = 6.88185... -> "%.1f" -> "6.9" (same 1-decimal convention as
        // AppState.displayGlucoseForUnit / the Swift GlucoseUnit.format(mgdl:) it mirrors).
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", false, true),  "6.9^",   "stringTrend fresh mmol -> converted value+arrow");
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", false, false), "6.9^",   "numericColor fresh mmol -> converted value+arrow");
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", true,  false), "6.9 old", "numericColor stale mmol -> converted value + stale marker");
        // stale + stringTrend stays "--" regardless of unit (the value is replaced, not converted).
        Test.assertEqualMessage(BgComplication.shortLabelFor(124, "^", true,  true),  "--",     "stringTrend stale mmol -> still --");
        AppState.glucoseUnit = prior;
        return true;
    }
}
