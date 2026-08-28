using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Lang;
using Toybox.Time;

// Glance input: tap the Bolus button (only) to open bolus entry. The top physical button
// (SELECT) is also a shortcut. Tapping elsewhere on the glance does nothing.
class MainDelegate extends Ui.BehaviorDelegate {
    private var _showBolus as Lang.Boolean;
    private var _screenId as Lang.String;
    function initialize(showBolus as Lang.Boolean, screenId as Lang.String) {
        BehaviorDelegate.initialize();
        _showBolus = showBolus;
        _screenId = screenId;
    }

    // Bolus-button press: cancel an in-flight bolus, open bolus entry, or do nothing (disabled) —
    // matching the button's appearance in MainView. Kept non-private (mirrors FaBolusApp.pollTick /
    // scheduleCount) so tests/BolusSendFailedTest.mc + tests/OutcomeWatchdogTest.mc can drive the real
    // cancel path directly — onTap's Ui.ClickEvent (and onSelect/onKey's DeviceProfile.isTouch() gate on
    // a touch device like venu3s) have no test-constructible/test-controllable path in.
    function pressBolusButton() as Lang.Boolean {
        // No bolus button on the CGM-only screen: swallow the input.
        if (!_showBolus) { return true; }
        // GA-02: read-only must block STARTING a bolus, but NEVER block CANCELLING one already in
        // flight — cancel is a safety action. So check canCancel() BEFORE the read-only gate.
        if (AppState.canCancel()) {
            // CX-G-04/C5-04: honor RemoteComm.send()'s Bool — mirrors the sibling failed-transmit
            // handling (AppState.sendBolusNow / noteBolusSendFailed, VA-12). On a failed dispatch, do
            // NOT flip to "cancelling" (that would look done and non-retryable — canCancel() itself
            // doesn't consult `status`, only bolusing()+pendingRequestId, so leaving status untouched
            // keeps the cancel retryable) and surface an error via `message`. On a successful dispatch,
            // set "cancelling" AND re-stamp `outcomeSentEpoch` — copied verbatim from
            // HoldDelegate.cancelDelivery — since a cancel REQUEST isn't a confirmed cancellation and
            // needs its own watchdog deadline if no terminal echo arrives. Do NOT extend RemoteComm.mc's
            // routine-caller send()-ignore exemption to this path.
            var dispatched = RemoteComm.send(RemoteComm.cancelBolus(AppState.pendingRequestId as Lang.String));
            if (dispatched) {
                AppState.status = "cancelling";
                AppState.outcomeSentEpoch = Time.now().value();
            } else {
                AppState.message = "Cancel failed — try again.";
            }
            // Transient toast for this NON-ack status feedback (additive — the persistent
            // AppState.message error above is untouched, so BolusSendFailedTest still holds).
            // The cancel Confirmation and any dose/alert-clear acknowledgment surface stay full Ui views.
            Toast.show(Toast.cancelFeedback(dispatched));
            Ui.requestUpdate();
            return true;
        }
        // Read-only (or a hidden button): don't open bolus entry.
        if (AppState.readOnly) { return true; }
        // Inert when bolusing isn't possible (phone unreachable or pump disconnected) — matches the
        // greyed button. Swallow the input so nothing opens.
        if (!AppState.canBolus()) { return true; }
        Nav.openBolusEntry();   // resets + shows the G5 one-time notice on first use
        return true;
    }

    // Only a tap inside the Bolus button opens the bolus screen (matches MainView geometry).
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        var bw = w * 0.52, bh = h * 0.17;
        var bx = (w - bw) / 2, by = h * 0.68;
        if (c[0] >= bx && c[0] <= bx + bw && c[1] >= by && c[1] <= by + bh) {
            return pressBolusButton();
        }
        return true;   // swallow taps elsewhere so the glance doesn't jump to bolus
    }

    // GA-06: on a touch device a tap is ALSO delivered as onSelect/onKey. Suppress the physical-button
    // handlers there (return false → fall through to the validated onTap path) so a single tap can't
    // double-route into pressBolusButton().
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return pressBolusButton(); }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return pressBolusButton(); }
        return false;
    }

    // Swipe between screens in the user-configured order (default: glance → alerts → history → details).
    function onNextPage() as Lang.Boolean { return Nav.goNext(_screenId); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev(_screenId); }
}
