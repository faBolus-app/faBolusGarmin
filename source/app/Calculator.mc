using Toybox.Lang;

// The watch's bolus calculator, for the live units preview while carbs are dialed. The phone recomputes
// from its own fresh inputs and is the authority: it refuses a request whose estimate differs from its
// own by more than 0.10 U. Both run every row of contract/bolus_oracle_fixtures.jsonl in their tests.
//
// A hand port of faBolusCore's BolusMath.estimate (pumpx2's bolus calculator) and BolusVolume.roundedDown
// (LoopKit's round-down to the pump's 0.05 U step), in Double, from the integers the wire carries.
module Calculator {
    // The plausible CGM range, mg/dL (faBolusCore GlucosePlausibility). Dexcom reports LOW and HIGH
    // outside it, and a calculated dose can't be sent then.
    const GLUCOSE_MIN = 40;
    const GLUCOSE_MAX = 400;
    // The pump's step.
    const STEP_MU = 50;

    function plausible(mgdl as Lang.Number) as Lang.Boolean {
        return mgdl >= GLUCOSE_MIN && mgdl <= GLUCOSE_MAX;
    }

    // Two decimals, ties away from zero: faBolusCore's dp(), which rounds the shortest decimal form of the
    // value. A Double that should be an exact half-cent (1.005) is stored a hair below it, so a tiny nudge
    // gives the decimal answer. The inputs are ratios of small integers, so a value that genuinely lies
    // that close to a half-cent without being on it can't occur.
    function dp(v as Lang.Double) as Lang.Double {
        var negative = v < 0.0d;
        var m = negative ? -v : v;
        var cents = (m * 100.0d + 0.5d + 1.0e-9d).toLong();
        var r = cents.toDouble() / 100.0d;
        return negative ? -r : r;
    }

    // The pump calculator's total in units, unrounded to the step; null when its sanity checks fail (a
    // carb ratio of zero, or a target or correction factor the pump couldn't use with a reading). `glucose`
    // is null for no correction. A reading outside 40–400 mg/dL gives no correction here, as in the
    // pump's calculator; the caller refuses such a dose before getting this far.
    function totalUnits(carbs as Lang.Number, glucose as Lang.Number?, carbRatioMg as Lang.Number,
                        isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number) as Lang.Double? {
        if (carbRatioMg <= 0) { return null; }
        var fromCarbs = dp(carbs.toDouble() * 1000.0d / carbRatioMg.toDouble());
        var fromBG = 0.0d;
        if (glucose != null) {
            if (target < GLUCOSE_MIN || target > GLUCOSE_MAX || isf <= 0) { return null; }
            if (plausible(glucose)) {
                fromBG = dp((glucose - target).toDouble() / isf.toDouble());
            }
        }
        var fromIOB = (iobMU > 0) ? dp(-(iobMU.toDouble() / 1000.0d)) : 0.0d;
        var total = fromCarbs;
        var corr = fromBG + fromIOB;
        if (fromBG >= 0.0d) {
            // At or above target: a correction IOB cancels adds nothing.
            if (corr > 0.0d) { total += corr; }
        } else if (total + corr > 0.0d) {
            // Below target the correction reduces the dose, never below zero.
            total += corr;
        } else {
            total = 0.0d;
        }
        total = dp(total);
        return (total > 0.0d) ? total : 0.0d;
    }

    // Down to the pump's step, in milliunits: never more than the calculator says. A value within a
    // millionth of a unit of a step is that step, so float noise doesn't cost a whole step.
    function roundDown(units as Lang.Double) as Lang.Number {
        if (!(units > 0.0d)) { return 0; }
        var steps = units * 20.0d;
        var nearest = (steps + 0.5d).toLong();
        var whole = ((nearest.toDouble() - steps).abs() <= 1.0e-6d * 20.0d) ? nearest : steps.toLong();
        return (whole * STEP_MU).toNumber();
    }

    // The dose the phone will compute, in milliunits; -1 when the calculator can't give one.
    function estimate(carbs as Lang.Number, glucose as Lang.Number?, carbRatioMg as Lang.Number,
                      isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number) as Lang.Number {
        var total = totalUnits(carbs, glucose, carbRatioMg, isf, target, iobMU);
        return (total == null) ? -1 : roundDown(total);
    }
}
