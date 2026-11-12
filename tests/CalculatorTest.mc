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
                // A reading outside 20–600 gives no correction, as on the phone (the flow then refuses to
                // send it; lowAndHighAreSaidUpFront).
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

    // A reading outside 20–600 blocks a calculator dose before anything is sent, and says which way.
    (:test)
    function lowAndHighAreSaidUpFront(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 30;
        Status.accept(Support.status({ "glucose" => { "mgdl" => 19, "at" => Support.NOW - 60, "backup" => false } }), Support.NOW);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW), "low");
        Support.eq(BolusFlow.estimate(Support.NOW), -1);
        Support.eq(BolusEntryView.previewLine(Support.NOW), "Too low for a carb dose");
        Status.accept(Support.status({ "glucose" => { "mgdl" => 601, "at" => Support.NOW - 60, "backup" => false } }), Support.NOW);
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
        Support.eq(BolusFlow.calculatorBlock(Support.NOW + Prefs.iobStaleSeconds()), "waiting");
        Support.eq(BolusFlow.estimate(Support.NOW + Prefs.iobStaleSeconds()), -1);
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

    // The golden status with the CGM at `mgdl`, a minute old: 45 g at 7.5 g/U is 6.00 U for carbs, ISF 40,
    // target 110, IOB 1.25 U.
    function reading(mgdl as Lang.Number) as Void {
        Support.connected();
        Status.accept(Support.status({ "glucose" => { "mgdl" => mgdl, "at" => Support.NOW - 60, "backup" => false } }),
                      Support.NOW);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        BolusFlow.foodMU = 0;
    }

    // Asked from 70 up when correcting changes the dose; carbs only says so, with the reading it was for, so
    // the phone holds the answer to that reading.
    (:test)
    function theCorrectionIsAskedAndMayBeDeclined(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        Test.assert(BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.estimate(Support.NOW), 8250);
        Support.eq(CorrectionView.label("apply"), "Corrected");
        Support.eq(CorrectionView.dose("apply"), "8.25 U");
        Support.eq(CorrectionView.label("carbsOnly"), "Carbs only");
        Support.eq(CorrectionView.dose("carbsOnly"), "6.00 U");
        BolusFlow.declineCorrection = true;
        Support.eq(BolusFlow.estimate(Support.NOW), 6000);
        Test.assert(BolusFlow.arm(Support.NOW));
        // The confirm screen names the answer, so a mistap shows before anything goes.
        Support.eq(BolusFlow.armedChoice(), "Carbs only");
        Test.assert(BolusFlow.send(Support.NOW));
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Support.eq(p["estimateMU"] as Lang.Object?, 6000);
        Support.eq(p["declineCorrection"] as Lang.Object?, true);
        Support.eq(p["glucoseMgdl"] as Lang.Object?, 250);
        // The phone asks for a confirmation: the same dose armed again still names the answer.
        var o = Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_confirm);
        o["requestId"] = BolusFlow.requestId() as Lang.String;
        Test.assert(BolusFlow.onOutcome(o, Support.NOW + 2));
        Test.assert(BolusFlow.armConfirmed(Support.NOW + 3));
        Support.eq(BolusFlow.armedChoice(), "Carbs only");
        BolusFlow.forget();
        // Below target, from 70 up, the reduction may be declined too.
        reading(90);
        Test.assert(BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(CorrectionView.label("apply"), "Reduced");
        Support.eq(CorrectionView.dose("apply"), "4.25 U");
        Support.eq(CorrectionView.label("carbsOnly"), "Not reduced");
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(BolusFlow.armedChoice(), "Reduced");
        return true;
    }

    // New doses while the question shows: noticed once, and the change screen holds until the user has seen
    // it. A reading that ends the question isn't asked about.
    (:test)
    function aQuestionWhoseDosesChangeSaysSo(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        var v = new CorrectionView(Support.NOW);
        Test.assert(!v.noticeChange(Support.NOW));
        Test.assert(!v.changed);
        reading(270);
        Test.assert(v.noticeChange(Support.NOW));
        Test.assert(!v.noticeChange(Support.NOW));
        Test.assert(v.changed);
        v.seen();
        Test.assert(!v.changed);
        reading(60);
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        return true;
    }

    // Under 70 the reduction always applies: no question, a declined answer doesn't count, and the screen
    // says to eat carbs.
    (:test)
    function underSeventyTheReductionApplies(logger as Test.Logger) as Lang.Boolean {
        reading(60);
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        BolusFlow.declineCorrection = true;
        Support.eq(BolusFlow.estimate(Support.NOW), 3500);
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(BolusFlow.armedChoice(), null);
        Support.eq(BolusFlow.message(Support.NOW), "Glucose low: dose reduced");
        BolusFlow.carbs = 0;
        Support.eq(BolusFlow.message(Support.NOW), "Glucose low: eat carbs");
        // 5 g is 0.67 U, and the low takes 2.50 U off: no bolus.
        BolusFlow.carbs = 5;
        Support.eq(BolusFlow.message(Support.NOW), "Glucose low: no bolus");
        BolusFlow.carbs = 45;
        Test.assert(BolusFlow.arm(Support.NOW));
        Test.assert(BolusFlow.send(Support.NOW));
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Support.eq(p["declineCorrection"] as Lang.Object?, null);
        Support.eq(p["glucoseMgdl"] as Lang.Object?, 60);
        return true;
    }

    // No question when correcting changes nothing, and the messages the phone gives.
    (:test)
    function theMessagesFollowThePhone(logger as Test.Logger) as Lang.Boolean {
        reading(142);
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.message(Support.NOW), "IOB covers the correction");
        reading(110);
        Support.eq(BolusFlow.message(Support.NOW), "IOB may drop you low");
        // While the question is to come, the screen says so and shows both doses.
        reading(90);
        Support.eq(BolusFlow.message(Support.NOW), "Reduction asked next");
        Support.eq(BolusEntryView.previewLine(Support.NOW), "4.25 U or 6.00 U");
        Support.eq(Calculator.messageText(Calculator.message(90, 40, 110, 1250, 0, 0) as Lang.String),
                   "Below target: no bolus");
        // A reduction that leaves a dose isn't explained, as in Tandem's app.
        Support.eq(Calculator.message(90, 40, 110, 1250, 45, 4250), null);
        // Above target, IOB covering the correction and enough to take 120 under 70: it may drop low.
        Support.eq(Calculator.message(120, 40, 110, 1500, 45, 6000), "iobLow");
        Support.eq(Calculator.message(120, 40, 110, 500, 45, 6000), "iobCovers");
        reading(250);
        Support.eq(BolusFlow.message(Support.NOW), "Correction asked next");
        Support.eq(BolusEntryView.previewLine(Support.NOW), "8.25 U or 6.00 U");
        reading(180);
        Support.eq(BolusFlow.message(Support.NOW), "Correction asked next");
        // Each answer must be a dose. A reduction to nothing (5 g is 0.65 U) isn't asked about, and the screen
        // says why; nor is a correction with no carbs, which has no carbs-only dose.
        reading(90);
        BolusFlow.carbs = 5;
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.message(Support.NOW), "Below target: no bolus");
        reading(250);
        BolusFlow.carbs = 0;
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        // Over the remote limit (10 U in the golden status) neither dose can go: no question, no message.
        reading(250);
        BolusFlow.carbs = 90;
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.message(Support.NOW), null);
        Support.eq(BolusEntryView.previewLine(Support.NOW), "Over the 10.00 U limit");
        Support.eq(Calculator.message(null, 40, 110, 1250, 45, 6000), null);
        Support.eq(Calculator.message(150, 40, 110, 0, 45, 7000), null);
        return true;
    }

    // The question gone, the screen says what that means for the dose, and never "no correction needed" when
    // there's no dose to go on to.
    (:test)
    function whenTheQuestionGoesTheScreenSaysWhatItMeans(logger as Test.Logger) as Lang.Boolean {
        reading(142);
        Support.eq(CorrectionView.goneMeaning(Support.NOW), "No correction needed");
        Test.assert(!CorrectionView.noDoseToSee(Support.NOW));
        reading(60);
        Support.eq(CorrectionView.goneMeaning(Support.NOW), "Dose reduced");
        // A reduction from 70 up that takes the whole dose.
        reading(90);
        BolusFlow.carbs = 5;
        Support.eq(CorrectionView.goneMeaning(Support.NOW), "No bolus");
        Test.assert(CorrectionView.noDoseToSee(Support.NOW));
        reading(250);
        BolusFlow.carbs = 90;
        Support.eq(CorrectionView.goneMeaning(Support.NOW), "Over the 10.00 U limit");
        Test.assert(CorrectionView.noDoseToSee(Support.NOW));
        reading(650);
        Support.eq(CorrectionView.goneMeaning(Support.NOW), "Too high for a carb dose");
        Test.assert(CorrectionView.noDoseToSee(Support.NOW));
        reading(250);
        Support.eq(CorrectionView.goneMeaning(Support.NOW + Prefs.iobStaleSeconds()), "Waiting for the pump");
        Test.assert(CorrectionView.noDoseToSee(Support.NOW + Prefs.iobStaleSeconds()));
        return true;
    }

    // Deliver is ready only when a press does something: a question to ask, or a dose to arm.
    (:test)
    function deliverIsReadyOnlyWithADoseToSend(logger as Test.Logger) as Lang.Boolean {
        reading(142);
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        BolusFlow.carbs = 0;
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        reading(250);
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        reading(650);
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        reading(15);
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        reading(250);
        BolusFlow.carbs = 90;
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 0;
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        BolusFlow.unitsMU = 1000;
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        return true;
    }

    // With no reading, the dose screen says the dose is carbs only.
    (:test)
    function noReadingSaysCarbsOnly(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var st = Support.status({});
        st.remove("glucose");
        Status.accept(st, Support.NOW);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Support.eq(BolusFlow.message(Support.NOW), "No CGM: carbs only");
        Support.eq(BolusFlow.estimate(Support.NOW), 6000);
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        reading(142);
        Test.assert(!"No CGM: carbs only".equals(BolusFlow.message(Support.NOW)));
        return true;
    }

    // The stale-reading question offers each choice with its whole dose, as the correction question does;
    // a reading too old to include isn't asked about.
    (:test)
    function aStaleReadingOffersBothDosesOrCarbsOnly(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 600, "backup" => false } }),
                      Support.NOW);
        Test.assert(BolusFlow.staleChoiceNeeded(Support.NOW));
        Support.eq(StaleBolusView.doseMU("include"), 8250);
        Support.eq(StaleBolusView.doseMU("carbsOnly"), 6000);
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 2400, "backup" => false } }),
                      Support.NOW);
        // Too old to include: no question, the dose screen says carbs only, and Deliver arms that dose.
        Test.assert(!BolusFlow.staleChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.message(Support.NOW), "Stale CGM: carbs only");
        Support.eq(BolusFlow.estimate(Support.NOW), 6000);
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        return true;
    }

    // A reading that ages past includable while the question shows ends the question: the screen says so,
    // and nothing it showed can be picked.
    (:test)
    function aReadingThatAgesOutEndsTheQuestion(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 600, "backup" => false } }),
                      Support.NOW);
        var v = new StaleBolusView(Support.NOW);
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 960, "backup" => false } }),
                      Support.NOW);
        Test.assert(!BolusFlow.staleChoiceNeeded(Support.NOW));
        Test.assert(!StaleBolusView.shownKey(Support.NOW).equals(v.shown));
        return true;
    }

    // A reading the pump flags corrects nothing: no question, the dose screen says why, and the carbs-only
    // dose goes with no reading, as the phone composes it.
    (:test)
    function aFlaggedReadingIsCarbsOnly(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_glucose_caution), Support.NOW);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Support.eq(Status.glucoseCaution(), "checkbg");
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        Test.assert(!BolusFlow.staleChoiceNeeded(Support.NOW));
        Support.eq(BolusFlow.estimate(Support.NOW), 6000);
        Support.eq(BolusFlow.message(Support.NOW), "Check BG: carbs only");
        Test.assert(BolusFlow.canDeliver(Support.NOW));
        Test.assert(BolusFlow.arm(Support.NOW));
        Test.assert(BolusFlow.send(Support.NOW));
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Support.eq(p["glucoseMgdl"] as Lang.Object?, null);
        Support.eq(p["estimateMU"] as Lang.Object?, 6000);
        // One this watch doesn't know is kept out of a dose too.
        var st = Support.payloadOf(Rez.JsonData.fixture_status_glucose_caution);
        var g = st["glucose"] as Lang.Dictionary;
        g["caution"] = "somethingnew";
        Status.accept(st, Support.NOW);
        Support.eq(Status.glucoseCaution(), "other");
        Support.eq(BolusFlow.estimate(Support.NOW), 6000);
        return true;
    }

    // Carbs off on the pump: the food entry is insulin units, the reading still corrects and the question is
    // still asked, and the request carries the food as foodMU with no carbs, as the phone takes it.
    (:test)
    function withCarbsOffTheFoodIsUnits(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var calc = Support.payloadOf(Rez.JsonData.fixture_status_carbs_off)["calculator"];
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 60, "backup" => false },
                                       "calculator" => calc }), Support.NOW);
        Test.assert(Status.carbsOff());
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 0;
        BolusFlow.foodMU = 3000;
        BolusFlow.declineCorrection = false;
        // 3.00 U for the food, 140/40 is 3.50 U, less the 1.25 U of IOB; the 45 g aren't counted.
        Support.eq(BolusFlow.estimate(Support.NOW), 5250);
        var doses = BolusFlow.correctionDoses(Support.NOW) as Lang.Array<Lang.Number>;
        Support.eq(doses[0], 5250);
        Support.eq(doses[1], 3000);
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(HoldView.splitText(), "3.00 food + 2.25 correction");
        Test.assert(BolusFlow.send(Support.NOW));
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Support.eq(p["foodMU"] as Lang.Object?, 3000);
        Support.eq(p["carbsG"] as Lang.Object?, null);
        Support.eq(p["estimateMU"] as Lang.Object?, 5250);
        Support.eq(p["glucoseMgdl"] as Lang.Object?, 250);
        BolusFlow.foodMU = 0;
        return true;
    }

    // With carbs off there are no carbs in the dose, so the dose without the correction is "No correction",
    // on the question, the stale question and the dose screen's lines.
    (:test)
    function withCarbsOffTheDoseWithoutTheCorrectionIsNoCorrection(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var calc = Support.payloadOf(Rez.JsonData.fixture_status_carbs_off)["calculator"];
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 60, "backup" => false },
                                       "calculator" => calc }), Support.NOW);
        Support.eq(CorrectionView.label("carbsOnly"), "No correction");
        Support.eq(StaleBolusView.label("carbsOnly"), "No correction");
        Support.eq(BolusFlow.cautionText("sensor"), "CGM not ready: no correction");
        Support.eq(BolusFlow.cautionText("other"), "CGM unusable: no correction");
        var st = Support.status({ "calculator" => calc });
        st.remove("glucose");
        Status.accept(st, Support.NOW);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 0;
        BolusFlow.foodMU = 3000;
        Support.eq(BolusFlow.message(Support.NOW), "No CGM: no correction");
        BolusFlow.foodMU = 0;
        // Carbs on, as before.
        reading(250);
        Support.eq(CorrectionView.label("carbsOnly"), "Carbs only");
        Support.eq(BolusFlow.cautionText("other"), "CGM unusable: carbs only");
        return true;
    }

    // Carbs turned off on the pump after a carb dose was armed: it isn't sent as it stood.
    (:test)
    function carbsTurnedOffAfterArmingStopTheDose(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        BolusFlow.foodMU = 0;
        BolusFlow.declineCorrection = false;
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(BolusFlow.armBlock(Support.NOW), null);
        var calc = Support.payloadOf(Rez.JsonData.fixture_status_carbs_off)["calculator"];
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 60, "backup" => false },
                                       "calculator" => calc }), Support.NOW);
        Support.eq(BolusFlow.armBlock(Support.NOW), "changed");
        Test.assert(!BolusFlow.send(Support.NOW));
        return true;
    }

    // Carbs turned off on the pump with carbs dialed: nothing goes until the food is dialed again in units,
    // and dialing it clears the grams.
    (:test)
    function carbsTurnedOffWithCarbsDialedAreDialedAgain(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        BolusFlow.foodMU = 0;
        var calc = Support.payloadOf(Rez.JsonData.fixture_status_carbs_off)["calculator"];
        Status.accept(Support.status({ "glucose" => { "mgdl" => 250, "at" => Support.NOW - 60, "backup" => false },
                                       "calculator" => calc }), Support.NOW);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW), "redial");
        Test.assert(!BolusFlow.canDeliver(Support.NOW));
        Test.assert(!BolusFlow.correctionChoiceNeeded(Support.NOW));
        Support.eq(BolusEntryView.previewLine(Support.NOW), "Carbs now off: dial in U");
        BolusFlow.adjust(1);
        Support.eq(BolusFlow.carbs, 0);
        Test.assert(BolusFlow.foodMU > 0);
        Support.eq(BolusFlow.calculatorBlock(Support.NOW), null);
        BolusFlow.foodMU = 0;
        return true;
    }

    // With carbs off the food's insulin goes into the calculator as it is: reduced below target, never below
    // nothing, as faBolusCore's BolusMath.estimate(foodUnits:).
    (:test)
    function theFoodsInsulinIsCorrectedAsCarbsAre(logger as Test.Logger) as Lang.Boolean {
        Support.eq(Calculator.estimateFood(3000, 70, 40, 110, 0), 2000);
        Support.eq(Calculator.estimateFood(500, 30, 40, 110, 0), 0);
        Support.eq(Calculator.estimateFood(3000, null, 40, 110, 1250), 3000);
        Support.eq(Calculator.estimateFood(3000, 250, 40, 110, 1250), 5250);
        return true;
    }

    // The confirm screen splits a carb dose into food and correction as the phone's review does; the parts
    // add up to the dose, and a units dose has none.
    (:test)
    function theConfirmScreenSplitsTheDose(logger as Test.Logger) as Lang.Boolean {
        reading(250);
        Test.assert(BolusFlow.arm(Support.NOW));
        // 45 g at 7.5 g/U is 6.00 U; 140/40 is 3.50 U, less the 1.25 U of IOB.
        Support.eq(HoldView.splitText(), "6.00 food + 2.25 correction");
        BolusFlow.declineCorrection = true;
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(HoldView.splitText(), "6.00 food · no correction");
        reading(90);
        BolusFlow.declineCorrection = true;
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(HoldView.splitText(), "6.00 food · not reduced");
        BolusFlow.declineCorrection = false;
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(HoldView.splitText(), "6.00 food - 1.75 reduction");
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        Test.assert(BolusFlow.arm(Support.NOW));
        Support.eq(HoldView.splitText(), null);
        return true;
    }
}
