using Toybox.Application as App;
using Toybox.Application.Storage;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Messages that arrive late or through the background service, clocks that step, alerts announced by one
// process and then the other, and what the system hands over that isn't a message.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module LateMessageTest {
    const NOW = Support.NOW;

    // A status Connect IQ held for 50 minutes, handed to a process with nothing saved before it (as after a
    // fresh install), is shown and used as 50 minutes old, in that process and in one that loads it, and
    // doesn't count as hearing from the phone: the bolus button stays closed.
    (:test)
    function aHeldStatusIsAsOldAsItIs(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config), NOW));
        var held = Support.status({ "sentAt" => NOW - 3000,
            "glucose" => { "mgdl" => 150, "at" => NOW - 3060, "backup" => false, "trend" => "up" } });
        Controller.phoneDataAt(Support.message("status", held), NOW);
        Support.eq(Status.glucose(), 150);
        Test.assert((Status.ageOf("glucose", NOW) as Lang.Number) >= 3060);
        Test.assert(Glucose.stale(NOW));
        Support.eq(Glucose.trend(NOW), null);
        Support.eq(BolusFlow.correctionGlucose(NOW), null);
        Support.eq(BgComplication.glucoseEntry(NOW)[1] as Lang.Object?, "--");
        Test.assert(!Link.phoneLive(NOW));
        Test.assert(!BolusFlow.canStart(NOW));
        Test.assert(!BolusFlow.statusRecent(NOW));
        // Placed on the chart when it was measured, and the chart asks for fresh history.
        Test.assert(Status.clockOffset() <= Status.CLOCK_SEC);
        Test.assert(History.stale(NOW));
        // The glance, another process, loads it as just as old.
        Status.clear();
        Test.assert(FaBolusGlanceView.line(NOW)[2] as Lang.Boolean);
        Test.assert((Status.ageOf("glucose", NOW) as Lang.Number) >= 3060);
        // The service, handed it, tells the app when the phone sent it, which isn't hearing from it now.
        Support.fresh();
        var bg = new BgServiceDelegate();
        var out = bg.exitData(Support.message("status", held), NOW);
        Test.assert(out instanceof Lang.Number && out <= NOW - 3000 + Status.CLOCK_SEC);
        Controller.serviceDataAt(out as App.PersistableType, NOW);
        Test.assert(!Link.phoneLive(NOW));
        // A held bolus outcome doesn't count either.
        Controller.phoneDataAt(Support.message("bolusOutcome",
            { "requestId" => "r1", "outcome" => "delivered", "sentAt" => NOW - 3000 }), NOW);
        Test.assert(!Link.phoneLive(NOW));
        // Nor does a config, which carries no send time.
        Controller.phoneDataAt(Support.message("config", Support.payloadOf(Rez.JsonData.fixture_config)), NOW);
        Test.assert(!Link.phoneLive(NOW));
        // One sent just now does.
        Controller.phoneDataAt(Support.message("status", Support.status({ "sentAt" => NOW - 2 })), NOW);
        Test.assert(Link.phoneLive(NOW));
        return true;
    }

    // Each message reaches a fresh background process, so whether a status replaces the one held is decided
    // from what's stored: a held or reordered copy never does, however late; a current one does when the
    // one held was sent ahead of the watch's clock (the phone's clock has been put right).
    (:test)
    function aLateStatusDoesntRollAFreshProcessBack(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW - 20 }), NOW - 20));
        Status.save(Store.BG_STATUS);
        var late = [NOW - 25, NOW - 300, NOW - 3600] as Lang.Array<Lang.Number>;
        for (var i = 0; i < late.size(); i += 1) {
            Status.clear();
            Status.load();
            Test.assert(!Status.accept(Support.status({ "sentAt" => late[i] }), NOW + i * 60));
            Support.eq(Status.sentAt(), NOW - 20);
        }
        // A backlog, each later than the last, all sent before the one held, over minutes: none is taken.
        for (var t = NOW - 200; t < NOW - 20; t += 30) {
            Status.clear();
            Status.load();
            Test.assert(!Status.accept(Support.status({ "sentAt" => t }), t + 600));
        }
        // The phone's clock was 10 minutes ahead and has been put right.
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW + 600 }), NOW));
        Status.save(Store.BG_STATUS);
        Status.clear();
        Status.load();
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW + 10 }), NOW + 15));
        Support.eq(Status.sentAt(), NOW + 10);
        // Of two stored copies, the one the phone sent last is loaded, whatever order they arrived in.
        Support.fresh();
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW }), NOW));
        Status.save(Store.STATUS);
        Status.clear();
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW - 3000 }), NOW + 5));
        Status.save(Store.BG_STATUS);
        Status.clear();
        Status.load();
        Support.eq(Status.sentAt(), NOW);
        return true;
    }

    // A status loaded from storage ages by uptime while the watch hasn't restarted, so a wall clock stepped
    // back doesn't make it current; saved before a restart, with the clock behind its arrival, its age can't
    // be told and it isn't shown.
    (:test)
    function aStoredStatusAgesByUptime(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config), NOW));
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW));
        Status.save(Store.BG_STATUS);
        var rec = Store.record(Store.BG_STATUS) as Lang.Dictionary;
        // It arrived an hour ago by uptime; the wall clock reads the moment it arrived.
        rec["t"] = System.getTimer() - 3600000;
        Storage.setValue(Store.BG_STATUS, rec as Storage.ValueType);
        Status.clear();
        Status.load();
        Test.assert((Status.ageOf("glucose", NOW) as Lang.Number) >= 3600 + 80);
        Test.assert(Glucose.stale(NOW));
        // Saved before the watch restarted (uptime is below it now), and the clock stepped back since.
        rec["t"] = System.getTimer() + 100000000;
        Storage.setValue(Store.BG_STATUS, rec as Storage.ValueType);
        Status.clear();
        Status.load();
        Support.eq(Status.ageOf("glucose", NOW - 600), null);
        // Shown as old wherever it's shown, never as current, and never corrected from.
        Support.eq(Glucose.text(NOW - 600), "142");
        Test.assert(Glucose.stale(NOW - 600));
        Support.eq(Glucose.ageText(NOW - 600), "old");
        Support.eq(Glucose.trend(NOW - 600), null);
        Test.assert((DetailsView.row("cgm", NOW - 600) as Lang.String).find("(old)") != null);
        Test.assert((DetailsView.row("iob", NOW - 600) as Lang.String).find("(old)") != null);
        Support.eq(FaBolusGlanceView.line(NOW - 600), ["142", "old", true, null]);
        Support.eq(BgComplication.glucoseEntry(NOW - 600)[1] as Lang.Object?, "--");
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        BolusFlow.includeStale = true;
        Support.eq(BolusFlow.correctionGlucose(NOW - 600), null);
        Support.eq(BolusFlow.estimate(NOW - 600), -1);
        return true;
    }

    // A wall clock stepped back neither makes a silent phone count as answering nor a talking one silent:
    // uptime decides then, and uptime that says it has been longer than a minute wins over the wall clock.
    (:test)
    function aClockSteppedBackDoesntKeepThePhoneLive(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Link.phoneLive(NOW));
        // Heard just now by uptime: still live on a clock stepped back.
        Test.assert(Link.phoneLive(NOW - 10));
        // Heard two minutes ago by uptime: silent, whatever the stepped-back clock says.
        Link._heardMs = System.getTimer() - 120000;
        Test.assert(!Link.phoneLive(NOW - 10));
        Support.eq(BolusFlow.startBlock(NOW - 10), "No reply from faBolus");
        Test.assert(Link.recent(10, 9000));
        Test.assert(!Link.recent(10, 61000));
        Test.assert(Link.recent(-1, 0));
        Test.assert(!Link.recent(-1, 61000));
        // A wrapped timer is ignored, unless it's all there is.
        Test.assert(Link.recent(10, -5));
        Test.assert(!Link.recent(-1, -5));
        // The clock is set back ten minutes (from the phone) while the phone keeps talking: its statuses,
        // sent by that clock, count as hearing from it, and the poll waiting on them is answered.
        Link.poll(NOW - 600);
        var back = NOW - 597;
        Controller.phoneDataAt(Support.message("status", Support.status({ "sentAt" => back - 1 })), back);
        Test.assert(Link.phoneLive(back));
        Test.assert(!Link.outstanding());
        Support.eq(BolusFlow.startBlock(back), null);
        // A time heard that's older than the last, or in the future, changes nothing.
        Link.heardAt(NOW - 5, NOW + 5);
        Test.assert(Link.phoneLive(NOW));
        Link.reset();
        Link.heardAt(NOW + 5, NOW);
        Test.assert(!Link.phoneLive(NOW + 5));
        return true;
    }

    // What the system hands over that isn't a phone message (it has handed over null) is ignored rather
    // than read, and the background service still ends with word for the app.
    (:test)
    function somethingThatIsntAMessageIsIgnored(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Support.eq(Inbound.dataOf(null), null);
        Support.eq(Inbound.dataOf({ "version" => 2 }), null);
        var none = null as Lang.Object?;
        Controller.phoneMessage(none as Comm.PhoneAppMessage);
        Support.eq(Status.glucose(), 142);
        Status.save(Store.BG_STATUS);
        var bg = new PostRecorder();
        bg.onPhoneAppMessage(none as Comm.PhoneAppMessage);
        Test.assert(bg.left);
        bg = new PostRecorder();
        bg.onPhoneMessage(none as Comm.PhoneAppMessage);
        Test.assert(bg.left);
        return true;
    }

    // The system can hand the background service a status while the app is open. The app then counts the
    // phone as heard from, as it would for a message of its own, so the bolus button opens while glucose
    // updates; and the status reaches the chart.
    (:test)
    function aStatusTheServiceTookOpensTheBolusButton(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        // The watch's Bluetooth flag says no phone, as it can while the phone's messages arrive.
        Link.testReachable = false;
        Test.assert(Prefs.accept(Support.payloadOf(Rez.JsonData.fixture_config), NOW));
        var bg = new BgServiceDelegate();
        var out = bg.exitData(Support.message("status", Support.status({ "sentAt" => NOW })), NOW);
        // The service is another process: the app holds nothing it took.
        Status.clear();
        Support.eq(History.times().size(), 0);
        Support.eq(BolusFlow.startBlock(NOW), "Phone not connected");
        Controller.serviceDataAt(out as App.PersistableType, NOW);
        Support.eq(BolusFlow.startBlock(NOW), null);
        Support.eq(History.times().size(), 1);
        // What the service saved long before the app hears of it says nothing about now.
        Link.reset();
        Controller.backgroundData(NOW - Link.LIVE_SEC - 1, NOW);
        Test.assert(!Link.phoneLive(NOW));
        Controller.backgroundData(null, NOW);
        Test.assert(!Link.phoneLive(NOW));
        Controller.backgroundData(NOW + 600, NOW);
        Test.assert(!Link.phoneLive(NOW));
        return true;
    }

    // A bolus outcome the system hands to the background service reaches the request on the watch, and the
    // phone counts as heard from. Each saved result is applied once, in order, even with its "read" number
    // unsaved: replaying "delivering" would take a request out of "check the pump before dosing again".
    (:test)
    function anOutcomeTheServiceTookReachesTheAppOnce(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        BolusFlow._id = "r1";
        BolusFlow._msg = {};
        BolusFlow._state = "sending";
        var bg = new BgServiceDelegate();
        bg.exitData(Support.message("bolusOutcome", Support.outcome("r1", "received")), NOW);
        var out = bg.exitData(Support.message("bolusOutcome", Support.outcome("r1", "delivering")), NOW);
        Support.eq(BolusFlow.state(), "sending");
        Test.assert(!Link.phoneLive(NOW));
        Controller.serviceDataAt(out as App.PersistableType, NOW);
        Support.eq(BolusFlow.state(), "delivering");
        Test.assert(Link.phoneLive(NOW));
        BolusFlow._state = "noAnswer";
        Inbound.applySavedResults(NOW + 100);
        Support.eq(BolusFlow.state(), "noAnswer");
        Storage.deleteValue(Store.BG_RESULTS_READ);
        Inbound.applySavedResults(NOW + 100);
        Support.eq(BolusFlow.state(), "noAnswer");
        // A new word from the phone still moves it; one for another request doesn't.
        bg.exitData(Support.message("bolusOutcome", Support.outcome("r2", "failed")), NOW + 100);
        Inbound.applySavedResults(NOW + 100);
        Support.eq(BolusFlow.state(), "noAnswer");
        bg.exitData(Support.message("bolusOutcome", Support.outcome("r1", "delivered")), NOW + 100);
        Inbound.applySavedResults(NOW + 100);
        Support.eq(BolusFlow.state(), "delivered");
        // Only the newest few are kept, and their numbers keep rising.
        for (var i = 0; i < 6; i += 1) {
            Test.assert(bg.apply(Support.message("bolusOutcome", Support.outcome("x" + i.toString(), "delivered"))));
        }
        var kept = Store.list(Store.BG_RESULTS);
        Support.eq(kept.size(), 4);
        Support.eq((kept[kept.size() - 1] as Lang.Dictionary)["n"] as Lang.Number?, 10);
        return true;
    }

    // A dismiss result the service took reaches the app too, and isn't word from the phone.
    (:test)
    function aDismissResultTheServiceTookReachesTheApp(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(Alerts.dismiss("pump.alert.2", NOW));
        var id = Wire.text(Wire.payload(Support.lastSent() as Lang.Dictionary), "requestId", "");
        Link.reset();
        var bg = new BgServiceDelegate();
        var out = bg.exitData(Support.message("dismissResult",
            { "requestId" => id, "alertId" => "pump.alert.2", "result" => "refused" }), NOW);
        Support.eq(out, {});
        Controller.serviceDataAt(out as App.PersistableType, NOW);
        Support.eq(Alerts.note(), "Pump didn't clear it");
        Test.assert(!Link.phoneLive(NOW));
        return true;
    }

    // A chart, or a phone app that can't talk to this one, taken by the service reaches the open app; a
    // chart too large to pass is asked for again.
    (:test)
    function whatOnlyTheAppActsOnReachesIt(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        var bg = new BgServiceDelegate();
        var history = Support.fixture(Rez.JsonData.fixture_history);
        var payloadPart = history["payload"] as Lang.Dictionary;
        payloadPart["sentAt"] = NOW;
        Controller.serviceDataAt(bg.exitData(history, NOW) as App.PersistableType, NOW);
        Test.assert(History.times().size() > 0);
        Test.assert(Link.phoneLive(NOW));
        Controller.serviceDataAt(bg.exitData(Support.fixture(Rez.JsonData.fixture_incompatible), NOW) as App.PersistableType, NOW);
        Test.assert(Link.watchTooOld());
        Link.reset();
        Controller.serviceDataAt(bg.exitData(Support.fixture(Rez.JsonData.fixture_v1_statusRead_from_phone), NOW) as App.PersistableType, NOW);
        Test.assert(Link.phoneTooOld());
        Link.reset();
        Controller.serviceDataAt({ "at" => NOW, "k" => Wire.HISTORY }, NOW);
        Link.poll(NOW);
        Support.eq(Wire.payload(Support.lastSent() as Lang.Dictionary)["history"] as Lang.Object?, true);
        // A status that doesn't read changes nothing.
        Support.eq(bg.exitData(Support.message("status", { "sentAt" => NOW }), NOW), null);
        return true;
    }

    // The background service doesn't post an alert the open app has already shown (and buzzed for); one the
    // app showed that clears and comes back while the app is closed is posted again, each time.
    (:test)
    function anAlertTheAppShowedIsntPostedUntilItComesBack(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Storage.setValue(Store.ALERTS_SEEN, ["pump.alert.2"]);
        var bg = new PostRecorder();
        bg.notifyNew();
        Support.eq(bg.posts, ["app.pumpDisconnected"]);
        for (var i = 0; i < 2; i += 1) {
            Test.assert(Status.accept(Support.status({ "alerts" => [] }), NOW + 1));
            bg.notifyNew();
            Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 2));
            bg.posts = [];
            bg.notifyNew();
            Support.eq(bg.posts, ["pump.alert.2", "app.pumpDisconnected"]);
        }
        // While it stays up, it isn't posted again.
        bg.posts = [];
        bg.notifyNew();
        Support.eq(bg.posts.size(), 0);
        return true;
    }

    // An alert the service notified, which clears and comes back while the app is open, buzzes again when
    // the app shows it; the service doesn't then post it a second time, and an alert it posts after that
    // isn't buzzed for by the app again.
    (:test)
    function anAlertThatComesBackWhileTheAppIsOpenBuzzes(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Storage.setValue(Store.BG_NOTIFIED, ["pump.alert.2"]);
        Support.eq(Alerts.toVibrate(Alerts.list()).size(), 1);
        // The app sees it leave the list, and come back.
        Test.assert(Status.accept(Support.status({ "alerts" => [] }), NOW + 1));
        Controller.announce();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 2));
        Controller.announce();
        Support.eq(Alerts.toVibrate(Alerts.list()).size(), 2);
        // The app showed both; the service, run now, posts neither.
        Storage.setValue(Store.ALERTS_SEEN, ["pump.alert.2", "app.pumpDisconnected"]);
        var bg = new PostRecorder();
        bg.notifyNew();
        Support.eq(bg.posts.size(), 0);
        // It clears and comes back while the app is closed: the service posts it, and the app doesn't buzz
        // for it again.
        Test.assert(Status.accept(Support.status({ "alerts" => [] }), NOW + 3));
        bg.notifyNew();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + 4));
        bg.notifyNew();
        Support.eq(bg.posts, ["pump.alert.2", "app.pumpDisconnected"]);
        Support.eq(Alerts.toVibrate(Alerts.list()).size(), 0);
        Controller.announce();
        Support.eq(Alerts.toVibrate(Alerts.list()).size(), 0);
        return true;
    }

    // The app re-registers for phone messages with every poll: a background service the system ended without
    // exiting may have taken the registration, and would never tell the app.
    (:test)
    function theAppRegistersAgainWithEachPoll(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var before = Controller.registrations;
        Controller.tickAt(NOW);
        Support.eq(Support.sentKinds(), ["poll"]);
        Support.eq(Controller.registrations, before + 1);
        return true;
    }

    const X = "pump.alert.2";
    var _t as Lang.Number = 0;

    function up() as Void { _t += 1; Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW + _t)); }
    function down() as Void { _t += 1; Test.assert(Status.accept(Support.status({ "alerts" => [] }), NOW + _t)); }

    // The open app takes the status as Controller.announce does: 1 when it buzzes for X.
    function appRun() as Lang.Number {
        _t += 1;
        var list = Alerts.list();
        Alerts.noteGone(list);
        var fresh = Alerts.toAnnounce(list);
        var buzz = Alerts.ids(Alerts.toVibrate(fresh));
        Alerts.recordShown(list, Alerts.ids(fresh), NOW + _t);
        return Wire.contains(buzz, X) ? 1 : 0;
    }

    // The service takes the status: 1 when it posts X.
    function bgRun(bg as PostRecorder) as Lang.Number {
        bg.posts = [];
        bg.notifyNew();
        return Wire.contains(bg.posts, X) ? 1 : 0;
    }

    // An alert that leaves the list and comes back buzzes exactly once, whichever process sees it leave and
    // whichever sees it return, and however often each runs after.
    (:test)
    function aReturningAlertBuzzesOnceInEveryOrder(logger as Test.Logger) as Lang.Boolean {
        // 0: the service sees both; 1: the app sees both; 2: the service the leaving, the app the return;
        // 3: the app the leaving, the service the return.
        for (var order = 0; order < 4; order += 1) {
            Support.connected();
            _t = 0;
            var bg = new PostRecorder();
            Support.eqm(appRun(), 1, "first showing");
            Support.eqm(bgRun(bg), 0, "shown by the app");
            down();
            if (order == 0 || order == 2) { bgRun(bg); } else { appRun(); }
            up();
            var n = (order == 0 || order == 3) ? bgRun(bg) + appRun() : appRun() + bgRun(bg);
            n += bgRun(bg) + appRun() + bgRun(bg) + appRun();
            Support.eqm(n, 1, "order " + order.toString());
        }
        // The service posted it with the app closed; the app opens and shows it, then sees it leave and come
        // back and buzzes; the service doesn't post it again once the app closes.
        Support.connected();
        _t = 0;
        var bg = new PostRecorder();
        Support.eq(bgRun(bg), 1);
        Support.eq(appRun(), 0);
        down();
        appRun();
        up();
        Support.eq(appRun() + bgRun(bg) + bgRun(bg) + appRun(), 1);
        return true;
    }
}

// The background service with its notification post and its exit recorded.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class PostRecorder extends BgServiceDelegate {
    var posts as Lang.Array = [];
    var left as Lang.Boolean = false;

    function initialize() { BgServiceDelegate.initialize(); }

    function post(a as Lang.Dictionary) as Void { posts.add(Alerts.idOf(a)); }

    function leave(out as Lang.Number or Lang.Dictionary or Null) as Void { left = true; }
}
