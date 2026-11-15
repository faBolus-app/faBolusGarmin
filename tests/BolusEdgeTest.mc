using Toybox.Lang;
using Toybox.Test;

// The dose the confirm screen shows is the dose requested, whatever moved while the user was at it; a
// config from a newer phone still reads; and a cancel that can't reach the phone never looks done.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module BolusEdgeTest {
    const NOW = Support.NOW;

    // A status received at `t`, sent then, with the pump's settings and IOB read then and the given reading.
    function statusAt(t as Lang.Number, glucose as Lang.Dictionary) as Void {
        var p = Support.status({ "sentAt" => t, "glucose" => glucose, "iob" => { "mU" => 1250, "at" => t } });
        var calculatorPart = p["calculator"] as Lang.Dictionary;
        calculatorPart["at"] = t;
        Test.assert(Status.accept(p, t));
    }

    // A yes to a stale reading holds only while the reading may still be included: past that the dose is
    // carbs only, as the dose screen says, and that's what is armed.
    (:test)
    function aStaleYesLapsesWithTheReading(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var reading = { "mgdl" => 250, "at" => NOW - 80, "backup" => false };
        var t1 = NOW + 400;
        statusAt(t1, reading);
        Link.heard(t1);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Test.assert(BolusFlow.staleChoiceNeeded(t1));
        BolusFlow.includeStale = true;
        Support.eq(BolusFlow.dose(t1), 8250);
        // The user backs out; later the reading is too old to include.
        var t2 = NOW + 1000;
        statusAt(t2, reading);
        Link.heard(t2);
        Test.assert(!BolusFlow.staleIncludable(t2));
        Support.eq(BolusFlow.offeredGlucose(t2), null);
        Support.eq(BolusFlow.dose(t2), 6000);
        Support.eq(BolusFlow.message(t2), "Stale CGM: carbs only");
        Test.assert(BolusFlow.arm(t2));
        Support.eq(BolusFlow.armedDose(), 6000);
        Test.assert(BolusFlow.send(t2));
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Support.eq(p["estimateMU"] as Lang.Object?, 6000);
        Test.assert(!p.hasKey("glucoseMgdl"));
        Support.eq(p["includeStaleGlucose"] as Lang.Object?, false);
        return true;
    }

    // Carbs only was chosen for one reading: a new reading during the confirm asks again, even when the
    // carbs-only dose is the same, so the phone isn't sent an answer for a reading it no longer has.
    (:test)
    function aDeclineIsForTheReadingItAnswered(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        statusAt(NOW, { "mgdl" => 250, "at" => NOW - 5, "backup" => false });
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Test.assert(BolusFlow.correctionChoiceNeeded(NOW));
        BolusFlow.declineCorrection = true;
        Test.assert(BolusFlow.arm(NOW));
        Support.eq(BolusFlow.armBlock(NOW), null);
        statusAt(NOW + 5, { "mgdl" => 260, "at" => NOW + 3, "backup" => false });
        Link.heard(NOW + 5);
        Support.eq(BolusFlow.dose(NOW + 5), 6000);
        Support.eq(BolusFlow.armBlock(NOW + 5), "changed");
        Test.assert(!BolusFlow.send(NOW + 5));
        // The same reading, still current: it goes.
        Support.connected();
        statusAt(NOW, { "mgdl" => 250, "at" => NOW - 5, "backup" => false });
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        BolusFlow.declineCorrection = true;
        Test.assert(BolusFlow.arm(NOW));
        statusAt(NOW + 5, { "mgdl" => 250, "at" => NOW - 5, "backup" => false });
        Support.eq(BolusFlow.armBlock(NOW + 5), null);
        return true;
    }

    // With only the corrected dose over the limit, the question is still asked, and carbs only can be sent;
    // the corrected half can't be armed. With both over, there's no question.
    (:test)
    function oneHalfOverTheLimitLeavesTheOther(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var p = Support.status({ "glucose" => { "mgdl" => 250, "at" => NOW - 5, "backup" => false } });
        var bolusPart = p["bolus"] as Lang.Dictionary;
        bolusPart["remoteLimitMU"] = 7000;
        Test.assert(Status.accept(p, NOW));
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Support.eq(BolusFlow.correctionDoses(NOW), [8250, 6000]);
        Test.assert(BolusFlow.canDeliver(NOW));
        Support.eq(BolusFlow.message(NOW), "Correction asked next");
        Support.eq(BolusEntryView.previewLine(NOW), "over limit or 6.00 U");
        Test.assert(!BolusFlow.arm(NOW));
        BolusFlow.declineCorrection = true;
        Test.assert(BolusFlow.arm(NOW));
        Support.eq(BolusFlow.armedDose(), 6000);
        Support.eq(BolusFlow.armBlock(NOW), null);
        // Both over.
        bolusPart["remoteLimitMU"] = 5000;
        Test.assert(Status.accept(p, NOW + 1));
        BolusFlow.declineCorrection = false;
        Support.eq(BolusFlow.correctionDoses(NOW + 1), null);
        Test.assert(!BolusFlow.canDeliver(NOW + 1));
        return true;
    }

    // A bolus an old status says is going can still be cancelled while the phone is silent: the way out is
    // never hidden. The button marks the status old, and a press sends the cancel, asks the phone, and says
    // to use the pump, never that it's done.
    (:test)
    function aCancelIsNeverHidden(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_delivering), NOW));
        Test.assert(BolusFlow.canCancel(NOW));
        Test.assert(!BolusFlow.activeBolusOld(NOW));
        Support.eq(BolusFlow.cancelToast(true, NOW), "Cancel sent");
        var later = NOW + 3600;
        Support.phoneGone();
        Test.assert(BolusFlow.canCancel(later));
        Test.assert(BolusFlow.activeBolusOld(later));
        Nav.pressBolusAt(later);
        Support.eq(Support.sentKinds(), ["cancel", "poll"]);
        Test.assert(BolusFlow.cancelToast(true, later).find("pump") != null);
        Test.assert(BolusFlow.cancelToast(false, NOW).find("pump") != null);
        // This watch's own request in hand: Cancel stays, and pressing it also asks the phone.
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        Test.assert(BolusFlow.arm(NOW));
        Test.assert(BolusFlow.send(NOW));
        Support.phoneGone();
        Test.assert(BolusFlow.canCancel(NOW + 90));
        Nav.pressBolusAt(NOW + 90);
        Support.eq(Support.sentKinds(), ["bolus", "cancel", "poll"]);
        return true;
    }

    // A transmit that throws as it's handed over says so, and that nothing was sent, not that the phone
    // isn't connected: the phone had just answered.
    (:test)
    function aThrownTransmitSaysWhatHappened(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        Test.assert(BolusFlow.arm(NOW));
        Link.testTransmitFails = true;
        Test.assert(BolusFlow.send(NOW));
        Support.eq(BolusFlow.state(), "notSent");
        Support.eq(BolusFlow.text(), "Couldn't send. Nothing was sent.");
        return true;
    }

    // A screen, detail or slot this build doesn't know is left out; the rest of the config is taken, so the
    // phone doesn't send it again on every poll.
    (:test)
    function anUnknownTokenDoesntRefuseTheConfig(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var c = Support.payloadOf(Rez.JsonData.fixture_config);
        c["revision"] = "00000000000000ee";
        c["details"] = ["iob", "somethingNew", "battery"];
        c["screens"] = { "order" => ["glance", "newScreen", "alerts"], "default" => "newScreen" };
        var complicationPart = c["complication"] as Lang.Dictionary;
        complicationPart["slots"] = ["iob", "newSlot"];
        Test.assert(Prefs.accept(c, NOW));
        Support.eq(Prefs.revision(), "00000000000000ee");
        Support.eq(Prefs.details(), ["iob", "battery"]);
        Support.eq(Prefs.screenOrder(), ["glance", "alerts"]);
        Support.eq(Prefs.defaultScreen(), "glance");
        Support.eq(Prefs.complicationSlots(), ["iob"]);
        return true;
    }

    // The "no bolus" words come from the calculator's total before rounding down, as on the phone: a total
    // under one step below target isn't "reduced to nothing".
    (:test)
    function theMessageIsFromTheUnroundedTotal(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Status.accept(Support.status({
            "glucose" => { "mgdl" => 99, "at" => NOW - 5, "backup" => false },
            "calculator" => { "carbRatioMg" => 10000, "isf" => 40, "target" => 110, "maxBolusMU" => 25000, "at" => NOW - 5 },
            "iob" => { "mU" => 0, "at" => NOW - 5 } }), NOW));
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 3;
        // 0.30 U for the carbs, -0.28 U for the reading: 0.02 U, which rounds down to none.
        Support.eq(BolusFlow.estimate(NOW), 0);
        Support.eq(BolusFlow.message(NOW), null);
        Support.eq(Calculator.message(99, 40, 110, 0, 3, 20.0d), null);
        Support.eq(Calculator.message(99, 40, 110, 0, 3, 0), "reduced");
        Support.eq(Calculator.message(65, 40, 110, 0, 3, 20.0d), "lowReduced");
        Support.eq(Calculator.message(65, 40, 110, 0, 3, 0.0d), "lowNone");
        return true;
    }
}
