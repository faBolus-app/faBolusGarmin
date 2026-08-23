using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Background;
using Toybox.Time;
using Toybox.System;
using Toybox.Timer;
using Toybox.Attention;
using Toybox.Math;
using Toybox.Lang;

// App entry. Glance-first: requests pump status from the phone on launch and every 30s, listens
// for status/bolus updates, and republishes the BG complication so it shows on the watch face.
// A background temporal event refreshes the complication roughly every 5 minutes while the app
// isn't open. Thin remote — the iPhone owns the pump connection.
class FaBolusApp extends App.AppBase {
    private var _timer as Timer.Timer?;
    private var _eating as EatingRelay?;   // wrist eating-sensing relay (phone-gated)
    private var _hr as HeartRateRelay?;    // ambient HR relay (phone-gated; rides the status tick)
    // R2-19: self-rescheduling poll state. `_pollOutstanding` is true between sending a statusRead and its
    // reply arriving (statusRead replies aren't reqId-correlated, so "outstanding" is tracked by arrival —
    // cleared in onPhoneMessage); `_pollSentEpoch` is when the outstanding poll was sent (Unix sec);
    // `_backoff` is the consecutive-miss level (0..4) feeding AppState.pollBaseDelayMs().
    private var _backoff as Lang.Number = 0;
    private var _pollOutstanding as Lang.Boolean = false;
    private var _pollSentEpoch as Lang.Number = 0;
    // True once a real view is on the stack (set in getInitialView). Gates surfacing a background-
    // arrived alert: a CIQ app must not pushView before its first view exists (cold-launch order is
    // onStart → onBackgroundData → getInitialView), so onBackgroundData only vibrates/pushes once this
    // is true; otherwise the alert stays "unseen" and the next foreground statusRead surfaces it.
    private var _foreground as Lang.Boolean = false;

    function initialize() { AppBase.initialize(); _eating = new EatingRelay(); _hr = new HeartRateRelay(); }

    function onStart(state as Lang.Dictionary?) as Void {
        Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
        AppState.loadPersisted();            // show last-known BG instantly (no "--" flash)
        AppState.loadPrefs();                // restore configured screen order + default screen
        BgComplication.publish(null, null, 0);  // re-publish last-known reading to the complication
        // R2-19: kick off the self-rescheduling poll — pollTick() sends an immediate statusRead and arms
        // the next one-shot (base 15s + jitter, backing off when replies go missing). Replaces the old
        // fixed 15s repeating timer (no outstanding-gate/backoff → queue+radio churn on a dead/flappy link).
        pollTick();
        registerBackground();
    }

    function onStop(state as Lang.Dictionary?) as Void {
        if (_timer != null) { _timer.stop(); }
        if (_eating != null) { _eating.stop(); }
        if (_hr != null) { _hr.stop(); }
        _foreground = false;
    }

    function getInitialView() {
        _foreground = true;         // a view is about to be on the stack — safe to surface alerts now
        return Nav.initialView();   // the user-configured default screen
    }

    // Compact BG glance shown in the glance/widget carousel (devices that support glances).
    (:glance)
    function getGlanceView() {
        return [ new FaBolusGlanceView() ];
    }

    // The background service that refreshes the complication when the app is closed.
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [ new BgServiceDelegate() ];
    }

    private function registerBackground() as Void {
        if (!(Toybox has :Background)) { return; }
        // Re-register every launch (registering replaces the schedule). The previous `last == null`
        // guard could skip registration after a sideload update — where the last-event time
        // persisted but the schedule was cleared — leaving the complication with no background
        // refresh at all. 5 min is the minimum interval Garmin allows.
        try {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } catch (e) {
            // Background not permitted on this device/config — foreground updates still work.
        }
    }

    // R2-19: one poll tick. Runs the R2-02 outcome-watchdog backstop, applies the outstanding-gate +
    // backoff, sends a statusRead (unless a prior one is still within its reply deadline), then arms the
    // next one-shot via scheduleNextPoll(). Re-armed by itself — never a fixed repeating timer.
    function pollTick() as Void {
        // R2-02 backstop: advance a stuck in-flight outcome even if no phone reply ever arrives. This is
        // the reschedule loop the batch guidance relies on to keep the watchdog ticking.
        if (AppState.tickOutcomeWatchdog()) { Ui.requestUpdate(); }
        var now = Time.now().value();
        // Outstanding-gate: a prior poll is still awaiting its reply within the reply deadline → don't
        // pile on another statusRead; just reschedule and let it land (or time out into backoff below).
        if (_pollOutstanding && (now - _pollSentEpoch) < AppState.POLL_REPLY_DEADLINE_SEC) {
            scheduleNextPoll();
            return;
        }
        // A prior poll went unanswered past its reply deadline → back off (capped at level 4).
        if (_pollOutstanding && _backoff < 4) { _backoff += 1; }
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
        _pollOutstanding = true;
        _pollSentEpoch = now;
        // Piggyback ambient HR on the existing status cadence (D-08) — no new timer/radio wake. No-op
        // unless the phone's hr_ctl toggle enabled it (D-09).
        if (_hr != null) { _hr.emitIfDue(); }
        scheduleNextPoll();
    }

    // R2-19: arm the next one-shot poll. Backoff is SUPPRESSED (level 0, fast cadence) while an outcome is
    // pending so a terminal-echo recovery is quick; otherwise it follows `_backoff`. A random jitter (0..
    // 3999 ms) decorrelates repeated polls / multiple watches from hammering the phone in lockstep.
    function scheduleNextPoll() as Void {
        var level = AppState.outcomePending() ? 0 : _backoff;
        var delay = AppState.pollBaseDelayMs(level) + (Math.rand() % 4000);
        if (_timer != null) { _timer.stop(); }
        _timer = new Timer.Timer();
        _timer.start(method(:pollTick), delay, false);   // one-shot; pollTick re-arms
    }

    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Lang.Dictionary) {
            // Phone toggles wrist eating-sensing (out-of-band, not a RemoteCommand). Advisory feature.
            var type = data["type"];
            if (type != null && (type as Lang.String).equals("eating_sense")) {
                if (_eating != null) {
                    if (data["on"] == true) { _eating.start(); } else { _eating.stop(); }
                }
                return;
            }
            // Phone toggles ambient HR chart context (out-of-band, not a RemoteCommand). D-08/D-09:
            // enables/disables the phone-gated relay; when off the watch skips reading + sending HR.
            if (type != null && (type as Lang.String).equals("hr_ctl")) {
                if (_hr != null) { _hr.setEnabled(data["on"] == true); }
                return;
            }
            AppState.handle(data as Lang.Dictionary);
            // R2-19: a statusRead reply clears the poll-outstanding gate and resets backoff so the fast
            // cadence resumes as soon as the phone is answering again. statusRead replies aren't reqId-
            // correlated — the arrival of ANY statusRead is the "the poll was answered" signal.
            var kind = data["kind"];
            if (kind instanceof Lang.String && (kind as Lang.String).equals("statusRead")) {
                _pollOutstanding = false;
                _backoff = 0;
            }
            BgComplication.publishFromState();
            notifyNewAlerts(true);   // foreground: the app is open, so a view is up — safe to surface
            Ui.requestUpdate();
        }
    }

    // When a NEW pump alert arrives, vibrate and show an actionable confirmation to clear it. "New" =
    // an alert identity (AppState.alertIdentity, kind + "-" + id) not in the PERSISTED seen-set — not
    // merely a higher count. The old count comparison missed an alarm that replaced another at the same
    // count and re-fired whenever the list reshuffled; identity tracking fixes both.
    //
    // canSurface is false only when we can't legally pushView yet (a background-arrived alert delivered
    // to onBackgroundData before the first view exists). In that case we do NOTHING — crucially we do
    // NOT mark the alert seen — so it stays new and the next foreground statusRead surfaces it. Vibrate/
    // pushView therefore only ever happen in the foreground; the background never fakes them.
    private function notifyNewAlerts(canSurface as Lang.Boolean) as Void {
        if (!canSurface) { return; }
        // VA-13: surface EVERY genuinely-new alert, not just the most-serious one. The old code found only
        // `firstNew` but marked ALL active identities seen — so a 2nd simultaneous new alert was suppressed
        // forever. newAlertsSince() returns the new ones (most-serious first); we then rewrite the seen-set
        // to exactly the active identities (a cleared alert drops out and re-notifies if it re-fires).
        var newAlerts = AppState.newAlertsSince(AppState.loadSeenAlerts());
        AppState.saveSeenAlerts(AppState.activeAlertIdentities());
        if (newAlerts.size() == 0) { return; }
        // Vibrate ONCE for the batch, then push a Confirmation for EACH new alert. Push LEAST-serious
        // first (iterate the most-serious-first list in reverse) so the most-serious confirmation ends on
        // TOP of the view stack — the one the wearer sees + acts on first. Bounded by sanitizeAlerts +
        // AlertsListView.MAX_ROWS == 4.
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(75, 400)]);
        }
        for (var i = newAlerts.size() - 1; i >= 0; i -= 1) {
            var a = newAlerts[i] as Lang.Dictionary;
            Ui.pushView(new Ui.Confirmation("Pump alert: " + a["title"] + " — clear?"),
                        new AlertConfirmDelegate(a["id"], a["kind"]), Ui.SLIDE_UP);
        }
    }

    // Called when the background service exits with data. The 5-minute temporal event fetches fresh
    // status off-screen; BgService forwards ONLY the compact alerts list here (not the full status —
    // its history array can be large and would risk the background-data size limit). We refresh the
    // complication from the persisted reading and re-run the new-alert check. A background SERVICE
    // process cannot vibrate or pushView, so it never surfaces itself — surfacing happens HERE, in the
    // main app, and only once a view exists (_foreground). If we're not foreground yet (cold launch),
    // the alert is left unseen and the next foreground statusRead surfaces it.
    function onBackgroundData(data as App.PersistableType) as Void {
        if (data instanceof Lang.Array) {
            AppState.alerts = AppState.sanitizeAlerts(data as Lang.Array);
        }
        BgComplication.publishFromState();
        notifyNewAlerts(_foreground);
    }
}
