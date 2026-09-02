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
//
// getGlanceView()/getServiceDelegate() below carry (:glance)/(:background) directly, on
// the METHOD (not the class) — empirically, annotating the whole FaBolusApp class propagates the tag to
// every member (per Monkey C's annotation-inheritance rule for conditional compilation), which would
// pull EVERY foreground-only method here (onStart/onStop/pollTick/notifyNewAlerts/handlePhoneData/
// pushAlertConfirm/getInitialView, and everything THEY reach — Nav, Attention, the full screen carousel)
// into the bg/glance reachable-graph check, defeating the whole memory-reduction point. Per-method
// annotation is the minimal, correct scope: only the two override methods that actually RUN in the
// restricted contexts carry the tag; everything else here stays unannotated and reachable only from the
// normal foreground entry points. (typecheck -l2/-l3 still flags this class's OTHER methods as
// "implicitly added to the background process" — a known, harmless SDK-compiler quirk: the App class
// already had (:background) declarations elsewhere (BgServiceDelegate/BgCommListener), so the compiler
// conservatively scans the whole class; none of the flagged symbols there are part of the REAL
// bg/glance call graph.)
class FaBolusApp extends App.AppBase {
    private var _timer as Timer.Timer?;
    // Self-rescheduling poll state. `_pollOutstanding` is true between sending a statusRead and its
    // reply arriving (statusRead replies aren't reqId-correlated, so "outstanding" is tracked by arrival —
    // cleared in onPhoneMessage); `_pollSentEpoch` is when the outstanding poll was sent (Unix sec);
    // `_backoff` is the consecutive-miss level (0..4) feeding AppState.pollBaseDelayMs().
    private var _backoff as Lang.Number = 0;
    private var _pollOutstanding as Lang.Boolean = false;
    private var _pollSentEpoch as Lang.Number = 0;
    // Counts scheduleNextPoll() invocations. This is the most direct externally-
    // observable proof that the one-shot poll loop keeps re-arming itself without needing to inspect a
    // live Timer.Timer instance. See tests/RelayResilienceTest.mc.
    private var _scheduleCount as Lang.Number = 0;
    // True once a real view is on the stack (set in getInitialView). Gates surfacing a background-
    // arrived alert: a CIQ app must not pushView before its first view exists (cold-launch order is
    // onStart → onBackgroundData → getInitialView), so onBackgroundData only vibrates/pushes once this
    // is true; otherwise the alert stays "unseen" and the next foreground statusRead surfaces it.
    private var _foreground as Lang.Boolean = false;
    // Observable count of inbound phoneAppMessage delivery errors (see
    // Communications.registerForPhoneAppMessageErrors, registered in onStart below) — purely additive
    // observability, no change to the message-handling flow. Test-only-seam style (mirrors
    // _scheduleCount/scheduleCount() above).
    private var _phoneMsgErrorCount as Lang.Number = 0;
    // Observable count of pollTick's own empty-catch guards firing — the dismiss-retry
    // resend loop transmits through a call that could throw, and its catch used to swallow that throw
    // with zero observability into a persistent transmit failure. Test-only-seam style (mirrors
    // _scheduleCount/scheduleCount() above).
    private var _pollGuardFailureCount as Lang.Number = 0;

    function initialize() { AppBase.initialize(); }

    function onStart(state as Lang.Dictionary?) as Void {
        Comm.registerForPhoneAppMessages(method(:onPhoneMessage));
        // Register for inbound delivery errors where the device/firmware supports it
        // (API Level 6.0.0 — NOT on venu3s per the SDK's own doc/Toybox/Communications.html "Supported
        // Devices" list for registerForPhoneAppMessageErrors, hence the `has` capability guard, exactly
        // the SDK's own documented idiom). Purely additive observability; no change to onPhoneMessage.
        if (Comm has :registerForPhoneAppMessageErrors) {
            Comm.registerForPhoneAppMessageErrors(method(:onPhoneMessageError));
        }
        AppState.loadPersisted();            // show last-known BG instantly (no "--" flash)
        AppState.loadPrefs();                // restore configured screen order + default screen
        BgComplication.publish(null, null, 0);  // re-publish last-known reading to the complication
        // Kick off the self-rescheduling poll — pollTick() sends an immediate statusRead and arms
        // the next one-shot (base 15s + jitter, backing off when replies go missing). Replaces the old
        // fixed 15s repeating timer (no outstanding-gate/backoff → queue+radio churn on a dead/flappy link).
        pollTick();
        registerBackground();
    }

    // Records an inbound phoneAppMessage delivery error for observability. Never throws, never
    // alters message handling — the foreground poll loop (pollTick/scheduleNextPoll) already recovers
    // from a missed/failed reply via its own outstanding-gate + backoff, independent of this counter.
    function onPhoneMessageError(err as Comm.PhoneAppMessageError) as Void { _phoneMsgErrorCount += 1; }

    // Test-observable inbound-error count (mirrors scheduleCount()'s seam style).
    function phoneMsgErrorCount() as Lang.Number { return _phoneMsgErrorCount; }

    function onStop(state as Lang.Dictionary?) as Void {
        if (_timer != null) { _timer.stop(); }
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
    (:background)
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
        // Also register for event-driven phone-app-message push-wake (API 3.2.0), so
        // the phone can wake the closed-app background service immediately on a new CGM value / critical
        // alert (BgServiceDelegate.onPhoneAppMessage) instead of waiting for the next ~5-min temporal poll.
        // Additive to the temporal event above (both stay registered). Capability + try/catch guarded so a
        // device/firmware without it degrades to the temporal poll alone, never a crash.
        if (Background has :registerForPhoneAppMessageEvent) {
            try {
                Background.registerForPhoneAppMessageEvent();
            } catch (e) {
                // Push-wake not permitted here — the 5-min temporal refresh still works.
            }
        }
    }

    // One poll tick. Runs the outcome-watchdog backstop, applies the outstanding-gate +
    // backoff, sends a statusRead (unless a prior one is still within its reply deadline), then arms the
    // next one-shot via scheduleNextPoll(). Re-armed by itself — never a fixed repeating timer.
    function pollTick() as Void {
        // Backstop: advance a stuck in-flight outcome even if no phone reply ever arrives. This is
        // the reschedule loop that keeps the watchdog ticking.
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
        // Mint + RETAIN the reqId (mirrors BgServiceDelegate.mintedReqId) so handlePhoneData can
        // accept ONLY the correlated statusRead reply — the same true id-correlation the background
        // service already does, now applied to the foreground poll too.
        // ROUTINE mint (fires every ~15s) — see RemoteComm.newRoutineRequestId().
        var reqId = RemoteComm.newRoutineRequestId();
        AppState.fgPollMintedReqId = reqId;
        RemoteComm.send(RemoteComm.statusRead(reqId));
        _pollOutstanding = true;
        _pollSentEpoch = now;
        // Bounded retry, piggybacked on this SAME existing tick (no new timer/radio
        // wake) — re-dispatch any unacked, UNEXPIRED dismiss REUSING the SAME requestId+generation the
        // wearer's original confirm minted (a lost-ack retry never mints a new one). Guarded so a throw
        // here can never skip scheduleNextPoll() — the loop's only re-arm path.
        try {
            var dueRetries = AppState.dueDismissRetries(now);
            for (var r = 0; r < dueRetries.size(); r += 1) {
                var due = dueRetries[r] as Lang.Dictionary;
                RemoteComm.send(RemoteComm.dismissAlert(due["requestId"], due["id"], due["kind"]));
            }
        } catch (e) {
            // Counted (see _pollGuardFailureCount above) rather than silently swallowed, still
            // deliberately non-fatal (scheduleNextPoll() below must still run).
            _pollGuardFailureCount += 1;
        }
        scheduleNextPoll();
    }

    // Test-observable proof that scheduleNextPoll() ran (see tests/RelayResilienceTest.mc).
    function scheduleCount() as Lang.Number { return _scheduleCount; }

    // Test-observable pollTick guard-failure count (see tests/RelayResilienceTest.mc).
    function pollGuardFailureCount() as Lang.Number { return _pollGuardFailureCount; }

    // Test-only seam (mirrors scheduleCount()): whether a foreground poll's reply is still
    // outstanding — lets tests/StatusReplyTest.mc assert a mismatched-reqId reply does NOT clear the
    // gate while a matched/legacy one does. Harmless in shipping use (read-only).
    function pollOutstanding() as Lang.Boolean { return _pollOutstanding; }

    // Arm the next one-shot poll. Backoff is SUPPRESSED (level 0, fast cadence) while an outcome is
    // pending so a terminal-echo recovery is quick; otherwise it follows `_backoff`. A random jitter (0..
    // 3999 ms) decorrelates repeated polls / multiple watches from hammering the phone in lockstep.
    function scheduleNextPoll() as Void {
        _scheduleCount += 1;
        var level = AppState.outcomePending() ? 0 : _backoff;
        var delay = AppState.pollBaseDelayMs(level) + (Math.rand() % 4000);
        // Reuse ONE retained Timer.Timer instance across every re-arm instead of allocating
        // a new one every ~15s tick. Lazily create it once (first call — mirrors onStart's pollTick()
        // priming this method), then thereafter stop()+start() the SAME object. The one-shot re-arm
        // semantics (pollTick re-arms itself), the outcome-pending fast-cadence level, and the jitter are
        // all unchanged — only the Timer object identity is now stable across ticks.
        if (_timer == null) { _timer = new Timer.Timer(); } else { _timer.stop(); }
        _timer.start(method(:pollTick), delay, false);   // one-shot; pollTick re-arms
    }

    function onPhoneMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Lang.Dictionary) {
            handlePhoneData(data as Lang.Dictionary);
        }
    }

    // Kept separate from onPhoneMessage so tests/StatusReplyTest.mc + tests/
    // PhoneMessageCastGuardTest.mc can drive the real dispatch logic directly — Comm.PhoneAppMessage is a
    // system-delivered type with no test-constructible instance. Kept non-private, mirroring pollTick().
    function handlePhoneData(data as Lang.Dictionary) as Void {
        var kind = data["kind"];
        var isStatusReadReply = (kind instanceof Lang.String) && (kind as Lang.String).equals("statusRead");
        // Correlate a fg statusRead reply BEFORE any state mutation (AppState.handle() below
        // mutates glucose/iob/carbRatio/etc.) — a mismatched-reqId reply is discarded here so it changes
        // NOTHING (not merely "clears _pollOutstanding late"), mirroring BgServiceDelegate.onPhoneMessage
        // exactly (reuses the SAME AppState.isCorrelatedStatusReply() the bg service uses — no second
        // correlation implementation). RETAINED: isCorrelatedStatusReply's either-id-absent legacy
        // fallback (a reply with no echoed requestId, or fgPollMintedReqId somehow unset, falls back to
        // the kind discriminator) — kept because this fg path is advisory-display only (refreshes
        // glucose/iob/etc.; it never delivers a dose, which is the ledgered phone-side path) and dropping
        // it would break an older phone that doesn't echo requestId. Non-statusRead messages (a
        // bolusStatus echo, etc.) are NEVER gated by this — they proceed to handle() exactly as before.
        if (isStatusReadReply && !AppState.isCorrelatedStatusReply(data, AppState.fgPollMintedReqId)) {
            return;
        }
        AppState.handle(data);
        // A CORRELATED statusRead reply clears the poll-outstanding gate and resets backoff so the
        // fast cadence resumes as soon as the phone is answering again.
        if (isStatusReadReply) {
            _pollOutstanding = false;
            _backoff = 0;
        }
        BgComplication.publishFromState();
        notifyNewAlerts(true);   // foreground: the app is open, so a view is up — safe to surface
        Ui.requestUpdate();
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
    //
    // Non-private — mirrors handlePhoneData's own rationale, so
    // tests/SeenAlertsOrderingTest.mc can drive the real per-alert seen-commit ordering + push-count
    // bound directly (via a FaBolusApp subclass overriding pushAlertConfirm() below to simulate a
    // pushView failure without a live view stack).
    function notifyNewAlerts(canSurface as Lang.Boolean) as Void {
        if (!canSurface) { return; }
        // Surface EVERY genuinely-new alert, not just the most-serious one. newAlertsSince()
        // returns the new ones (most-serious first).
        var newAlerts = AppState.newAlertsSince(AppState.loadSeenAlerts());
        var presented = [];
        if (newAlerts.size() > 0) {
            // Count bound (the "50-vs-4 mismatch"): at most AppState.MAX_ALERT_PUSHES
            // are actively surfaced in ONE batch — matching AlertsListView.MAX_ROWS's 4-row display cap
            // (sanitizeAlerts alone allows up to 50 stored alerts, so an unbounded burst could stack up
            // to 50 Confirmation views). Anything beyond the bound is simply left "new" — it is picked
            // up by the NEXT notifyNewAlerts() call, never dropped.
            var toPush = AppState.capAlertPushes(newAlerts);
            // The watch alert output is driven by the phone-synced,
            // fail-closed alert-intensity gate (AppState.alertActionFor) — NOT a hardcoded vibrate. Resolve
            // the batch's most-severe tier + the device's vibrateOn/doNotDisturb state, then vibrate/tone/
            // backlight ONLY as the gate permits. DEFAULT is vibration-only for every tier; nothing audible
            // and nothing pierces DND unless the user opted in on the phone. FULLY-SILENT guarantee: in
            // Silent mode + critical-override-off the gate returns zero output for every tier including
            // critical — there is no code path here that forces vibrate/tone (the phone is authoritative).
            // Compute the escalation tier over the FULL new-alert set, NOT the display-
            // capped `toPush` — a critical arriving beyond MAX_ALERT_PUSHES must still drive the batch's
            // (single) haptic/tone escalation, never be downgraded because it fell past the 4-row cap.
            var tier = AppState.mostSevereTier(newAlerts);
            var ds = System.getDeviceSettings();
            var vibrateOn = (ds has :vibrateOn) ? ds.vibrateOn : true;        // permissive if unreadable
            var dnd = (ds has :doNotDisturb) ? ds.doNotDisturb : false;       // not-in-DND if unreadable
            var action = AppState.alertActionFor(tier, AppState.alertIntensityMode,
                                                 AppState.alertAudibleMinSeverity,
                                                 AppState.alertCriticalOverridesDnd, vibrateOn, dnd);
            // Vibrate ONCE for the batch (severity-encoded pattern), then push a Confirmation for EACH
            // alert in the capped set. Push LEAST-serious first (iterate the most-serious-first list in
            // reverse) so the most-serious confirmation ends on TOP of the view stack — the one the wearer
            // sees + acts on first.
            if (action["vibrate"] && (Attention has :vibrate)) {
                Attention.vibrate(buildVibeProfiles(AppState.vibePatternFor(action["vibeProfileKey"])));
            }
            // Audible tone + backlight escalate ONLY when the gate returns them (mode "audible", the
            // tier is at/above the user's audible floor, and the DND gate permitted output) — each
            // capability-guarded so an unsupported device silently degrades to vibration-only.
            if (action["tone"] && (Attention has :playTone)) {
                Attention.playTone(Attention.TONE_ALARM);
            }
            if (action["backlight"] && (Attention has :backlight)) {
                Attention.backlight(true);
            }
            // Commit 'seen' PER successfully-presented alert, not a single write of every
            // active identity made BEFORE this loop ran (the old bug — a partial-loop failure could
            // suppress an alert whose Confirmation never actually reached the wearer). pushAlertConfirm's
            // explicit failure model tells us which ones actually ran.
            for (var i = toPush.size() - 1; i >= 0; i -= 1) {
                var a = toPush[i] as Lang.Dictionary;
                if (pushAlertConfirm(a)) {
                    presented.add(AppState.alertIdentity(a));
                }
            }
        }
        // Persist EXACTLY (previously-seen ∩ still-active) ∪ presented-this-batch — ALWAYS, even when
        // newAlerts was empty, so a cleared alert still drops out of the seen-set (a cleared alert that
        // re-fires must re-notify), while an identity that wasn't actually
        // presented (skipped by the count bound, or a failed pushView) is never marked seen.
        AppState.saveSeenAlerts(AppState.reconciledSeenAlerts(presented));
    }

    // Turn a pure haptic pattern ([[dutyCyclePct, durationMs], ...] from
    // AppState.vibePatternFor) into the Attention.VibeProfile array Attention.vibrate expects. This is the
    // ONLY place a VibeProfile is constructed — the severity→pattern decision stays pure + unit-testable in
    // AppState; only this thin builder touches Attention.
    function buildVibeProfiles(pattern as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < pattern.size(); i += 1) {
            var p = pattern[i] as Lang.Array;
            out.add(new Attention.VibeProfile(p[0] as Lang.Number, p[1] as Lang.Number));
        }
        return out;
    }

    // The single explicit "did this alert actually get presented" seam. The Connect IQ 9.2.0
    // SDK docs (doc/Toybox/WatchUi.html) document WatchUi.pushView as throwing
    // Lang.OperationNotAllowedException when called from a context that cannot show a view (background,
    // data field, glance, watch face app, or a widget's base page) — treated here as "not presented" so
    // the caller never marks that identity seen. Non-private (mirrors notifyNewAlerts's own rationale
    // above) so tests/SeenAlertsOrderingTest.mc can override it to inject a failure without a
    // live view stack.
    function pushAlertConfirm(a as Lang.Dictionary) as Lang.Boolean {
        try {
            Ui.pushView(new Ui.Confirmation("Pump alert: " + a["title"] + " — clear?"),
                        new AlertConfirmDelegate(a["id"], a["kind"]), Ui.SLIDE_UP);
            return true;
        } catch (e) {
            return false;
        }
    }

    // Called when the background service exits with data. The 5-minute temporal event fetches fresh
    // status off-screen; BgService forwards ONLY the compact alerts list here (not the full status —
    // its history array can be large and would risk the background-data size limit). We refresh the
    // complication from the persisted reading and re-run the new-alert check. A background SERVICE
    // process still cannot vibrate or pushView, so the FULL confirm-to-clear surface never happens here —
    // that happens HERE, in the main app, and only once a view exists (_foreground). If we're not
    // foreground yet (cold launch), this specific vibrate+confirm surfacing is left for the next
    // foreground statusRead. The background service ITSELF (BgServiceDelegate, a
    // separate process — see BgService.mc) already fired an early Toybox.Notifications system
    // notification for any genuinely new alert before forwarding here, via its own independent
    // bgNotifiedAlerts dedup set — so a critical alert is not left completely silent even when this
    // callback's canSurface is false. That background notification never marks anything "seen" here;
    // this method's own dedup/surfacing below is unaffected and always still runs when a view exists.
    function onBackgroundData(data as App.PersistableType) as Void {
        if (data instanceof Lang.Array) {
            AppState.alerts = AppState.sanitizeAlerts(data as Lang.Array);
        }
        BgComplication.publishFromState();
        notifyNewAlerts(_foreground);
    }
}
