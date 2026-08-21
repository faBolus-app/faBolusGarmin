using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Math;
using Toybox.Lang;

// C2 §2.3 (Garmin half): input for the 4-digit bolus passcode entry (PasscodeEntryView). Portable across
// devices via the same both-input model + touch double-route guard as StaleBolusDelegate/HoldDelegate:
//   • Touch (e.g. venu3s): tap − / + to change the active digit, tap OK to commit-and-advance. The
//     physical-button handlers return false on a touch device so the tap falls through to the validated
//     onTap.
//   • Buttons: UP = +1, DOWN = -1, START/ENTER = commit-and-advance.
//   • Either: BACK deletes the last committed digit, or (when none) cancels back to bolus entry.
// On the 4th committed digit the code is complete: it is sent through the SHARED funnel
// AppState.sendBolusNow(code) — the identical delivery/reqId/reachability/status path HoldView uses — and
// we switch to HoldView to render the outcome. The WATCH never verifies or persists the code; the phone
// is the sole authority and denies a wrong/absent one.
class PasscodeEntryDelegate extends Ui.BehaviorDelegate {
    private var _view as PasscodeEntryView;
    function initialize(view as PasscodeEntryView) { BehaviorDelegate.initialize(); _view = view; }

    private function inRect(c, r) {
        return c[0] >= r[0] && c[0] <= r[0] + r[2] && c[1] >= r[1] && c[1] <= r[1] + r[3];
    }
    private function nearCircle(c, center, radius) {
        var dx = c[0] - center[0], dy = c[1] - center[1];
        return Math.sqrt(dx * dx + dy * dy) <= radius * 1.3;   // a little forgiving
    }

    // Touch: map the tapped coordinates to a control.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        if (nearCircle(c, PasscodeEntryView.minusCenter(w, h), PasscodeEntryView.stepRadius(w))) { _view.bump(-1); Ui.requestUpdate(); return true; }
        if (nearCircle(c, PasscodeEntryView.plusCenter(w, h), PasscodeEntryView.stepRadius(w))) { _view.bump(1); Ui.requestUpdate(); return true; }
        if (inRect(c, PasscodeEntryView.okRect(w, h))) { return commit(); }
        return true;
    }

    // Buttons: UP = +1, DOWN = -1, START = commit. Gated to button devices — on a touchscreen a tap is
    // ALSO delivered as onSelect / next-page, so those return false there and fall through to onTap.
    function onPreviousPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } _view.bump(1); Ui.requestUpdate(); return true; }   // UP
    function onNextPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } _view.bump(-1); Ui.requestUpdate(); return true; }     // DOWN
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return commit(); }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return commit(); }
        return false;
    }

    // BACK: delete the last committed digit; when nothing is entered, cancel — return false so the
    // framework pops this view back to bolus entry (NOTHING is sent). Clears the RAM buffer on cancel.
    function onBack() as Lang.Boolean {
        if (_view.backspace()) { Ui.requestUpdate(); return true; }
        _view.clearBuffer();
        return false;
    }

    // Commit the active digit; on the 4th it completes the code and sends.
    private function commit() as Lang.Boolean {
        if (_view.commit()) { submit(_view.code()); }
        else { Ui.requestUpdate(); }
        return true;
    }

    // Send the entered code through the SHARED funnel, then switch to HoldView to render the delivery
    // outcome. sendBolusNow sets status (delivering / outOfRange) — or, if bolusing was policy-disabled
    // mid-entry, leaves status null so HoldView's disabledMidArm() shows the "Bolusing off" notice. Either
    // way HoldView is the single outcome/status surface (its cancel / auto-return-home / lastBolus logic).
    // The RAM buffer is cleared BEFORE the send returns so no secret lingers on the wrist.
    private function submit(code as Lang.String) as Void {
        _view.clearBuffer();
        AppState.sendBolusNow(code);
        var v = new HoldView();
        Ui.switchToView(v, new HoldDelegate(v), Ui.SLIDE_LEFT);
    }
}
