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

    // shortLabelFor's `value` now renders via AppState.formatMgdl instead of a raw
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

    // The four pump-status complication formatters. Each returns
    // { "value" => Numeric or null, "label" => String }, precision matching DetailsView (f2 = %.2f, n0 =
    // toString). Unknown reservoir/battery (-1 sentinel) render an honest "--" with a null numeric slot so
    // no misleading number is published; iob/basal are always real values (0.0 = none, NOT unknown).
    (:test)
    function pumpStatusFieldFormatters(logger as Test.Logger) as Lang.Boolean {
        var iob = BgComplication.iobField(2.35);
        Test.assertEqualMessage(iob["label"], "2.35 U", "IOB label");
        Test.assertMessage(iob["value"] != null, "IOB value present");

        var resv = BgComplication.reservoirField(120.0);
        Test.assertEqualMessage(resv["label"], "120.00 U", "reservoir label");
        Test.assertMessage(resv["value"] != null, "reservoir value present");
        var resvUnknown = BgComplication.reservoirField(-1.0);
        Test.assertEqualMessage(resvUnknown["label"], "--", "reservoir unknown -> --");
        Test.assertMessage(resvUnknown["value"] == null, "reservoir unknown -> null value (no misleading 0)");

        var batt = BgComplication.batteryField(85);
        Test.assertEqualMessage(batt["label"], "85%", "battery label");
        Test.assertMessage(batt["value"] != null, "battery value present");
        var battUnknown = BgComplication.batteryField(-1);
        Test.assertEqualMessage(battUnknown["label"], "--", "battery unknown -> --");
        Test.assertMessage(battUnknown["value"] == null, "battery unknown -> null value");

        var basal = BgComplication.basalField(0.75);
        Test.assertEqualMessage(basal["label"], "0.75 U/hr", "basal label");
        var basalZero = BgComplication.basalField(0.0);
        Test.assertEqualMessage(basalZero["label"], "0.00 U/hr", "basal 0.0 is a REAL value, not --");
        Test.assertMessage(basalZero["value"] != null, "basal 0.0 value present");
        return true;
    }

    // Task 3: on a cold launch / background service the not-yet-populated reservoir/battery start at their
    // -1 unknown defaults and MUST publish "--" (never a misleading 0) until the first statusRead fills a
    // real value. Pins the default-state honesty.
    (:test)
    function coldLaunchUnknownFieldsRenderDashes(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(BgComplication.reservoirField(-1.0)["label"], "--", "default reservoir -> --");
        Test.assertEqualMessage(BgComplication.batteryField(-1)["label"], "--", "default battery -> --");
        return true;
    }

    function sr(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // The phone-selectable complication-slot set. Connect IQ caps an app at 4
    // complications, so glucose (fixed) + three assignable slots; a phone-owned ordered list picks which
    // up-to-3 fields fill them. DEFAULT = IOB + reservoir + battery (glucose is the fixed id 0).
    (:test)
    function complicationSlotsSanitizeAndRoundTrip(logger as Test.Logger) as Lang.Boolean {
        // Sanitizer: allowed tokens only, de-duped, capped at 3, order preserved.
        var s1 = AppState.sanitizeComplicationSlots(["basal", "iob", "iob", "bogus", "battery", "reservoir"]);
        Test.assertEqualMessage(s1.size(), 3, "capped at 3 slots");
        Test.assertEqualMessage(s1[0], "basal", "order preserved (basal first)");
        Test.assertEqualMessage(s1[1], "iob", "de-duped iob kept once");
        Test.assertEqualMessage(s1[2], "battery", "garbage 'bogus' dropped, battery kept");
        var s2 = AppState.sanitizeComplicationSlots(["bogus", "nope"]);
        Test.assertEqualMessage(s2.size(), 0, "all-garbage -> empty (default stands)");

        // Parse + persist + restore round-trip; an empty/garbage list keeps the safe default.
        AppState.garminComplicationSlots = ["iob", "reservoir", "battery"];   // default
        AppState.handle(sr({ "garminComplicationSlots" => ["battery", "basal", "iob"] }));
        Test.assertEqualMessage(AppState.garminComplicationSlots.size(), 3, "adopted 3-slot selection");
        Test.assertEqualMessage(AppState.garminComplicationSlots[0], "battery", "adopted order");
        AppState.handle(sr({ "garminComplicationSlots" => ["bogus"] }));   // all-garbage
        Test.assertEqualMessage(AppState.garminComplicationSlots[0], "battery", "garbage list ignored (keeps last)");

        AppState.garminComplicationSlots = [];   // simulate cold launch
        AppState.loadPrefs();
        Test.assertEqualMessage(AppState.garminComplicationSlots[0], "battery", "restored from Storage");

        // fieldForToken dispatches to the right formatter.
        AppState.iob = 3.0;
        Test.assertEqualMessage(BgComplication.fieldForToken("iob")["label"], "3.00 U", "token iob -> IOB formatter");
        Test.assertEqualMessage(BgComplication.fieldForToken("bogus")["label"], "--", "unknown token -> blank");
        return true;
    }
}
