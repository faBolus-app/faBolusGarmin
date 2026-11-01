using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Test;

// Lost, late, repeated and reordered messages, transmit errors and the background wake: the watch recovers,
// never retries without end, and is never stuck.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module FaultTest {
    const NOW = Support.NOW;

    // Unanswered polls back off, doubling to two minutes, and any message from the phone resets them.
    (:test)
    function unansweredPollsBackOffAndRecover(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        var t = NOW;
        Test.assert(Link.pollDue(t));
        Link.poll(t);
        Test.assert(!Link.pollDue(t + 5));
        var delays = [] as Lang.Array<Lang.Number>;
        for (var i = 0; i < 8; i += 1) {
            t += Link.REPLY_SEC;
            Test.assert(Link.pollDue(t));
            delays.add(Link.delayMs());
            Link.poll(t);
        }
        Test.assert(Support.same(delays, [30000, 60000, 120000, 120000, 120000, 120000, 120000, 120000]));
        Test.assert(!Link.phoneLive(t));
        Link.heard(t);
        Support.eq(Link.delayMs(), Link.POLL_MS);
        Test.assert(Link.phoneLive(t));
        Test.assert(!Link.outstanding());
        return true;
    }

    // A transmit error, or no phone at all, counts as a miss: the next poll still comes, later.
    (:test)
    function transmitErrorsCountAsMisses(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Link.poll(NOW);
        Link.pollFailed(NOW);
        Support.eq(Link.misses(), 1);
        Test.assert(!Link.outstanding());
        Link.testReachable = false;
        Test.assert(!Link.poll(NOW + 30));
        Support.eq(Link.misses(), 2);
        Test.assert(Link.pollDue(NOW + 31));
        return true;
    }

    // An error for an earlier poll, arriving after the next went out, doesn't touch the next: it was
    // already counted when that poll timed out.
    (:test)
    function aLatePollErrorIsThatPollsOwn(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Link.poll(NOW);
        Test.assert(Link.pollDue(NOW + Link.REPLY_SEC));
        Link.poll(NOW + Link.REPLY_SEC);
        Support.eq(Link.misses(), 1);
        Link.pollFailed(NOW);
        Support.eq(Link.misses(), 1);
        Test.assert(Link.outstanding());
        Link.pollFailed(NOW + Link.REPLY_SEC);
        Support.eq(Link.misses(), 2);
        Test.assert(!Link.outstanding());
        return true;
    }

    // The bolus request is resent unchanged until the phone answers, only while the phone would still take
    // it, and then the watch says it has no answer. It never says the bolus wasn't delivered.
    (:test)
    function anUnansweredBolusIsResentThenNoAnswer(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        var first = Support.lastSent() as Lang.Dictionary;
        var t = NOW;
        while (t < NOW + 200) {
            t += 1;
            Link.heard(t);
            BolusFlow.tick(t);
        }
        var resends = 0;
        for (var i = 1; i < Link.testSent.size(); i += 1) {
            var m = Link.testSent[i] as Lang.Dictionary;
            Test.assert(Support.same(m, first));
            resends += 1;
        }
        // Every 10 s within the 120 s the phone accepts.
        Support.eq(resends, 12);
        Support.eq(BolusFlow.state(), "noAnswer");
        Support.eq(BolusFlow.headline(), "No answer");
        Test.assert((BolusFlow.text() as Lang.String).find("Check the pump") != null);
        // Not stuck: a new bolus may start, and the request is still asked about.
        Test.assert(!BolusFlow.busy());
        Support.eq(BolusFlow.awaitingId(t), BolusFlow.requestId());
        // The real answer, however late, still lands.
        Test.assert(BolusFlow.onOutcome(Support.outcome(BolusFlow.requestId() as Lang.String, "delivered"), t));
        Support.eq(BolusFlow.state(), "delivered");
        Support.eq(BolusFlow.awaitingId(t), null);
        return true;
    }

    // The phone acknowledged and then went quiet mid-delivery: the watch stops blocking and keeps asking.
    (:test)
    function aPhoneThatGoesQuietDoesntStrandTheWatch(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        BolusFlow.onOutcome(Support.outcome(BolusFlow.requestId() as Lang.String, "delivering"), NOW + 2);
        Test.assert(BolusFlow.busy());
        // While the phone keeps answering the polls that name it, a long delivery is fine.
        var id = BolusFlow.requestId() as Lang.String;
        for (var t = NOW; t < NOW + 600; t += 15) {
            Link.heard(t);
            BolusFlow.onOutcome(Support.outcome(id, "delivering"), t);
            BolusFlow.tick(t);
        }
        Support.eq(BolusFlow.state(), "delivering");
        // Then nothing for over a minute.
        BolusFlow.tick(NOW + 700);
        Support.eq(BolusFlow.state(), "noAnswer");
        Test.assert(!BolusFlow.busy());
        Support.eq(BolusFlow.awaitingId(NOW + 700), BolusFlow.requestId());
        return true;
    }

    // The phone said it had the request and then lost it (it relaunched before the answer reached the
    // watch): it keeps answering polls but never about this request. The watch doesn't stay busy.
    (:test)
    function aRequestThePhoneLostDoesntStrandTheWatch(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        BolusFlow.onOutcome(Support.outcome(BolusFlow.requestId() as Lang.String, "received"), NOW + 1);
        for (var t = NOW + 1; t <= NOW + 200; t += 15) {
            Link.heard(t);
            Status.accept(Support.status({ "sentAt" => t }), t);
            BolusFlow.tick(t);
        }
        Support.eq(BolusFlow.state(), "noAnswer");
        Test.assert(!BolusFlow.busy());
        Test.assert(BolusFlow.canStart(NOW + 200));
        // Still asked about, in case it turns up.
        Support.eq(BolusFlow.awaitingId(NOW + 200), BolusFlow.requestId());
        return true;
    }

    // Repeated, reordered and stray outcomes: only a move forward for this request counts.
    (:test)
    function outcomesOnlyMoveForward(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow._id = "r1";
        BolusFlow._msg = {};
        BolusFlow._state = "sending";
        Test.assert(BolusFlow.onOutcome(Support.outcome("r1", "received"), NOW));
        Test.assert(!BolusFlow.onOutcome(Support.outcome("r1", "received"), NOW));
        Test.assert(BolusFlow.onOutcome(Support.outcome("r1", "unknown"), NOW));
        Test.assert(!BolusFlow.onOutcome(Support.outcome("r1", "delivering"), NOW));
        Test.assert(!BolusFlow.onOutcome(Support.outcome("r1", "refused"), NOW));
        Test.assert(!BolusFlow.onOutcome(Support.outcome("r2", "delivered"), NOW));
        Test.assert(!BolusFlow.onOutcome({ "requestId" => "r1", "outcome" => "teleported" }, NOW));
        Support.eq(BolusFlow.state(), "unknown");
        Test.assert(BolusFlow.onOutcome(Support.outcome("r1", "stopped"), NOW));
        Test.assert(!BolusFlow.onOutcome(Support.outcome("r1", "delivered"), NOW));
        Support.eq(BolusFlow.state(), "stopped");
        return true;
    }

    // With no phone at the confirm, nothing goes out, and the watch says so.
    (:test)
    function noPhoneAtSendIsNotSent(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        Link.testReachable = false;
        // The confirm itself refuses: the phone isn't there.
        Test.assert(!BolusFlow.send(NOW));
        Support.eq(BolusFlow.armBlock(NOW), "phone");
        Support.eq(Link.testSent.size(), 0);
        return true;
    }

    // A transmit that fails as it's handed over: nothing went out, and the result says so.
    (:test)
    function aTransmitThatThrowsIsNotSent(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        Link.testTransmitFails = true;
        Test.assert(BolusFlow.send(NOW));
        Support.eq(BolusFlow.state(), "notSent");
        Test.assert(!BolusFlow.busy());
        Support.eq(BolusFlow.awaitingId(NOW), null);
        return true;
    }

    // The confirmed dose is checked again at the last tap: a status that moved since cancels it.
    (:test)
    function aConfirmAgainstAMovedStateIsNotSent(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Test.assert(BolusFlow.arm(NOW));
        Support.eq(BolusFlow.armBlock(NOW), null);
        // A new reading: the calculator's dose changed.
        Status.accept(Support.status({ "glucose" => { "mgdl" => 200, "at" => NOW - 5, "backup" => false } }), NOW);
        Support.eq(BolusFlow.armBlock(NOW), "changed");
        Test.assert(!BolusFlow.send(NOW));
        // Bolusing turned off on the phone.
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 1000;
        BolusFlow.arm(NOW);
        var off = Support.payloadOf(Rez.JsonData.fixture_config);
        var ob = off["bolus"] as Lang.Dictionary;
        ob["enabled"] = false;
        Prefs.accept(off, NOW);
        Support.eq(BolusFlow.armBlock(NOW), "off");
        // The phone blocked bolusing.
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 1000;
        BolusFlow.arm(NOW);
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_minimal), NOW);
        Support.eq(BolusFlow.armBlock(NOW), "blocked");
        // Too long since the confirm started.
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 1000;
        BolusFlow.arm(NOW);
        Link.heard(NOW + 121);
        Support.eq(BolusFlow.armBlock(NOW + 121), "expired");
        Support.eq(Link.testSent.size(), 0);
        return true;
    }

    // A fresh reading that goes stale during the confirm isn't silently included: the dose changes, and the
    // confirm has to start over.
    (:test)
    function aReadingGoingStaleMidConfirmIsNotIncluded(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Status.accept(Support.status({ "glucose" => { "mgdl" => 200, "at" => NOW - 300, "backup" => false } }), NOW);
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 30;
        Test.assert(BolusFlow.arm(NOW));
        Link.heard(NOW + 90);
        Support.eq(BolusFlow.armBlock(NOW + 90), "changed");
        return true;
    }

    // Cancel is never gated: read-only, bolusing off and a blocked pump don't stop it.
    (:test)
    function cancelIsNeverGated(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_delivering), NOW);
        var ro = Support.payloadOf(Rez.JsonData.fixture_config);
        var rb = ro["bolus"] as Lang.Dictionary;
        rb["readOnly"] = true;
        rb["enabled"] = false;
        Prefs.accept(ro, NOW);
        Test.assert(BolusFlow.canCancel());
        Test.assert(BolusFlow.cancel(NOW));
        Support.eq((Support.lastSent() as Lang.Dictionary)["kind"] as Lang.Object?, "cancel");
        return true;
    }

    // A request open when the app was closed is still asked about when it opens again.
    (:test)
    function anOpenRequestSurvivesARestart(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        var id = BolusFlow.requestId();
        BolusFlow._id = null;
        BolusFlow._state = "";
        BolusFlow.load(NOW + 5);
        Support.eq(BolusFlow.requestId(), id);
        Support.eq(BolusFlow.state(), "sending");
        Link.poll(NOW + 5);
        Support.eq(Wire.payload(Support.lastSent() as Lang.Dictionary)["awaiting"] as Lang.Object?, id);
        // A corrupt record is dropped rather than half-read.
        Storage.setValue(Store.BOLUS, { "id" => 5 });
        BolusFlow.forget();
        Storage.setValue(Store.BOLUS, { "id" => 5 });
        BolusFlow.load(NOW + 5);
        Support.eq(BolusFlow.requestId(), null);
        Support.eq(Storage.getValue(Store.BOLUS), null);
        return true;
    }

    // The background service, woken by a push, saves only its own keys, and the app then loads the newer.
    (:test)
    function aBackgroundPushIsSavedUnderItsOwnKeys(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        var bg = new BgServiceDelegate();
        Test.assert(bg.apply(Support.message("status", Support.payloadOf(Rez.JsonData.fixture_status))));
        Test.assert(Support.isSet(Store.record(Store.BG_STATUS)));
        Support.eq(Store.record(Store.STATUS), null);
        Test.assert(bg.apply(Support.message("config", Support.payloadOf(Rez.JsonData.fixture_config))));
        Test.assert(Support.isSet(Store.record(Store.BG_CONFIG)));
        Support.eq(Store.record(Store.CONFIG), null);
        // Nothing else is the background's.
        Test.assert(!bg.apply(Support.message("bolusOutcome", Support.outcome("r1", "delivered"))));
        Test.assert(!bg.apply(Support.fixture(Rez.JsonData.fixture_v1_statusRead_from_phone)));
        Status.clear();
        Prefs.clear();
        Status.load();
        Prefs.load(Status.revision());
        Support.eq(Status.glucose(), 142);
        Test.assert(Prefs.bolusEnabled());
        BgComplication.publish(NOW);
        return true;
    }

    // Alerts the background notified aren't notified again; one that cleared and came back is.
    (:test)
    function eachAlertIsAnnouncedOnce(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var list = Alerts.list();
        var seen = [] as Lang.Array;
        Support.eq(Alerts.unseen(list, seen).size(), 2);
        seen = Alerts.reconciled(list, seen, ["pump.alert.2"]);
        Support.eq(Alerts.unseen(list, seen).size(), 1);
        // It clears: it leaves the set.
        Status.accept(Support.status({ "alerts" => [] }), NOW);
        seen = Alerts.reconciled(Alerts.list(), seen, []);
        Support.eq(seen.size(), 0);
        // It returns: announced again.
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW);
        Support.eq(Alerts.unseen(Alerts.list(), seen).size(), 2);
        return true;
    }

    // A dismiss answer for an earlier request, or one that arrives after a newer dismiss, is ignored.
    (:test)
    function lateDismissAnswersAreIgnored(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Alerts.dismiss("pump.alert.2", NOW));
        var first = Wire.text(Wire.payload(Support.lastSent() as Lang.Dictionary), "requestId", "");
        Test.assert(Alerts.dismiss("pump.alert.2", NOW + 1));
        Test.assert(!Alerts.onDismissResult({ "requestId" => first, "alertId" => "pump.alert.2", "result" => "cleared" }));
        Support.eq(Alerts.shown().size(), 2);
        Link.testReachable = false;
        Test.assert(!Alerts.dismiss("pump.alert.2", NOW + 2));
        Support.eq(Alerts.note(), "Phone not connected — not cleared");
        Support.eq(Alerts.shown().size(), 2);
        return true;
    }

    // A send error for an earlier dismiss, arriving after a newer one went out, leaves the newer one alone:
    // its answer is still taken.
    (:test)
    function aLateDismissErrorIsThatDismisssOwn(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Alerts.dismiss("pump.alert.2", NOW));
        var first = Wire.text(Wire.payload(Support.lastSent() as Lang.Dictionary), "requestId", "");
        Test.assert(Alerts.dismiss("pump.alert.2", NOW + 1));
        var second = Wire.text(Wire.payload(Support.lastSent() as Lang.Dictionary), "requestId", "");
        Alerts.sendFailed(first);
        Support.eq(Alerts.note(), "Clearing…");
        Test.assert(Alerts.onDismissResult({ "requestId" => second, "alertId" => "pump.alert.2", "result" => "cleared" }));
        Support.eq(Alerts.shown().size(), 1);
        // Its own error is shown.
        Test.assert(Alerts.dismiss("app.pumpDisconnected", NOW + 2));
        Alerts.sendFailed(Wire.text(Wire.payload(Support.lastSent() as Lang.Dictionary), "requestId", ""));
        Support.eq(Alerts.note(), "Not sent — try again");
        return true;
    }

    // A cancel that fails after it was handed over isn't shown as in progress, so the user presses again.
    (:test)
    function aFailedCancelIsNotShownAsCancelling(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        Test.assert(BolusFlow.cancel(NOW + 3));
        Test.assert(BolusFlow.cancelling());
        // An error for some earlier cancel changes nothing.
        BolusFlow.cancelFailed(NOW + 1);
        Test.assert(BolusFlow.cancelling());
        BolusFlow.cancelFailed(NOW + 3);
        Test.assert(!BolusFlow.cancelling());
        Support.eq(BolusFlow.headline(), "Sending…");
        Test.assert(BolusFlow.canCancel());
        return true;
    }

    // A status that doesn't read isn't word from the phone: once the last good one is a minute old, no
    // bolus is offered from it.
    (:test)
    function unreadableStatusesDontKeepThePhoneLive(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(BolusFlow.canStart(NOW));
        for (var t = NOW + 15; t <= NOW + 90; t += 15) {
            Controller.phoneData(Support.message("status", { "sentAt" => t }));
        }
        Support.eq(BolusFlow.startBlock(NOW + 90), "No reply from faBolus");
        return true;
    }

    // A status sent before the one held, arriving just after it, is a late copy and changes nothing; a
    // phone whose clock moved back is believed once a minute has passed.
    (:test)
    function aLateStatusDoesntRollTheWatchBack(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW + 20,
            "glucose" => { "mgdl" => 150, "at" => NOW + 10, "backup" => false } }), NOW + 20));
        Test.assert(!Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 25));
        Support.eq(Status.glucose(), 150);
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 20 + Status.REORDER_SEC));
        Support.eq(Status.glucose(), 142);
        return true;
    }
}
