using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.System;
using Toybox.Math;

// Bolus entry input, portable across devices:
//   • Touch (venu3s): onTap hit-tests the drawn controls (− / + / mode chip / Deliver).
//   • Buttons: UP / DOWN adjust the amount directly, MENU toggles Units/Carbs, START delivers —
//     button-native, no on-screen focus cursor.
class BolusEntryDelegate extends Ui.BehaviorDelegate {
    private var _view as BolusEntryView;
    function initialize(view as BolusEntryView) { BehaviorDelegate.initialize(); _view = view; }

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
        if (nearCircle(c, BolusEntryView.minusCenter(w, h), BolusEntryView.stepRadius(w))) { AppState.adjust(-1); Ui.requestUpdate(); return true; }
        if (nearCircle(c, BolusEntryView.plusCenter(w, h), BolusEntryView.stepRadius(w))) { AppState.adjust(1); Ui.requestUpdate(); return true; }
        if (inRect(c, BolusEntryView.chipRect(w, h))) { AppState.toggleMode(); Ui.requestUpdate(); return true; }
        if (inRect(c, BolusEntryView.deliverRect(w, h))) { return deliver(); }
        return true;
    }

    // Buttons: UP = increase, DOWN = decrease, MENU = switch mode, START = deliver.
    // Gated to button devices — on a touchscreen a tap is ALSO delivered as onSelect/next-page
    // behaviors, which would otherwise hijack every tap. Returning false lets touch fall through to
    // onTap (the validated touch path).
    function onPreviousPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.adjust(1); Ui.requestUpdate(); return true; }   // UP
    function onNextPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.adjust(-1); Ui.requestUpdate(); return true; }       // DOWN
    function onMenu() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.toggleMode(); Ui.requestUpdate(); return true; }
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return deliver(); }

    private function deliver() as Lang.Boolean {
        // FB-01: never deliver a carb bolus when the calculator inputs haven't synced from the phone —
        // the wrist would otherwise dose off an unverified assumption. Block + tell the user.
        if (!AppState.carbCalcAvailable()) {
            AppState.message = "Calculator unavailable — open faBolus on the phone.";
            Ui.requestUpdate();
            return true;
        }
        AppState.deliverUnits = AppState.computeUnits();
        if (AppState.deliverUnits < 0.05) { return true; }   // nothing to deliver
        var v = new HoldView();
        Ui.pushView(v, new HoldDelegate(v), Ui.SLIDE_LEFT);
        return true;
    }
}
