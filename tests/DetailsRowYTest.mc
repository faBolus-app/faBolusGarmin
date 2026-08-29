using Toybox.Lang;
using Toybox.Test;

// DetailsView lays its rows out across a vertical band by dividing it into `rowCount-1`
// gaps. A phone-pushed detailsOrder of only opt-in CIQ ids can collapse the visible rows down to just the
// always-appended alerts row (size 1) — `(bottom-top)/(rowCount-1)` would then divide by zero and hand a
// NaN/inf y to drawText. DetailsView.rowY is the PURE helper the onUpdate guard is factored through; this
// pins the contract so a future edit can't silently reintroduce the divide-by-zero:
//   • rowCount==1 → the single row is centered at (top+bottom)/2, a FINITE y (no NaN/inf divide);
//   • rowCount>=2 → evenly spaced: the endpoints land on top and bottom and the interior spacing is uniform.
// DetailsView.mc is compiled into the test binary via test.jungle (it depends only on AppState + SDK
// WatchUi/Graphics, no EatingSense barrel). Style mirrors tests/RangeColorTest.mc + tests/ResponsesTest.mc.
module DetailsRowYTest {

    // FINITE iff |v| is below a large bound. This also catches NaN and +/-inf: NaN.abs() is NaN and
    // (NaN < 1.0e30) is false, and inf.abs() is inf which is not < 1.0e30 — so a divide-by-zero result fails.
    function isFinite(v as Lang.Float) as Lang.Boolean {
        return v.abs() < 1.0e30;
    }

    // rowCount==1 (the degenerate collapsed-layout case): centered, finite, never a NaN/inf divide.
    (:test)
    function singleRowIsCenteredAndFinite(logger as Test.Logger) as Lang.Boolean {
        var y = DetailsView.rowY(1, 0, 0.28, 0.80);
        Test.assertMessage(isFinite(y), "single-row y must be finite (no divide-by-zero NaN/inf)");
        Test.assertMessage((y - 0.54).abs() < 0.0005, "single row centered at (0.28+0.80)/2 = 0.54");
        return true;
    }

    // rowCount>=2: endpoints anchor to top/bottom and the interior spacing is uniform (unchanged behavior).
    (:test)
    function multiRowSpacingIsUniform(logger as Test.Logger) as Lang.Boolean {
        // 3 rows across [0.0, 1.0] ⇒ 0.0, 0.5, 1.0 (step 0.5).
        Test.assertMessage((DetailsView.rowY(3, 0, 0.0, 1.0) - 0.0).abs() < 0.0005, "3-row i0 = top (0.0)");
        Test.assertMessage((DetailsView.rowY(3, 1, 0.0, 1.0) - 0.5).abs() < 0.0005, "3-row i1 = midpoint (0.5)");
        Test.assertMessage((DetailsView.rowY(3, 2, 0.0, 1.0) - 1.0).abs() < 0.0005, "3-row i2 = bottom (1.0)");

        // The production band [0.28, 0.80] with 2 rows ⇒ the endpoints exactly.
        Test.assertMessage((DetailsView.rowY(2, 0, 0.28, 0.80) - 0.28).abs() < 0.0005, "first of two rows sits at top");
        Test.assertMessage((DetailsView.rowY(2, 1, 0.28, 0.80) - 0.80).abs() < 0.0005, "second of two rows sits at bottom");

        // Uniform spacing: consecutive gaps are equal for rowCount>=2 (here 4 rows across the real band).
        var gap1 = DetailsView.rowY(4, 1, 0.28, 0.80) - DetailsView.rowY(4, 0, 0.28, 0.80);
        var gap2 = DetailsView.rowY(4, 2, 0.28, 0.80) - DetailsView.rowY(4, 1, 0.28, 0.80);
        Test.assertMessage((gap1 - gap2).abs() < 0.0005, "row spacing is uniform");
        return true;
    }
}
