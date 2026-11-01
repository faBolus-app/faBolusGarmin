using Toybox.Lang;
using Toybox.Test;
using Toybox.WatchUi as Ui;

// The watch's calculator against every row of contract/bolus_oracle_fixtures.jsonl, the rows the phone's
// DoseComposerParityTests run: the same dose, rounded down to the pump's step, and the same refusals.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module CalculatorTest {
    function chunk(i as Lang.Number) as Lang.Array {
        var ids = [Rez.JsonData.oracle_0, Rez.JsonData.oracle_1, Rez.JsonData.oracle_2, Rez.JsonData.oracle_3,
                   Rez.JsonData.oracle_4, Rez.JsonData.oracle_5];
        var v = Ui.loadResource(ids[i] as Lang.ResourceId);
        return (v instanceof Lang.Array) ? v : [];
    }

    function num(row as Lang.Array, i as Lang.Number) as Lang.Number? {
        var v = row[i];
        return (v instanceof Lang.Number) ? v : null;
    }

    (:test)
    function everyFixtureRowAgreesWithThePhone(logger as Test.Logger) as Lang.Boolean {
        Support.eq(OracleCount.CHUNKS, 6);
        var rows = 0;
        var checked = 0;
        for (var c = 0; c < OracleCount.CHUNKS; c += 1) {
            var list = chunk(c);
            for (var i = 0; i < list.size(); i += 1) {
                var row = list[i] as Lang.Array;
                rows += 1;
                var carbs = num(row, 0);
                var bg = num(row, 1);
                var ratio = num(row, 2) as Lang.Number;
                var isf = num(row, 3) as Lang.Number;
                var target = num(row, 4) as Lang.Number;
                var iob = num(row, 5) as Lang.Number;
                var oracle = num(row, 6) as Lang.Number;
                // Settings the pump couldn't report aren't a dose input at all (BolusCalculatorSettings.isUsable).
                if (ratio <= 0 || isf <= 0 || target <= 0) { continue; }
                checked += 1;
                // BolusVolume.roundedDown of the oracle's two-decimal total.
                var expected = (oracle / 50) * 50;
                var label = "row " + rows.toString() + ": carbs=" + carbs + " bg=" + bg + " cr=" + ratio + " isf=" + isf
                    + " tgt=" + target + " iob=" + iob + " oracle=" + oracle;
                // A reading outside 40–400 gives no correction, as in the pump's calculator (the flow then
                // refuses to send it; lowAndHighAreSaidUpFront).
                var estimate = Calculator.estimate(carbs == null ? 0 : carbs, bg, ratio, isf, target, iob);
                if (bg != null && (target < 40 || target > 400)) {
                    Support.eqm(estimate, -1, label + " (settings unusable)");
                } else {
                    Support.eqm(estimate, expected, label);
                }
            }
        }
        Support.eq(rows, OracleCount.ROWS);
        Support.eq(rows, 563);
        Test.assertMessage(checked > 400, "checked " + checked.toString());
        return true;
    }

    // A reading outside 40–400 blocks a calculator dose before anything is sent, and says which way.
    (:test)
    function lowAndHighAreSaidUpFront(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 30;
        Status.accept(Support.status({ "glucose" => { "mgdl" => 38, "at" => Support.NOW - 60, "backup" => false } }), Support.NOW);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW), "low");
        Support.eq(BolusFlow.estimate(Support.NOW), -1);
        Support.eq(BolusEntryView.previewLine(Support.NOW), "CGM LOW: use units");
        Status.accept(Support.status({ "glucose" => { "mgdl" => 401, "at" => Support.NOW - 60, "backup" => false } }), Support.NOW);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW), "high");
        // A dose dialed in units still goes.
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 1000;
        Test.assert(BolusFlow.arm(Support.NOW));
        return true;
    }

    // Without fresh settings and IOB there's no number to show.
    (:test)
    function staleInputsGiveNoNumber(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 30;
        Test.assert(BolusFlow.estimate(Support.NOW) > 0);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW + BolusFlow.IOB_SEC), "waiting");
        Support.eq(BolusFlow.estimate(Support.NOW + BolusFlow.IOB_SEC), -1);
        return true;
    }

    (:test)
    function roundingMatchesThePhone(logger as Test.Logger) as Lang.Boolean {
        // Ties away from zero, on the decimal value (faBolusCore dp).
        Support.eq(Calculator.dp(0.125d), 0.13d);
        Support.eq(Calculator.dp(-0.125d), -0.13d);
        Support.eq(Calculator.dp(1.005d), 1.01d);
        Support.eq(Calculator.dp(1.234d), 1.23d);
        // Down to the step, but a hair under a step is that step (BolusVolume.roundedDown).
        Support.eq(Calculator.roundDown(6.0d), 6000);
        Support.eq(Calculator.roundDown(0.149d), 100);
        Support.eq(Calculator.roundDown(0.1499999999d), 150);
        Support.eq(Calculator.roundDown(0.0d), 0);
        Support.eq(Calculator.roundDown(-1.0d), 0);
        return true;
    }
}
