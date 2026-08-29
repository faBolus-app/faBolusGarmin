using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// Glucose plot height customization:
// Garmin is in the SMALL-SCREEN group (same as the Apple Watch) — AppState.handle()'s statusRead
// parse resolves the small-screen OVERRIDE (glucosePlotFloorSmall/CeilingSmall) first, falling back
// to the shared/phone-scoped bounds (glucosePlotFloor/Ceiling) when no override is on the wire, and
// persists the resolved pair to Storage so a cold launch keeps it. This module pins that parse +
// persist contract, the floor<ceiling invariant enforcement, and the gridline
// (AppState.plotGridlines) within-domain guarantee. CgmView.mc (the actual draw code) is NOT compiled
// into the test binary (see test.jungle) — the contract we pin here is the testable math AppState
// exposes: plotFloor/plotCeiling themselves, and plotGridlines(). Style mirrors
// tests/ClockAnalogTest.mc + tests/GlucoseUnitTest.mc. AppState is compiled into the test binary.
module GlucosePlotBoundsTest {
    const FLOOR_KEY = "plotFloor";
    const CEILING_KEY = "plotCeiling";

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Reset AppState + Storage to the compile-time defaults before/after each test so no test leaks
    // state into the next (mirrors ClockAnalogTest.ignoresNonBoolean's own cleanup discipline).
    function resetToDefaults() as Void {
        AppState.plotFloor = 40;
        AppState.plotCeiling = 300;
        Storage.deleteValue(FLOOR_KEY);
        Storage.deleteValue(CEILING_KEY);
    }

    // A statusRead carrying ONLY the shared/phone-scoped bounds (no override) adopts + persists them.
    (:test)
    function sharedBoundsOnlyAdoptsAndPersistsThem(logger as Test.Logger) as Lang.Boolean {
        resetToDefaults();
        AppState.handle(statusRead({ "glucosePlotFloor" => 50, "glucosePlotCeiling" => 400 }));
        Test.assertEqualMessage(AppState.plotFloor, 50, "shared floor adopted");
        Test.assertEqualMessage(AppState.plotCeiling, 400, "shared ceiling adopted");
        Test.assertEqualMessage(Storage.getValue(FLOOR_KEY), 50, "shared floor persisted");
        Test.assertEqualMessage(Storage.getValue(CEILING_KEY), 400, "shared ceiling persisted");
        resetToDefaults();
        return true;
    }

    // A statusRead carrying BOTH the shared bounds AND the small-screen override prefers the
    // override — Garmin must never fall back to the shared pair when an override exists.
    (:test)
    function smallScreenOverridePreferredOverShared(logger as Test.Logger) as Lang.Boolean {
        resetToDefaults();
        AppState.handle(statusRead({
            "glucosePlotFloor" => 40, "glucosePlotCeiling" => 300,
            "glucosePlotFloorSmall" => 50, "glucosePlotCeilingSmall" => 400
        }));
        Test.assertEqualMessage(AppState.plotFloor, 50, "override floor preferred over shared");
        Test.assertEqualMessage(AppState.plotCeiling, 400, "override ceiling preferred over shared");
        resetToDefaults();
        return true;
    }

    // An out-of-range value (outside numRange's [1,1000] guard) or a fully-absent pair leaves the
    // last-persisted/default value untouched (legacy-safe) — never adopts a corrupt/garbage bound.
    (:test)
    function outOfRangeOrAbsentLeavesSafeDefault(logger as Test.Logger) as Lang.Boolean {
        resetToDefaults();
        AppState.handle(statusRead({ "message" => "Connected" }));   // no plot-bound keys at all
        Test.assertEqualMessage(AppState.plotFloor, 40, "absent pair keeps default floor");
        Test.assertEqualMessage(AppState.plotCeiling, 300, "absent pair keeps default ceiling");

        // Adopt a real pair first, then confirm an out-of-range push doesn't disturb it.
        AppState.handle(statusRead({ "glucosePlotFloor" => 50, "glucosePlotCeiling" => 350 }));
        AppState.handle(statusRead({ "glucosePlotFloor" => 2000, "glucosePlotCeiling" => 400 }));   // floor out of [1,1000]
        Test.assertEqualMessage(AppState.plotFloor, 50, "out-of-range floor ignored, keeps last-adopted");
        Test.assertEqualMessage(AppState.plotCeiling, 350, "ceiling also untouched (one-unit: both or neither)");
        resetToDefaults();
        return true;
    }

    // A resolved pair that violates the floor<ceiling min-gap invariant is dropped to the
    // compile-time defaults rather than applied — never a corrupt/inverted domain.
    (:test)
    function invertedPairDropsToDefaults(logger as Test.Logger) as Lang.Boolean {
        resetToDefaults();
        AppState.handle(statusRead({ "glucosePlotFloor" => 50, "glucosePlotCeiling" => 350 }));   // valid, non-default
        AppState.handle(statusRead({ "glucosePlotFloor" => 400, "glucosePlotCeiling" => 250 }));   // inverted
        Test.assertEqualMessage(AppState.plotFloor, 40, "inverted pair drops floor to default");
        Test.assertEqualMessage(AppState.plotCeiling, 300, "inverted pair drops ceiling to default");
        resetToDefaults();
        return true;
    }

    // Every computed gridline for a sample non-default combo (floor 50 / ceiling 400) falls
    // STRICTLY inside the domain — never at the floor or ceiling edge itself.
    (:test)
    function gridlinesFallStrictlyWithinDomainForSampleCombo(logger as Test.Logger) as Lang.Boolean {
        var lines = AppState.plotGridlines(50, 400);
        Test.assertMessage(lines.size() >= 2, "at least 2 gridlines for a 350 mg/dL-wide domain");
        for (var i = 0; i < lines.size(); i += 1) {
            var v = lines[i];
            Test.assertMessage(v > 50, "gridline " + v.toString() + " is strictly greater than the floor");
            Test.assertMessage(v < 400, "gridline " + v.toString() + " is strictly less than the ceiling");
        }
        return true;
    }

    // Same within-domain guarantee for the smallest legal preset combo (floorOptions.max=50 ×
    // ceilingOptions.min=250, faBolusCore.GlucosePlotScale) — the tightest span the presets allow.
    (:test)
    function gridlinesFallStrictlyWithinDomainForTightestCombo(logger as Test.Logger) as Lang.Boolean {
        var lines = AppState.plotGridlines(50, 250);
        Test.assertMessage(lines.size() >= 2, "at least 2 gridlines for the tightest preset combo");
        for (var i = 0; i < lines.size(); i += 1) {
            var v = lines[i];
            Test.assertMessage(v > 50, "gridline " + v.toString() + " is strictly greater than the floor");
            Test.assertMessage(v < 250, "gridline " + v.toString() + " is strictly less than the ceiling");
        }
        return true;
    }

    // The default combo (40..300, today's hardcoded view) still gets sane in-domain gridlines.
    (:test)
    function gridlinesFallStrictlyWithinDomainForDefaultCombo(logger as Test.Logger) as Lang.Boolean {
        var lines = AppState.plotGridlines(40, 300);
        Test.assertMessage(lines.size() >= 2, "at least 2 gridlines for the default 40..300 combo");
        for (var i = 0; i < lines.size(); i += 1) {
            var v = lines[i];
            Test.assertMessage(v > 40, "gridline " + v.toString() + " is strictly greater than the floor");
            Test.assertMessage(v < 300, "gridline " + v.toString() + " is strictly less than the ceiling");
        }
        return true;
    }
}
