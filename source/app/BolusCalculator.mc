using Toybox.Lang;
using Toybox.Math;

// The pure dose-rounding primitive for the watch calculator, lifted out of AppState so it has a
// testable home of its own. Two-decimal rounding, HALF_UP with ties resolved AWAY from zero — the
// same rule as faBolusCore/BolusMath.dp (BigDecimal.setScale(2, HALF_UP)), so every component the
// wrist previews lines up with the oracle-backed host. Monkey C's Math.round is not HALF_UP for
// negatives, so we floor(|v|*100 + 0.5) and re-apply the sign.
module BolusCalculator {
    function dp2(v as Lang.Float) as Lang.Float {
        if (v >= 0.0) { return Math.floor(v * 100.0 + 0.5) / 100.0; }
        return -(Math.floor(-v * 100.0 + 0.5) / 100.0);
    }
}
