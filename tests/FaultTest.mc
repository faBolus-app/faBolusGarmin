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

    // A transmit error counts as a miss: the next poll still comes, later. A poll goes out even when the
    // watch's Bluetooth flag says no phone, which it can while the phone's messages still arrive; with no
    // phone, its error is the miss.
    (:test)
    function transmitErrorsCountAsMisses(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Link.poll(NOW);
        Link.pollFailed(NOW);
        Support.eq(Link.misses(), 1);
        Test.assert(!Link.outstanding());
        Link.testReachable = false;
        Test.assert(Link.poll(NOW + 30));
        Link.pollFailed(NOW + 30);
        Support.eq(Link.misses(), 2);
        Test.assert(Link.pollDue(NOW + 31));
        Link.testTransmitFails = true;
        Test.assert(!Link.poll(NOW + 60));
        Support.eq(Link.misses(), 3);
        return true;
    }

    // Pressing the bolus button while the phone hasn't answered lately asks it now, rather than at the
    // next poll, which can be two minutes off: the button opens once it answers. Opening the bolus entry
    // asks it now too, with a fresh CGM read.
    (:test)
    function theBolusButtonAsksThePhoneNow(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var t = NOW + Link.LIVE_SEC + 1;
        Test.assert(!BolusFlow.canStart(t));
        Nav.pressBolusAt(t);
        Support.eq(Support.sentKinds(), ["poll"]);
        // A second press while that poll waits for its answer sends nothing more.
        Nav.pressBolusAt(t + 1);
        Support.eq(Support.sentKinds(), ["poll"]);
        Controller.phoneData(Support.message("status", Support.status({ "sentAt" => t + 2 })));
        Test.assert(BolusFlow.canStart(t + 2));
        // The entry asks again at once, for a fresh reading.
        Test.assert(Controller.checkPhone(t + 3));
        var poll = Support.lastSent() as Lang.Dictionary;
        Support.eq(Support.sentKinds(), ["poll", "poll"]);
        Support.eq(Wire.payload(poll)["freshGlucose"] as Lang.Object?, true);
        return true;
    }

    // The watch's Bluetooth flag can say no phone while faBolus's messages still arrive (the glucose keeps
    // updating). A message heard within LIVE_SEC shows the link works, so the watch still polls, sends and
    // offers a bolus; the phone checks and answers every request as always.
    (:test)
    function aPhoneStillHeardFromCountsAsReachable(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.testReachable = false;
        Test.assert(Link.reachable(NOW + 10));
        Test.assert(BolusFlow.startBlock(NOW + 10) == null);
        Test.assert(!Display.linkLine(NOW + 10).equals("Phone not connected"));
        Test.assert(Link.poll(NOW + 10));
        Support.eq(Support.sentKinds(), ["poll"]);
        // Nothing heard for longer than LIVE_SEC, and the flag still says no phone: not reachable.
        Test.assert(!Link.reachable(NOW + Link.LIVE_SEC + 1));
        Support.eq(BolusFlow.startBlock(NOW + Link.LIVE_SEC + 1), "Phone not connected");
        return true;
    }

    // The watch's Bluetooth link to the phone drops for minutes: the polls missed meanwhile back the watch
    // off to two minutes. They say nothing about the phone app, so once the watch sees the phone again it
    // asks at once, not after the backed-off wait.
    (:test)
    function aPhoneBackInReachIsAskedAtOnce(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var t = NOW;
        Controller.tickAt(t);
        Support.eq(Support.sentKinds(), ["poll"]);
        // Gone: the flag says no phone, and a transmit fails as it's handed over.
        Support.phoneGone();
        Link.testTransmitFails = true;
        for (var i = 0; i < 300; i += 1) {
            t += 1;
            Controller.tickAt(t);
        }
        Support.eq(Link.delayMs(), Link.MAX_POLL_MS);
        var before = Link.testSent.size();
        Link.testReachable = true;
        Link.testTransmitFails = false;
        t += 1;
        Controller.tickAt(t);
        Support.eq(Link.testSent.size(), before + 1);
        Support.eq(Support.sentKinds()[before], "poll");
        // The phone answers, and the polls are back to their usual pace.
        Controller.phoneData(Support.message("status", Support.status({ "sentAt" => t })));
        Support.eq(Link.delayMs(), Link.POLL_MS);
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
        Support.eq(BolusFlow.headline(NOW + 200), "No answer");
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
        Support.phoneGone();
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

    // A bolus request is stamped by the phone's clock as near as the watch can tell: its own, less the
    // smallest difference between the two that recent statuses showed, since time in transit only adds to
    // a difference.
    (:test)
    function aBolusIsStampedByThePhonesClock(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config), NOW));
        // The golden status, sent at NOW, reached the watch 40 s later by its clock.
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 40));
        Support.eq(Status.phoneNow(NOW + 100), NOW + 60);
        // A later one took 5 s: the watch is at most 5 s ahead.
        var later = Support.payloadOf(Rez.JsonData.fixture_status);
        later["sentAt"] = NOW + 50;
        Test.assert(Status.accept(later, NOW + 55));
        Support.eq(Status.phoneNow(NOW + 100), NOW + 95);
        Link.heard(NOW + 55);
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        Test.assert(BolusFlow.arm(NOW + 56));
        Test.assert(BolusFlow.send(NOW + 56));
        Support.eq(Wire.payload(Support.lastSent() as Lang.Dictionary)["sentAt"] as Lang.Object?, NOW + 51);
        return true;
    }

    // Cancelling a request the phone hasn't acknowledged stops its resends (the cancel names it, and the
    // phone refuses a copy that arrives later), and "Cancelling" isn't shown for good: the watch hears
    // nothing back about a cancel, so after a while it offers Cancel again.
    (:test)
    function aCancelStopsTheResendsAndIsntShownForGood(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 2000;
        BolusFlow.arm(NOW);
        BolusFlow.send(NOW);
        var id = BolusFlow.requestId();
        Test.assert(BolusFlow.cancel(NOW + 3));
        Support.eq(Wire.payload(Support.lastSent() as Lang.Dictionary)["bolusRequestId"] as Lang.Object?, id);
        var sent = Link.testSent.size();
        for (var t = NOW + 4; t <= NOW + 60; t += 1) { BolusFlow.tick(t); }
        Support.eq(Link.testSent.size(), sent);
        Test.assert(BolusFlow.cancelling(NOW + 10));
        // The button says the cancel is in hand; the headline stays what the request is doing.
        Support.eq(BolusFlow.headline(NOW + 10), "Sending…");
        // Shown through the phone's 60 s wait behind an unanswered request, then Cancel again; the hint to
        // use the pump only once 5 s have gone with no end to the bolus.
        Test.assert(!BolusFlow.cancelSlow(NOW + 3 + 4));
        Test.assert(BolusFlow.cancelSlow(NOW + 3 + 5));
        Test.assert(BolusFlow.cancelling(NOW + 3 + 170));
        Test.assert(!BolusFlow.cancelling(NOW + 3 + BolusFlow.CANCEL_SHOW_SEC));
        Test.assert(BolusFlow.canCancel());
        return true;
    }

    // A stale reading may be included only while the phone would include it (the config's window).
    (:test)
    function aStaleReadingIsIncludableOnlyWhileYoungEnough(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        // The golden reading was measured 80 s before the status; the window is 15 minutes.
        Test.assert(BolusFlow.staleIncludable(NOW + 900 - 80));
        Test.assert(!BolusFlow.staleIncludable(NOW + 900 - 80 + 1));
        return true;
    }

    // A clock stepped back doesn't hold the poll: the outstanding one counts as missed.
    (:test)
    function aClockSteppedBackDoesntHoldThePoll(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Link.poll(NOW + 600);
        Test.assert(Link.outstanding());
        Test.assert(Link.pollDue(NOW));
        return true;
    }

    // The dial stops at the lower of the remote limit and the pump's max bolus.
    (:test)
    function theDialStopsAtTheLowerLimit(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Support.eq(BolusFlow.dialMax(), 10000);
        var p = Support.payloadOf(Rez.JsonData.fixture_status);
        var bolus = p["bolus"] as Lang.Dictionary;
        bolus["remoteLimitMU"] = 30000;
        Test.assert(Status.accept(p, NOW + 1));
        Support.eq(BolusFlow.dialMax(), 25000);
        bolus.remove("remoteLimitMU");
        Test.assert(Status.accept(p, NOW + 2));
        Support.eq(BolusFlow.dialMax(), 25000);
        return true;
    }

    // An alert the background service already notified is shown when the app opens, but not vibrated for
    // again.
    (:test)
    function anAlertNotifiedInTheBackgroundIsntVibratedAgain(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var list = Alerts.list();
        Support.eq(Alerts.toVibrate(list).size(), 2);
        Storage.setValue(Store.BG_NOTIFIED, ["pump.alert.2"]);
        var buzz = Alerts.toVibrate(list);
        Support.eq(buzz.size(), 1);
        Support.eq(Alerts.idOf(buzz[0] as Lang.Dictionary), "app.pumpDisconnected");
        return true;
    }

    // A wall clock stepped back can't stop values aging: uptime, when it says longer, counts.
    (:test)
    function aClockSteppedBackDoesntStopAging(logger as Test.Logger) as Lang.Boolean {
        Support.eq(Status.elapsedFrom(30, null, 0), 30);
        Support.eq(Status.elapsedFrom(-600, 1000, 61000), 60);
        Support.eq(Status.elapsedFrom(90, 1000, 61000), 90);
        Support.eq(Status.elapsedFrom(-5, null, 0), 0);
        // A timer that wrapped reads negative and is ignored.
        Support.eq(Status.elapsedFrom(20, 2000000000, 5), 20);
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
        Test.assert(!Alerts.onDismissResult({ "requestId" => first, "alertId" => "pump.alert.2", "result" => "cleared" }, NOW));
        Support.eq(Alerts.shown().size(), 2);
        Support.phoneGone();
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
        Test.assert(Alerts.onDismissResult({ "requestId" => second, "alertId" => "pump.alert.2", "result" => "cleared" }, NOW));
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
        Test.assert(BolusFlow.cancelling(NOW + 3));
        // An error for some earlier cancel changes nothing.
        BolusFlow.cancelFailed(NOW + 1);
        Test.assert(BolusFlow.cancelling(NOW + 3));
        BolusFlow.cancelFailed(NOW + 3);
        Test.assert(!BolusFlow.cancelling(NOW + 3));
        Support.eq(BolusFlow.headline(NOW + 3), "Sending…");
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
