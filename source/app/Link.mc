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
// polls in a row went unanswered, and when the phone was last heard from. Any message from the phone
// answers. A transmit error counts as an unanswered poll. Every wait is bounded, so the link always
// polls again and never stops for good.
module Link {
    const POLL_MS = 15000;
    const MAX_POLL_MS = 120000;
    // A poll unanswered this long counts as a miss.
    const REPLY_SEC = 12;
    // The phone app counts as answering while it was heard from this recently.
    const LIVE_SEC = 60;

    var _pollSentAt as Lang.Number = 0;
    var _misses as Lang.Number = 0;
    var _heardAt as Lang.Number = 0;
    // Set by a message from another protocol version, until a version 2 message arrives.
    var _phoneTooOld as Lang.Boolean = false;
    var _watchTooOld as Lang.Boolean = false;
    // What the next poll asks for.
    var _wantHistory as Lang.Boolean = false;
    var _wantFreshGlucose as Lang.Boolean = false;

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
        _phoneTooOld = false;
        _watchTooOld = false;
        _wantHistory = false;
        _wantFreshGlucose = false;
        testSent = [];
        testTransmitFails = false;
    }

    // MARK: Decisions, each from `now` so tests drive them.

    // A poll should go out now: none is outstanding, or the outstanding one has waited long enough to be
    // a miss (which is counted).
    function pollDue(now as Lang.Number) as Lang.Boolean {
        if (_pollSentAt == 0) { return true; }
        if (now - _pollSentAt >= REPLY_SEC) {
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
    // whether faBolus is running on the phone.
    function phoneLive(now as Lang.Number) as Lang.Boolean {
        return _heardAt > 0 && now - _heardAt <= LIVE_SEC;
    }

    function phoneTooOld() as Lang.Boolean { return _phoneTooOld; }
    function watchTooOld() as Lang.Boolean { return _watchTooOld; }

    // MARK: Events.

    // A version 2 message from the phone.
    function heard(now as Lang.Number) as Void {
        _heardAt = now;
        _pollSentAt = 0;
        _misses = 0;
        _phoneTooOld = false;
        _watchTooOld = false;
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
        var msg = Wire.poll(Prefs.revision(), BolusFlow.awaitingId(now), _wantHistory, _wantFreshGlucose);
        _pollSentAt = now;
        var sent = transmit(msg, new SendListener(new Lang.Method(Link, :pollFailed), now));
        if (sent) {
            _wantHistory = false;
            _wantFreshGlucose = false;
        } else {
            missed();
        }
        return sent;
    }

    // MARK: Transmit.

    function reachable() as Lang.Boolean {
        var t = testReachable;
        if (t != null) { return t; }
        return System.getDeviceSettings().phoneConnected;
    }

    // Hands a message to Connect IQ. False when the phone isn't connected or the transmit throws; a
    // failure after it was handed over comes to the listener.
    function transmit(msg as Lang.Dictionary, listener as Comm.ConnectionListener) as Lang.Boolean {
        if (!reachable()) { return false; }
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
