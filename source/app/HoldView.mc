using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Timer;

// Confirm screen. Two deliberate-input models, chosen by device:
//   • Touch (venu3s): tap the numbered targets 1 → 2 → 3 in order (a wrong tap resets).
//   • Buttons: hold UP to ARM, then hold START to DELIVER — two DIFFERENT buttons, each held for
//     ~1.5s (releasing early cancels). A bolus can't be triggered by repeated presses of one button.
// Either way it takes sustained, deliberate action. Once sent, shows delivery status.
class HoldView extends Ui.View {
    private var _progress as Lang.Number = 0;      // touch: correct taps so far (0..3)
    public var btnArmed as Lang.Boolean = false;   // buttons: UP-hold completed
    public var btnProgress as Lang.Float = 0.0;    // buttons: current hold fill (0..1)
    // After a successful delivery, auto-return to the configured first screen (once).
    private var _homeTimer as Timer.Timer or Null = null;
    private var _returnScheduled as Lang.Boolean = false;

    function initialize() { View.initialize(); }

    // Cancel the auto-return timer if we leave the screen before it fires.
    function onHide() as Void { stopHomeTimer(); }
    private function stopHomeTimer() as Void {
        if (_homeTimer != null) { _homeTimer.stop(); _homeTimer = null; }
    }

    // Fired 2 s after "delivered": dismiss the bolus flow and open the user's first screen.
    function goHome() as Void {
        stopHomeTimer();
        AppState.reset();
        Ui.popView(Ui.SLIDE_IMMEDIATE);                     // drop this (Hold) view → Bolus entry
        var vd = Nav.initialView();                         // the configured first screen
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_RIGHT);      // replace Bolus entry with it
    }

    // Circle centers/radius (pixels) for the touch 1-2-3 targets, shared with the delegate.
    static function center(i, w, h) {
        var xs = [0.23, 0.50, 0.77];
        return [ (w * xs[i]).toNumber(), (h * 0.50).toNumber() ];
    }
    static function radius(w) { return (w * 0.11).toNumber(); }

    // Cancel button (shown while delivering). [x,y,w,h].
    static function cancelRect(w, h) { return [w / 2 - w * 0.26, h * 0.66, w * 0.52, h * 0.15]; }

    function progress() as Lang.Number { return _progress; }

    // P15 §2.3 / G4: if the phone flipped read-only ON or Garmin bolusing OFF while this confirm screen
    // was armed but the bolus hasn't been sent yet, DE-ARM immediately — clear the button-hold state
    // (btnArmed/btnProgress) and the touch tap-sequence (_progress). AppState.reset() ALONE can't: that
    // armed progress is view-local, not in AppState. Also drop the half-entered compose (reset()), so a
    // completed hold/tap can't fire a bolus the host just disabled. Returns true when it tore down, so
    // onUpdate draws the disabled notice instead of the confirm controls. Deterministic decision lives
    // in AppState.mustTeardownArmedBolus() (unit-tested); this just applies it to the view-local state.
    function disabledMidArm() as Lang.Boolean {
        if (!AppState.mustTeardownArmedBolus()) { return false; }
        _progress = 0; btnArmed = false; btnProgress = 0.0;
        AppState.reset();
        return true;
    }

    // Touch: register a tap on button number `num` (1..3).
    function tapped(num as Lang.Number) as Void {
        if (AppState.status != null) { return; }
        if (num == _progress + 1) {
            _progress += 1;
            if (_progress >= 3) { deliver(); }
        } else {
            _progress = 0;   // out of order — start over
        }
        Ui.requestUpdate();
    }

    // Buttons: the delegate calls this once the START hold completes.
    function confirmDeliver() as Void {
        if (AppState.status == null) { deliver(); }
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2, cy = h / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        if (AppState.status != null) {
            var s = AppState.status as Lang.String;
            var color = Gfx.COLOR_BLUE;
            if (s.equals("delivered")) {
                color = Gfx.COLOR_GREEN;
                // Show the green "delivered" briefly, then return to the first screen.
                if (!_returnScheduled) {
                    _returnScheduled = true;
                    _homeTimer = new Timer.Timer();
                    _homeTimer.start(method(:goHome), 2000, false);
                }
            }
            // Cancelled stays on screen (orange, no auto-return) so an accidental cancel isn't missed —
            // the user backs out deliberately.
            else if (s.equals("cancelled")) { color = Gfx.COLOR_ORANGE; }
            else if (s.equals("failed") || s.equals("outOfRange")) { color = Gfx.COLOR_RED; }
            // FB-02/GA-03: sent but outcome not known — caution color, stays on screen (no auto-return).
            else if (s.equals("unknown")) { color = Gfx.COLOR_YELLOW; }
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.30, Gfx.FONT_MEDIUM, s, Gfx.TEXT_JUSTIFY_CENTER);
            // On a terminal outcome, show how much insulin actually went in — the amount the phone
            // reported (deliveredUnits → AppState.lastBolus). Especially important on "cancelled",
            // where the user needs to know the partial dose delivered before the cancel landed.
            if ((s.equals("cancelled") || s.equals("delivered")) && AppState.lastBolus >= 0.0) {
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.44, Gfx.FONT_XTINY,
                            AppState.lastBolus.format("%.2f") + " U delivered", Gfx.TEXT_JUSTIFY_CENTER);
            } else if (AppState.message != null) {
                dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.44, Gfx.FONT_XTINY, AppState.message, Gfx.TEXT_JUSTIFY_CENTER);
            }
            if (s.equals("delivering") || s.equals("cancelling")) {
                var cr = cancelRect(w, h);
                dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(cr[0], cr[1], cr[2], cr[3], 10);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, cr[1] + cr[3] / 2, Gfx.FONT_SMALL,
                            DeviceProfile.isButtons() ? "Cancel (START)" : "Cancel",
                            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.80, Gfx.FONT_XTINY, "BACK to exit", Gfx.TEXT_JUSTIFY_CENTER);
            }
            return;
        }

        // P15 §2.3 / G4: a mid-arm disable (read-only ON or Garmin bolusing OFF, just pushed from the
        // phone) tears down the primed confirm and says why — instead of leaving an armed hold/tap that
        // could still fire. Only reached pre-delivery (status == null); an in-flight bolus is untouched.
        if (disabledMidArm()) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.40, Gfx.FONT_SMALL, "Bolusing off", vc);
            dc.drawText(cx, h * 0.54, Gfx.FONT_XTINY, "(disabled on phone)", vc);
            dc.drawText(cx, h * 0.80, Gfx.FONT_XTINY, "BACK to exit", vc);
            return;
        }

        // Dose, top.
        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.14, Gfx.FONT_SMALL, AppState.deliverUnits.format("%.2f") + " U", vc);

        if (DeviceProfile.isButtons()) {
            drawButtonConfirm(dc, w, h, cx, vc);
        } else {
            drawTouchConfirm(dc, w, h, cx, vc);
        }

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY, "experimental", vc);
    }

    // Touch: the 1-2-3 circles.
    private function drawTouchConfirm(dc, w, h, cx, vc) as Void {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.28, Gfx.FONT_XTINY, "Tap 1 - 2 - 3 in order", vc);
        var r = radius(w);
        for (var i = 0; i < 3; i += 1) {
            var c = center(i, w, h);
            var done = (i + 1) <= _progress;
            dc.setColor(done ? Gfx.COLOR_GREEN : 0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(c[0], c[1], r);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(c[0], c[1], Gfx.FONT_NUMBER_MEDIUM, (i + 1).toString(), vc);
        }
    }

    // Buttons: two-step hold. Step 1 = hold UP to arm; step 2 = hold START to deliver.
    private function drawButtonConfirm(dc, w, h, cx, vc) as Void {
        var step1 = btnArmed ? "1. armed" : "1. Hold UP to arm";
        var step2 = btnArmed ? "2. Hold START to deliver" : "2. then hold START";
        dc.setColor(btnArmed ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.34, Gfx.FONT_XTINY, step1, vc);
        dc.setColor(btnArmed ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.48, Gfx.FONT_XTINY, step2, vc);

        // Hold-progress bar.
        var bx = w * 0.22, bw = w * 0.56, by = h * 0.62, bh = h * 0.06;
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, bw, bh, 4);
        if (btnProgress > 0.0) {
            var fillW = bw * btnProgress;
            dc.setColor(btnArmed ? Gfx.COLOR_GREEN : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, fillW, bh, 4);
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.76, Gfx.FONT_XTINY, "release cancels", vc);
    }

    private function deliver() as Void {
        // C2 §2.3: the no-passcode confirm path. Delivery/reqId/reachability/status semantics + the P15
        // §2.3 / G4 policy-disabled hard guard all live in the SHARED funnel AppState.sendBolusNow() so
        // this path and the passcode path (PasscodeEntryView) send identically. This is the tap/hold
        // confirm, so no passcode is ever collected here → pass null.
        //
        // The funnel returns false ONLY when the hard guard blocked the send (read-only or Garmin bolusing
        // OFF pushed while this screen was armed): even a confirm that completed in the same frame as the
        // disabling push must fire NOTHING — the host would refuse it anyway (AccessPolicy); the wrist
        // doesn't even try. De-arm the view-local confirm state so the next redraw shows the disabled
        // notice (disabledMidArm()). On true, status now owns the screen (delivering / outOfRange).
        if (!AppState.sendBolusNow(null)) {
            _progress = 0; btnArmed = false; btnProgress = 0.0;
        }
    }
}
