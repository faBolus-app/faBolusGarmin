using Toybox.Lang;
using Toybox.Test;
using Toybox.Math;

// Pins BolusCalculator.dp2 directly (no AppState construction): two-decimal rounding, HALF_UP with
// ties resolved AWAY from zero, the same rule as faBolusCore/BolusMath.dp. The critical case is the
// exact half-cent tie and its negative mirror — Monkey C's Math.round rounds negatives toward zero,
// so a drift there (or a lost sign) fails loudly here. Assertions compare the rounded cent value
// (Math.round(result*100)) rather than a raw Float literal so single-precision representation of the
// quotient can't make an exact answer flaky. Style mirrors tests/GlucoseUnitTest.mc + tests/StaleBolusTest.mc.
// BolusCalculator is compiled into the test binary (test.jungle globs source/app).
module BolusCalculatorTest {

    // Two-decimal result expressed as a whole number of cents; the inputs to Math.round here are always
    // integer-valued Floats (dp2 already rounded), so no tie behavior of Math.round is exercised.
    function cents(v as Lang.Float) as Lang.Number {
        return Math.round(BolusCalculator.dp2(v) * 100.0).toNumber();
    }

    // The exact .005 tie (0.125 is representable in binary, so 0.125*100 = 12.5 exactly): rounds AWAY
    // from zero to 0.13, and its negative mirror to -0.13 (NOT toward zero). This is the whole reason
    // dp2 exists instead of Math.round.
    (:test)
    function halfCentTieRoundsAwayFromZero(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(cents(0.125), 13, "0.125 ties up to 0.13 (away from zero)");
        Test.assertEqualMessage(cents(-0.125), -13, "-0.125 ties to -0.13 (away from zero, not toward it)");
        Test.assertEqualMessage(cents(2.125), 213, "2.125 ties up to 2.13");
        return true;
    }

    // Below and above the half boundary: ordinary directed rounding, positive and negative.
    (:test)
    function nonTieRoundsToNearest(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(cents(1.234), 123, "1.234 rounds down to 1.23");
        Test.assertEqualMessage(cents(1.239), 124, "1.239 rounds up to 1.24");
        Test.assertEqualMessage(cents(-1.234), -123, "-1.234 rounds to -1.23 (magnitude nearest)");
        return true;
    }

    // Zero is a fixed point (and never signed).
    (:test)
    function zeroIsUnchanged(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(cents(0.0), 0, "0.0 -> 0");
        return true;
    }
}
