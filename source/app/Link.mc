using Toybox.Application.Storage;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi as Ui;

// The watch's side of the link, while the app is open: when to poll, how long to wait for an answer, how
// far to back off, and whether the phone app is answering at all.
//
// The phone pushes a status on every change, so the poll is a backstop and a way to say what the watch
// holds. Its state is three values: when the last poll went out (zero when none is outstanding), how many
// polls in a row went unanswered, and when the phone was last heard from, by the wall clock and by uptime.
// A status, bolus outcome or chart answers, by when the phone sent it: one Connect IQ held on its way
// here is as old as it is. A poll goes out whatever the watch's Bluetooth flag says (it can say no phone while the
// phone's messages arrive), and a transmit error counts as an unanswered poll. Every wait is bounded, so
// the link always polls again and never stops for good, and when the phone comes back in Bluetooth reach
// the app polls at once (Controller.tickAt) rather than after the wait its misses set.
module Link {
    const POLL_MS = 15000;
    const MAX_POLL_MS = 120000;
    // A poll unanswered this long counts as a miss.
    const REPLY_SEC = 12;
    // The phone app counts as answering while it was heard from this recently.
    const LIVE_SEC = 60;
    // A one-way link: this many asks the phone always answers have gone unanswered, the first this long
    // before the phone was last heard from (see oneWay).
    // Generous, as the phone sends the chart after any status due, so a busy phone can hold it back a while.
    const ONE_WAY_ASKS = 4;
    const ONE_WAY_SEC = 45;

    var _pollSentAt as Lang.Number = 0;
    var _misses as Lang.Number = 0;
    var _heardAt as Lang.Number = 0;
    // The same moment by uptime (System.getTimer(), ms), which a wall clock stepped back can't move.
    var _heardMs as Lang.Number = 0;
    // Set by a message from another protocol version, until a version 2 message arrives.
    var _phoneTooOld as Lang.Boolean = false;
    var _watchTooOld as Lang.Boolean = false;
    // What the next poll asks for.
    var _wantHistory as Lang.Boolean = false;
    var _wantFreshGlucose as Lang.Boolean = false;
    // Asks handed over since the phone last answered one (see asked), and when the first of them went.
    var _asks as Lang.Number = 0;
    var _askSince as Lang.Number = 0;

    // For tests: whether the phone counts as connected, instead of the device setting, and whether a
    // transmit actually goes out. The simulator has no phone, and a real transmit there opens a dialog.
    var testReachable as Lang.Boolean? = null;
    var testSuppressTransmit as Lang.Boolean = false;
    // For tests: a transmit that throws as it's handed over.
    var testTransmitFails as Lang.Boolean = false;
    var testSent as Lang.Array = [];

    function reset() as Void {
        _pollSentAt = 0;
        _misses = 0;
        _heardAt = 0;
        _heardMs = 0;
        _phoneTooOld = false;
        _watchTooOld = false;
        _wantHistory = false;
        _wantFreshGlucose = false;
        _asks = 0;
        _askSince = 0;
        testSent = [];
        testTransmitFails = false;
    }

    // MARK: Decisions, each from `now` so tests drive them.

    // A poll should go out now: none is outstanding, or the outstanding one has waited long enough to be
    // a miss (which is counted).
    function pollDue(now as Lang.Number) as Lang.Boolean {
        if (_pollSentAt == 0) { return true; }
        // A clock stepped back counts the outstanding poll as missed rather than wait for it to catch up.
        if (now - _pollSentAt >= REPLY_SEC || now < _pollSentAt) {
            missed();
            return true;
        }
        return false;
    }

    // The wait before the next poll: 15 s, doubling with each miss in a row, at most two minutes.
    function delayMs() as Lang.Number {
        var d = POLL_MS;
        for (var i = 0; i < _misses && d < MAX_POLL_MS; i += 1) { d *= 2; }
        return (d > MAX_POLL_MS) ? MAX_POLL_MS : d;
    }

    function misses() as Lang.Number { return _misses; }

    function outstanding() as Lang.Boolean { return _pollSentAt != 0; }

    // The phone app has answered within the last minute: the Bluetooth link alone says nothing about
    // whether faBolus is running on the phone. Both clocks must say so; with the wall clock stepped back past
    // the moment it was heard, uptime alone says, so a stepped-back clock neither makes a silent phone live
    // nor a talking one dead.
    function phoneLive(now as Lang.Number) as Lang.Boolean {
        return _heardAt > 0 && recent(now - _heardAt, System.getTimer() - _heardMs);
    }

    // Since the phone was last heard from, by the wall clock (s) and by uptime (ms). A wall clock behind the
    // moment it was heard has been stepped back and says nothing, so uptime decides. A wrapped timer reads
    // negative and is ignored, unless it's all there is: then nothing says the phone is live.
    function recent(wallSec as Lang.Number, uptimeMs as Lang.Number) as Lang.Boolean {
        if (wallSec < 0) { return uptimeMs >= 0 && uptimeMs <= LIVE_SEC * 1000; }
        return wallSec <= LIVE_SEC && (uptimeMs < 0 || uptimeMs <= LIVE_SEC * 1000);
    }

    // The phone's messages arrive but the watch's don't reach it: several asks it always answers went
    // unanswered, while it was heard from well after the first of them, so it was there to answer. Seen
    // after a sideload, until the watch was restarted; nothing on the phone or in Garmin Connect cleared it.
    // A message lost now and then never adds up to this, as any answer starts the count again.
    function oneWay(now as Lang.Number) as Lang.Boolean {
        return _asks >= ONE_WAY_ASKS && _heardAt - _askSince >= ONE_WAY_SEC && phoneLive(now);
    }

    // What the user is told, unless the phone's setting mutes it. Detection goes on either way, so a muted
    // watch still asks for the chart until the phone answers.
    function sayOneWay(now as Lang.Number) as Lang.Boolean { return oneWay(now) && !Prefs.muteOneWayNotice(); }

    function phoneTooOld() as Lang.Boolean { return _phoneTooOld; }
    function watchTooOld() as Lang.Boolean { return _watchTooOld; }

    // MARK: Events.

    // A version 2 message from the phone, sent just now.
    function heard(now as Lang.Number) as Void {
        _heardAt = now;
        _heardMs = System.getTimer();
        _pollSentAt = 0;
        _misses = 0;
        speaksVersion2();
    }

    // A version 2 message read, however old: the phone app speaks this watch's version. Unlike hearing from
    // it, this doesn't depend on when the message was sent.
    function speaksVersion2() as Void {
        _phoneTooOld = false;
        _watchTooOld = false;
    }

    // The phone was heard from at `at` (Status.heardTime), told now. A message Connect IQ held can arrive
    // long after the phone sent it, so only a recent time counts, and it never moves the last-heard time
    // back, unless the wall clock is now behind that time: it was stepped back (set from the phone), and the
    // stored time means nothing on it any more.
    function heardAt(at as Lang.Number?, now as Lang.Number) as Void {
        if (at != null && at <= now && now - at <= LIVE_SEC && (at >= _heardAt || now < _heardAt)) {
            heard(at);
            _heardMs -= (now - at) * 1000;
        }
    }

    // A message from the old phone app: it can't read this watch's messages.
    function heardLegacy(now as Lang.Number) as Void {
        _pollSentAt = 0;
        _phoneTooOld = true;
    }

    // The phone runs a newer protocol.
    function heardNewer(now as Lang.Number) as Void {
        _pollSentAt = 0;
        _watchTooOld = true;
    }

    // A message the phone always answers was handed over: a bolus request, which it answers at once with at
    // least "received", or a poll asking for the chart, which it answers with one. Statuses can't count:
    // the phone sends them unasked.
    function asked(now as Lang.Number) as Void {
        if (_asks == 0 || now < _askSince) { _askSince = now; }
        _asks += 1;
    }

    // The phone answered one: what the watch sends reaches it.
    function answered() as Void {
        _asks = 0;
        _askSince = 0;
    }

    // The chart arrived. The ask stands until then, so a lost poll asks again rather than leave the chart
    // unfilled until the next reopen.
    function historyArrived() as Void {
        _wantHistory = false;
        answered();
    }

    function missed() as Void {
        _pollSentAt = 0;
        if (_misses < 4) { _misses += 1; }
    }

    // A transmit error for the poll sent at `sentAt`. An error for an earlier poll, arriving after the next
    // one went out, is that one's and was already counted.
    function pollFailed(sentAt as Lang.Number) as Void {
        if (_pollSentAt != 0 && _pollSentAt == sentAt) { missed(); }
    }

    // The next poll also asks for history, or a fresh CGM read before the reply.
    function wantHistory() as Void { _wantHistory = true; }
    function wantFreshGlucose() as Void { _wantFreshGlucose = true; }

    // Sends a poll now, naming the config revision the watch holds and the bolus request it waits on.
    function poll(now as Lang.Number) as Lang.Boolean {
        // While the asks add up to a one-way link the poll asks for the chart too, so a link that's back
        // proves it with the answer rather than wait for the next bolus.
        var askHistory = _wantHistory || _asks >= ONE_WAY_ASKS;
        var msg = Wire.poll(Prefs.revision(), BolusFlow.awaitingId(now), askHistory, _wantFreshGlucose);
        _pollSentAt = now;
        var sent = hand(msg, new SendListener(new Lang.Method(Link, :pollFailed), now));
        if (sent) {
            if (askHistory) { asked(now); }
            _wantFreshGlucose = false;
        } else {
            missed();
        }
        return sent;
    }

    // MARK: Transmit.

    // The phone can take a message: the watch's Bluetooth flag says a phone is connected, or faBolus was
    // heard from within LIVE_SEC. The flag alone isn't enough: it can say no phone while faBolus's messages
    // still arrive, and a message just heard shows the link works.
    function reachable(now as Lang.Number) as Lang.Boolean { return phoneLive(now) || phoneConnected(); }

    // The watch's Bluetooth flag alone.
    function phoneConnected() as Lang.Boolean {
        var t = testReachable;
        if (t != null) { return t; }
        return System.getDeviceSettings().phoneConnected;
    }

    // Hands a message to Connect IQ. False when the phone isn't reachable or the transmit throws; a
    // failure after it was handed over comes to the listener.
    function transmit(msg as Lang.Dictionary, listener as Comm.ConnectionListener, now as Lang.Number) as Lang.Boolean {
        if (!reachable(now)) { return false; }
        return hand(msg, listener);
    }

    // Hands a message to Connect IQ whatever the Bluetooth flag says: for polls and cancels, which cost
    // nothing to try. With no phone the listener hears the error. False when the transmit throws.
    function hand(msg as Lang.Dictionary, listener as Comm.ConnectionListener) as Lang.Boolean {
        try {
            if (testTransmitFails) { throw new Lang.Exception(); }
            if (testSuppressTransmit) {
                testSent.add(msg);
            } else {
                Comm.transmit(msg as Comm.TransmitType, null, listener);
            }
            return true;
        } catch (e) {
            return false;
        }
    }

    // A request ID unique across restarts and the app's processes: a sequence kept in storage, folded
    // with the clock. Bolus and cancel requests use it.
    function newRequestId(now as Lang.Number) as Lang.String {
        var seq = Storage.getValue(Store.REQUEST_SEQ);
        var next = (seq instanceof Lang.Number) ? seq + 1 : 1;
        // A full storage doesn't stop the request: the clock and the timer still make the ID unique.
        Store.save(Store.REQUEST_SEQ, next);
        return now.toString() + "-" + next.toString() + "-" + (System.getTimer() % 1000000).toString();
    }

    // For dismisses, which the phone dedups but never doses from: no storage write.
    var _routine as Lang.Number = 0;
    function newRoutineId(now as Lang.Number) as Lang.String {
        _routine += 1;
        return now.toString() + "-r" + _routine.toString() + "-" + (System.getTimer() % 1000000).toString();
    }

    // Some jitter, so the watch's polls don't fall in step with the phone's pushes.
    function jitterMs() as Lang.Number { return (Math.rand() % 4000).abs(); }
}

// Polls, dismisses and cancels: a transmit error after the hand-over goes to `onError` with the token of
// the message it belongs to, so a late error for an earlier message can't change the current one.
class SendListener extends Comm.ConnectionListener {
    private var _onError as Lang.Method;
    private var _token as Lang.Number or Lang.String;
    function initialize(onError as Lang.Method, token as Lang.Number or Lang.String) {
        ConnectionListener.initialize();
        _onError = onError;
        _token = token;
    }
    function onComplete() as Void {}
    function onError() as Void {
        _onError.invoke(_token);
        Ui.requestUpdate();
    }
}
