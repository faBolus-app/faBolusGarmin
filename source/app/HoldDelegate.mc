using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.System;
using Toybox.Math;
using Toybox.Timer;

// Confirm-screen input.
//   • Touch (venu3s): tap the numbered circles 1 → 2 → 3 in order (the view enforces the order).
//   • Buttons: a deliberate two-DIFFERENT-button hold — hold UP for ~1.5s to ARM, then hold START
//     for ~1.5s to DELIVER. Releasing either early cancels that hold. Because it needs two distinct
//     buttons each held for a sustained period, a bolus can't be triggered by tapping one button
//     repeatedly. (The phone still enforces its own confirm + max-bolus interlock regardless.)
class HoldDelegate extends Ui.BehaviorDelegate {
    private const HOLD_MS = 1500;
    private var _view as HoldView;
    private var _timer as Timer.Timer?;
    private var _holdingKey as Lang.Number?;      // key currently held (null = none)
    private var _holdStart as Lang.Number = 0;    // System.getTimer() ms when the hold began

    function initialize(view as HoldView) { BehaviorDelegate.initialize(); _view = view; }

    // --- Touch (venu3s): unchanged 1-2-3 tap sequence ---
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        if (AppState.status != null) {
            if (AppState.status.equals("delivering")) {
                var cr = HoldView.cancelRect(w, h);
                if (c[0] >= cr[0] && c[0] <= cr[0] + cr[2] && c[1] >= cr[1] && c[1] <= cr[1] + cr[3]) {
                    cancelDelivery();
                }
            }
            return true;
        }
        var r = HoldView.radius(w);
        for (var i = 0; i < 3; i += 1) {
            var ctr = HoldView.center(i, w, h);
            var dx = c[0] - ctr[0], dy = c[1] - ctr[1];
            if (Math.sqrt(dx * dx + dy * dy) <= r * 1.3) { _view.tapped(i + 1); return true; }
        }
        return true;
    }

    // --- Buttons: two-different-button hold (only on button devices) ---
    function onKeyPressed(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (AppState.status != null) {
            if (AppState.status.equals("delivering") && (k == Ui.KEY_ENTER || k == Ui.KEY_START)) {
                cancelDelivery();
            }
            return true;
        }
        if (!_view.btnArmed && k == Ui.KEY_UP) { beginHold(k); return true; }               // ARM
        if (_view.btnArmed && (k == Ui.KEY_ENTER || k == Ui.KEY_START)) { beginHold(k); return true; }  // DELIVER
        return true;
    }

    function onKeyReleased(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        if (_holdingKey != null && evt.getKey() == _holdingKey) { cancelHold(); }
        return true;
    }

    // If the user backs out mid-hold, stop the timer (then let the default pop happen).
    function onBack() as Lang.Boolean { stopTimer(); return false; }

    private function beginHold(k as Lang.Number) as Void {
        _holdingKey = k;
        _holdStart = System.getTimer();
        _view.btnProgress = 0.0;
        stopTimer();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 80, true);
    }

    // Timer tick while a button is held: advance the fill; complete at 100%.
    function onTick() as Void {
        if (_holdingKey == null) { stopTimer(); return; }
        var elapsed = System.getTimer() - _holdStart;
        var frac = elapsed.toFloat() / HOLD_MS;
        if (frac >= 1.0) {
            var wasArm = (_holdingKey == Ui.KEY_UP);
            _holdingKey = null; _view.btnProgress = 0.0; stopTimer();
            if (wasArm) { _view.btnArmed = true; } else { _view.confirmDeliver(); }
            Ui.requestUpdate();
            return;
        }
        _view.btnProgress = frac;
        Ui.requestUpdate();
    }

    private function cancelHold() as Void {
        _holdingKey = null; _view.btnProgress = 0.0; stopTimer(); Ui.requestUpdate();
    }
    private function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }
    private function cancelDelivery() as Void {
        if (AppState.pendingRequestId != null) {
            RemoteComm.send(RemoteComm.cancelBolus(AppState.pendingRequestId));
        }
        AppState.status = "cancelling"; Ui.requestUpdate();
    }
}
