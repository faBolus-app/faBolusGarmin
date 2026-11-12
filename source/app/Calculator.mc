using Toybox.Lang;

// The watch's bolus calculator, for the live units preview while carbs are dialed. The phone recomputes
// from its own fresh inputs and is the authority: it refuses a request whose estimate differs from its
// own by more than 0.10 U. Both run every row of contract/bolus_oracle_fixtures.jsonl in their tests.
//
// A hand port of faBolusCore's BolusMath.estimate (pumpx2's bolus calculator) and BolusVolume.roundedDown
// (LoopKit's round-down to the pump's 0.05 U step), in Double, from the integers the wire carries.
module Calculator {
    // The glucose the calculator corrects from, mg/dL (faBolusCore CalculatorGlucose). Outside it a
    // calculated dose can't be sent.
    const GLUCOSE_MIN = 20;
    const GLUCOSE_MAX = 600;
    // The target the pump's calculator can use, mg/dL; outside it there's no calculated dose at all.
    const TARGET_MIN = 40;
    const TARGET_MAX = 400;
    // The pump's step.
    const STEP_MU = 50;

    function correctable(mgdl as Lang.Number) as Lang.Boolean {
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
    // is null for no correction. A reading outside 20–600 mg/dL gives no correction here, as on the
    // phone; the caller refuses such a dose before getting this far.
    function totalUnits(carbs as Lang.Number, glucose as Lang.Number?, carbRatioMg as Lang.Number,
                        isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number) as Lang.Double? {
        if (carbRatioMg <= 0) { return null; }
        return fromFood(dp(carbs.toDouble() * 1000.0d / carbRatioMg.toDouble()), glucose, isf, target, iobMU);
    }

    // The same total with carbs off on the pump: the food entry is insulin, `foodMU`, the food's part as it
    // is, with no carb ratio (faBolusCore BolusMath.estimate(foodUnits:)), as Tandem's apps take it then.
    function foodTotalUnits(foodMU as Lang.Number, glucose as Lang.Number?, isf as Lang.Number,
                            target as Lang.Number, iobMU as Lang.Number) as Lang.Double? {
        return fromFood(dp((foodMU > 0 ? foodMU : 0).toDouble() / 1000.0d), glucose, isf, target, iobMU);
    }

    function fromFood(fromCarbs as Lang.Double, glucose as Lang.Number?, isf as Lang.Number, target as Lang.Number,
                      iobMU as Lang.Number) as Lang.Double? {
        var fromBG = 0.0d;
        if (glucose != null) {
            if (target < TARGET_MIN || target > TARGET_MAX || isf <= 0) { return null; }
            if (correctable(glucose)) {
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

    // The carbs' share and the total, before rounding down, or null: for the confirm screen's split, whose
    // correction is the total less the carbs' share, as the phone's review shows it.
    function parts(carbs as Lang.Number, glucose as Lang.Number?, carbRatioMg as Lang.Number,
                   isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number) as Lang.Array<Lang.Double>? {
        var total = totalUnits(carbs, glucose, carbRatioMg, isf, target, iobMU);
        if (total == null) { return null; }
        return [dp(carbs.toDouble() * 1000.0d / carbRatioMg.toDouble()), total];
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

    // Under this the reduction always applies, with no question, and the screen says to eat carbs.
    const LOW_GLUCOSE = 70;

    // Why the dose is what it is, as the phone says it (faBolusCore CalculatorMessage), in a few words; null
    // for nothing to say. Under 70, what the low did to the dose of `doseMU` for `carbs`: "lowNoCarbs",
    // "lowNone" (no bolus) or "lowReduced". "reduced": below target, the dose reduced to nothing; "iobLow":
    // on target with IOB, or IOB that may take the glucose under 70; "iobCovers": above target, IOB more
    // than the correction. As Tandem's app chooses them.
    function message(glucose as Lang.Number?, isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number,
                     carbs as Lang.Number, doseMU as Lang.Number) as Lang.String? {
        if (glucose == null || !correctable(glucose) || isf <= 0 || target < TARGET_MIN || target > TARGET_MAX) {
            return null;
        }
        if (glucose < LOW_GLUCOSE) {
            if (carbs <= 0) { return "lowNoCarbs"; }
            return doseMU <= 0 ? "lowNone" : "lowReduced";
        }
        if (glucose < target) { return doseMU <= 0 ? "reduced" : null; }
        if (iobMU <= 0) { return null; }
        if (glucose == target) { return "iobLow"; }
        var fromBG = dp((glucose - target).toDouble() / isf.toDouble());
        var fromIOB = dp(-(iobMU.toDouble() / 1000.0d));
        if (fromBG + fromIOB > 0.0d) { return null; }
        // The IOB would take the glucose under 70 once it acts.
        var dropsLow = glucose.toDouble() - iobMU.toDouble() / 1000.0d * isf.toDouble() < LOW_GLUCOSE.toDouble();
        return dropsLow ? "iobLow" : "iobCovers";
    }

    function messageText(key as Lang.String) as Lang.String {
        if (key.equals("lowNoCarbs")) { return "Glucose low: eat carbs"; }
        if (key.equals("lowNone")) { return "Glucose low: no bolus"; }
        if (key.equals("lowReduced")) { return "Glucose low: dose reduced"; }
        if (key.equals("reduced")) { return "Below target: no bolus"; }
        if (key.equals("iobLow")) { return "IOB may drop you low"; }
        return "IOB covers the correction";
    }

    // The dose the phone will compute, in milliunits; -1 when the calculator can't give one.
    function estimate(carbs as Lang.Number, glucose as Lang.Number?, carbRatioMg as Lang.Number,
                      isf as Lang.Number, target as Lang.Number, iobMU as Lang.Number) as Lang.Number {
        var total = totalUnits(carbs, glucose, carbRatioMg, isf, target, iobMU);
        return (total == null) ? -1 : roundDown(total);
    }

    // The same with carbs off: `foodMU` of insulin for the food.
    function estimateFood(foodMU as Lang.Number, glucose as Lang.Number?, isf as Lang.Number, target as Lang.Number,
                          iobMU as Lang.Number) as Lang.Number {
        var total = foodTotalUnits(foodMU, glucose, isf, target, iobMU);
        return (total == null) ? -1 : roundDown(total);
    }

    // The food's share and the total with carbs off, as `parts` gives them with carbs.
    function foodParts(foodMU as Lang.Number, glucose as Lang.Number?, isf as Lang.Number, target as Lang.Number,
                       iobMU as Lang.Number) as Lang.Array<Lang.Double>? {
        var total = foodTotalUnits(foodMU, glucose, isf, target, iobMU);
        if (total == null) { return null; }
        return [dp((foodMU > 0 ? foodMU : 0).toDouble() / 1000.0d), total];
    }
}
