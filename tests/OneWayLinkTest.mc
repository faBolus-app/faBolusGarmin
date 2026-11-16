using Toybox.Lang;
using Toybox.Test;

// The phone's messages arrive but the watch's don't reach it, as seen after a sideload until the watch was
// restarted. The watch notices from the asks the phone always answers, says to restart the watch, and
// never says a bolus wasn't delivered.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module OneWayLinkTest {
    const NOW = Support.NOW;

    function statusAt(t as Lang.Number) as Void {
        Controller.phoneDataAt(Support.message("status", Support.status({ "sentAt" => t })), t);
    }

    function sendUnits(t as Lang.Number) as Lang.String {
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        Test.assert(BolusFlow.arm(t));
        Test.assert(BolusFlow.send(t));
        return BolusFlow.requestId() as Lang.String;
    }

    function pollAsksForHistory() as Lang.Boolean {
        var poll = Support.lastSent() as Lang.Dictionary;
        return Support.same(Wire.payload(poll)["history"] as Lang.Object?, true);
    }

    // The reported case: a request sent and resent, no "received", while statuses keep arriving. The
    // request screen and the bolus button say to restart the watch; the phone's answer clears it.
    (:test)
    function anUnansweredRequestWhileStatusesArriveIsOneWay(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var id = sendUnits(NOW);
        for (var t = NOW + 1; t <= NOW + 44; t += 1) {
            BolusFlow.tick(t);
            if (t % 5 == 0) { statusAt(t); }
        }
        Support.eq(Support.sentKinds(), ["bolus", "bolus", "bolus", "bolus", "bolus"]);
        // Not yet: the phone hasn't been heard from long enough after the first send.
        Test.assert(!Link.oneWay(NOW + 44));
        statusAt(NOW + 45);
        Test.assert(Link.oneWay(NOW + 45));
        Support.eq(BolusFlow.headline(NOW + 45), "Sending…");
        Support.eq(BolusFlow.oneWayHint(NOW + 45), "Phone can't hear the watch. Restart the watch.");
        Support.eq(BolusFlow.startBlock(NOW + 45), BolusFlow.ONE_WAY_BLOCK);
        Controller.phoneDataAt(Support.message("bolusOutcome", Support.outcome(id, "received")), NOW + 46);
        Test.assert(!Link.oneWay(NOW + 46));
        Test.assert(BolusFlow.oneWayHint(NOW + 46) == null);
        return true;
    }

    // Long after, with still no answer: "No answer", with the hint to restart the watch and check the pump.
    // It never says the bolus wasn't delivered.
    (:test)
    function noAnswerSaysToRestartAndCheckThePump(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        sendUnits(NOW);
        var t = NOW;
        while (t <= NOW + BolusFlow.NO_ANSWER_SEC + 1) {
            t += 1;
            BolusFlow.tick(t);
            if (t % 5 == 0) { statusAt(t); }
        }
        Support.eq(BolusFlow.state(), "noAnswer");
        Support.eq(BolusFlow.headline(t), "No answer");
        Support.eq(BolusFlow.oneWayHint(t), "Phone can't hear the watch. Restart the watch and check the pump.");
        return true;
    }

    // One lost message never adds up to a one-way link: the phone answers the resend, and any answer starts
    // the count again.
    (:test)
    function aLostMessageIsNotOneWay(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var id = sendUnits(NOW);
        for (var t = NOW + 1; t <= NOW + 12; t += 1) {
            BolusFlow.tick(t);
            if (t % 5 == 0) { statusAt(t); }
        }
        Controller.phoneDataAt(Support.message("bolusOutcome", Support.outcome(id, "received")), NOW + 12);
        for (var t = NOW + 13; t <= NOW + 60; t += 5) { statusAt(t); }
        Test.assert(!Link.oneWay(NOW + 60));
        var why = BolusFlow.startBlock(NOW + 60);
        Test.assert(why == null || !why.equals(BolusFlow.ONE_WAY_BLOCK));
        return true;
    }

    // With no bolus at all: the chart ask stands until the chart arrives, so polls keep asking; unanswered
    // while statuses arrive, the bolus button says to restart the watch before a request is ever sent. The
    // chart's arrival clears it, and the next poll no longer asks.
    (:test)
    function anUnansweredChartAskIsOneWay(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.wantHistory();
        for (var i = 0; i < 4; i += 1) {
            var t = NOW + i * 15;
            Test.assert(Link.poll(t));
            Test.assert(pollAsksForHistory());
            statusAt(t + 5);
        }
        Test.assert(Link.oneWay(NOW + 50));
        Support.eq(BolusFlow.startBlock(NOW + 50), BolusFlow.ONE_WAY_BLOCK);
        var history = Support.payloadOf(Rez.JsonData.fixture_history);
        history["sentAt"] = NOW + 51;
        Controller.phoneDataAt(Support.message("history", history), NOW + 51);
        Test.assert(!Link.oneWay(NOW + 51));
        Test.assert(BolusFlow.startBlock(NOW + 51) == null);
        Test.assert(Link.poll(NOW + 65));
        Test.assert(!pollAsksForHistory());
        return true;
    }

    // Muted by the phone's setting: nothing is said and the button isn't held, but the watch still notices
    // and keeps asking for the chart, so it's there again once unmuted.
    (:test)
    function theMuteHidesTheNoticeButNotTheDetection(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config_mute_one_way), NOW));
        var id = sendUnits(NOW);
        for (var t = NOW + 1; t <= NOW + 45; t += 1) {
            BolusFlow.tick(t);
            if (t % 5 == 0) { statusAt(t); }
        }
        Test.assert(Link.oneWay(NOW + 45));
        Test.assert(!Link.sayOneWay(NOW + 45));
        Test.assert(BolusFlow.oneWayHint(NOW + 45) == null);
        Support.eq(BolusFlow.startBlock(NOW + 45), "Bolus in progress");
        Test.assert(Link.poll(NOW + 46));
        Test.assert(pollAsksForHistory());
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config), NOW + 47));
        Test.assert(Link.sayOneWay(NOW + 47));
        Controller.phoneDataAt(Support.message("bolusOutcome", Support.outcome(id, "received")), NOW + 48);
        Test.assert(!Link.sayOneWay(NOW + 48));
        return true;
    }

    // The phone's own settings say why the button is off first: with bolusing off there's nothing to hold,
    // and the notice's mute sits with that setting on the phone.
    (:test)
    function bolusingOffOutranksTheNotice(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var off = Support.payloadOf(Rez.JsonData.fixture_config);
        var bolus = off["bolus"] as Lang.Dictionary;
        bolus["enabled"] = false;
        Test.assert(Prefs.accept(off, NOW));
        Link.wantHistory();
        for (var i = 0; i < 4; i += 1) {
            Link.poll(NOW + i * 15);
            statusAt(NOW + i * 15 + 5);
        }
        Test.assert(Link.oneWay(NOW + 50));
        Support.eq(BolusFlow.startBlock(NOW + 50), "Bolusing off (phone)");
        return true;
    }

    // A busy phone sends the chart after the statuses due, so it can come well after the ask: answered
    // before the asks add up, it's no alarm.
    (:test)
    function aLateChartIsNotOneWay(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.wantHistory();
        for (var i = 0; i < 3; i += 1) {
            Link.poll(NOW + i * 15);
            statusAt(NOW + i * 15 + 5);
        }
        var history = Support.payloadOf(Rez.JsonData.fixture_history);
        history["sentAt"] = NOW + 40;
        Controller.phoneDataAt(Support.message("history", history), NOW + 40);
        Link.poll(NOW + 45);
        for (var t = NOW + 50; t <= NOW + 120; t += 5) { statusAt(t); }
        Test.assert(!Link.oneWay(NOW + 120));
        return true;
    }

    // A phone gone silent isn't a one-way link: nothing shows it was there to answer, and the button says
    // there's no reply from faBolus, as before.
    (:test)
    function aSilentPhoneIsNotOneWay(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.wantHistory();
        for (var i = 0; i < 4; i += 1) { Link.poll(NOW + i * 15); }
        Test.assert(!Link.oneWay(NOW + 50));
        Test.assert(!Link.oneWay(NOW + Link.LIVE_SEC + 1));
        return true;
    }

    // Pressing the blocked button asks the phone again, with the chart, so a link that's back clears the
    // block with its answer.
    (:test)
    function theBlockedButtonAsksAgain(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.wantHistory();
        for (var i = 0; i < 4; i += 1) {
            Link.poll(NOW + i * 15);
            statusAt(NOW + i * 15 + 5);
        }
        Test.assert(!BolusFlow.canStart(NOW + 55));
        var before = Link.testSent.size();
        Nav.pressBolusAt(NOW + 55);
        Support.eq(Link.testSent.size(), before + 1);
        Test.assert(pollAsksForHistory());
        return true;
    }
}
