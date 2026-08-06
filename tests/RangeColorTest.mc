using Toybox.Lang;
using Toybox.Test;
using Toybox.Graphics as Gfx;

// P13c-1: AppState.rangeColor uses the CLOSED clinical band convention (mirroring
// faBolusCore.GlucoseThresholds and the phone's coloring), so the color agrees with the reported TIR
// at the exact integer boundaries: 180 colors in-range (green), 250 colors high (yellow), > 250 urgent.
// Pins those edges so a future one-sided edit to the bands is caught here. Style mirrors tests/CanBolusTest.mc.
module RangeColorTest {

    (:test)
    function closedConventionAtBoundaries(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.rangeColor(69),  Gfx.COLOR_RED,    "69 -> low (red)");
        Test.assertEqualMessage(AppState.rangeColor(70),  Gfx.COLOR_GREEN,  "70 -> in-range (green)");
        Test.assertEqualMessage(AppState.rangeColor(120), Gfx.COLOR_GREEN,  "120 -> in-range (green)");
        Test.assertEqualMessage(AppState.rangeColor(180), Gfx.COLOR_GREEN,  "180 -> in-range (closed upper bound)");
        Test.assertEqualMessage(AppState.rangeColor(181), Gfx.COLOR_YELLOW, "181 -> high (yellow)");
        Test.assertEqualMessage(AppState.rangeColor(250), Gfx.COLOR_YELLOW, "250 -> high (not urgent)");
        Test.assertEqualMessage(AppState.rangeColor(251), Gfx.COLOR_ORANGE, "251 -> urgent (orange)");
        Test.assertEqualMessage(AppState.rangeColor(400), Gfx.COLOR_ORANGE, "400 -> urgent (orange)");
        return true;
    }
}
