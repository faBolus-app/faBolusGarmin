using Toybox.Application as App;
using Toybox.Background;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi as Ui;

// The watch app. A thin remote: the phone owns the pump, and the app shows what the phone sends and
// passes on what the user confirms.
//
// The app class is compiled into every process, because getGlanceView and getServiceDelegate are in it,
// so it holds only the platform's entry points; each passes straight to Controller, which runs in the
// app's own process only. onStart and onStop run in the glance and background processes too, where
// Controller isn't loaded, so the app starts in getInitialView, which only its own process calls, and
// onStop stops only what was started.
class FaBolusApp extends App.AppBase {
    (:background, :glance)
    private var _started as Lang.Boolean = false;

    function initialize() { AppBase.initialize(); }

    (:background, :glance)
    function onStop(state as Lang.Dictionary?) as Void {
        if (_started) { Controller.stop(); }
    }

    function getInitialView() as [Ui.Views] or [Ui.Views, Ui.InputDelegates] {
        if (!_started) {
            _started = true;
            Controller.start();
        }
        return Controller.initialView();
    }

    (:glance)
    function getGlanceView() as [Ui.GlanceView] or [Ui.GlanceView, Ui.GlanceViewDelegate] or Null {
        return [new FaBolusGlanceView()];
    }

    (:background)
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new BgServiceDelegate()];
    }

    // Before the first view the app hasn't started; it loads what the background saved when it does.
    function onBackgroundData(data as App.PersistableType) as Void {
        if (_started) { Controller.backgroundData(); }
    }
}

// The app while it's open. One timer ticks every second: it polls when the link says one is due, resends
// an unacknowledged bolus request, and redraws. The phone pushes a status on every change, so the poll is
// the backstop. While the app is closed, the background service refreshes the complication.
//
// The annotation says this module runs only in the app's own process: the app class above, which every
// process compiles, calls it only from the app's entry points. Its own code is type-checked as usual.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module Controller {
    var _timer as Timer.Timer?;
    var _nextPollAt as Lang.Number = 0;
    var _lastPublishAt as Lang.Number = 0;
    // When a status last made the watch ask for the config it's missing. At most one ask per BEHIND_SEC,
    // so a config the watch can't read doesn't turn every status into another poll and another config.
    var _behindPollAt as Lang.Number = 0;
    const BEHIND_SEC = 30;
    // A view is on the stack, so an alert card can be pushed.
    var _foreground as Lang.Boolean = false;
    // The watch's Bluetooth link to the phone was down at the last tick.
    var _phoneAway as Lang.Boolean = false;

    function start() as Void {
        Store.migrate();
        Status.load();
        Prefs.load(Status.revision());
        History.load();
        BolusFlow.load(Status.now());
        Comm.registerForPhoneAppMessages(new Lang.Method(Controller, :phoneMessage));
        registerBackground();
        BgComplication.publish(Status.now());
        Link.wantHistory();
        tick();
        var t = new Timer.Timer();
        t.start(new Lang.Method(Controller, :tick), 1000, true);
        _timer = t;
    }

    function stop() as Void {
        var t = _timer;
        if (t != null) { t.stop(); }
        _timer = null;
        _foreground = false;
    }

    function initialView() as [Ui.Views, Ui.InputDelegates] {
        _foreground = true;
        return Nav.initialView();
    }

    // Every five minutes, and whenever the phone sends a message while the app is closed. Registering
    // again replaces the schedule, so it's done on every launch.
    function registerBackground() as Void {
        if (!(Toybox has :Background)) { return; }
        try {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } catch (e) {
            // Not permitted here; the app still updates while open.
        }
        if (Background has :registerForPhoneAppMessageEvent) {
            try {
                Background.registerForPhoneAppMessageEvent();
            } catch (e) {
                // The temporal refresh still runs.
            }
        }
    }

    function tick() as Void { tickAt(Status.now()); }

    // Separate from tick so tests can drive the clock.
    function tickAt(now as Lang.Number) as Void {
        var changed = BolusFlow.tick(now);
        // The phone is back in reach. The polls missed while it was away backed the watch off, but they say
        // nothing about the phone app, so the watch asks at once rather than after the backed-off wait. The
        // misses stand until the phone answers, and a poll still waiting holds the next, so a link that drops
        // and returns every few seconds still gets at most one poll per REPLY_SEC.
        var reachable = Link.reachable(now);
        if (reachable && _phoneAway) { _nextPollAt = now; }
        _phoneAway = !reachable;
        // A clock stepped back would hold the next poll until it caught up.
        if (_nextPollAt - now > Link.MAX_POLL_MS / 1000 + 4) { _nextPollAt = now; }
        if (now >= _nextPollAt && Link.pollDue(now)) {
            Link.poll(now);
            _nextPollAt = now + (Link.delayMs() + Link.jitterMs()) / 1000;
        }
        // The complication's staleness is judged when it's published, so it's republished as time passes.
        if (now - _lastPublishAt >= 60) {
            _lastPublishAt = now;
            BgComplication.publish(now);
        }
        if (changed || now % 5 == 0) { Ui.requestUpdate(); }
    }

    // The user is about to bolus: ask the phone now, with a fresh CGM read, rather than at the next poll.
    // True when a poll went, or one is already waiting for its answer (it asks for the reading next time).
    function checkPhone(now as Lang.Number) as Lang.Boolean {
        Link.wantFreshGlucose();
        if (Link.outstanding()) { return true; }
        var sent = Link.poll(now);
        _nextPollAt = now + (Link.delayMs() + Link.jitterMs()) / 1000;
        return sent;
    }

    function phoneMessage(msg as Comm.PhoneAppMessage) as Void { phoneData(msg.data); }

    // Separate from phoneMessage so tests can drive it: a PhoneAppMessage can't be built in a test.
    function phoneData(data as Lang.Object?) as Void {
        var now = Status.now();
        var kind = Inbound.handle(data, now);
        if (kind == Wire.STATUS || kind == Wire.CONFIG) {
            _lastPublishAt = now;
            BgComplication.publish(now);
        }
        if (kind == Wire.STATUS) {
            // A status naming a config the watch doesn't hold: polling now, with its own revision, makes the
            // phone send it.
            if (Inbound.configBehind() && !Link.outstanding() && now - _behindPollAt >= BEHIND_SEC) {
                _behindPollAt = now;
                Link.poll(now);
                _nextPollAt = now + Link.delayMs() / 1000;
            }
            announce();
        }
        Ui.requestUpdate();
    }

    // For tests: as at launch.
    function reset() as Void {
        _nextPollAt = 0;
        _lastPublishAt = 0;
        _behindPollAt = 0;
        _phoneAway = false;
    }

    // The background service saved a status or config: load it.
    function backgroundData() as Void {
        Status.load();
        Prefs.load(Status.revision());
        BgComplication.publish(Status.now());
        announce();
        Ui.requestUpdate();
    }

    // Shows each alert the app hasn't shown yet, once, and vibrates for those the phone says to.
    function announce() as Void {
        if (!_foreground) { return; }
        var list = Alerts.list();
        var seen = Alerts.loadSet(Store.ALERTS_SEEN);
        var fresh = Alerts.unseen(list, seen);
        var shown = [] as Lang.Array;
        if (fresh.size() > 0) {
            // One the background service already notified isn't vibrated for again.
            var buzz = Alerts.toVibrate(fresh);
            if (Alerts.shouldVibrate(buzz)) { Alerts.vibrate(buzz); }
            var n = (fresh.size() < Alerts.MAX_ANNOUNCED) ? fresh.size() : Alerts.MAX_ANNOUNCED;
            // Least severe first, so the most severe ends on top.
            for (var i = n - 1; i >= 0; i -= 1) {
                var a = fresh[i] as Lang.Dictionary;
                if (pushAlert(a)) { shown.add(Alerts.idOf(a)); }
            }
        }
        Store.save(Store.ALERTS_SEEN, Alerts.reconciled(list, seen, shown));
    }

    // False when the card couldn't be shown, so the alert stays unseen and is shown next time.
    function pushAlert(a as Lang.Dictionary) as Lang.Boolean {
        try {
            Nav.pushAlert(a);
            return true;
        } catch (e) {
            return false;
        }
    }
}
