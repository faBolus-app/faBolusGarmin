using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.System;
using Toybox.Math;

// Bolus entry input, portable across devices:
//   • Touch  — onTap hit-tests the drawn controls (− / + / mode chip / Deliver).
//   • Buttons — up/down move the focus cursor, START activates the focused control.
// Both routes funnel through act(), so the behavior is identical however it was triggered.
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
        if (nearCircle(c, BolusEntryView.minusCenter(w, h), BolusEntryView.stepRadius(w))) { return act(1); }
        if (nearCircle(c, BolusEntryView.plusCenter(w, h), BolusEntryView.stepRadius(w))) { return act(2); }
        if (inRect(c, BolusEntryView.chipRect(w, h))) { return act(0); }
        if (inRect(c, BolusEntryView.deliverRect(w, h))) { return act(3); }
        return true;
    }

    // Buttons: move the focus cursor and activate it. (This is a modal view, so up/down are free
    // to move focus rather than change screens.)
    function onNextPage() as Lang.Boolean {
        _view.focus = (_view.focus + 1) % BolusEntryView.TARGET_COUNT;
        Ui.requestUpdate(); return true;
    }
    function onPreviousPage() as Lang.Boolean {
        _view.focus = (_view.focus + BolusEntryView.TARGET_COUNT - 1) % BolusEntryView.TARGET_COUNT;
        Ui.requestUpdate(); return true;
    }
    function onSelect() as Lang.Boolean { return act(_view.focus); }

    // 0 = mode chip, 1 = minus, 2 = plus, 3 = deliver.
    private function act(target as Lang.Number) as Lang.Boolean {
        if (target == 0) { AppState.toggleMode(); Ui.requestUpdate(); return true; }
        if (target == 1) { AppState.adjust(-1); Ui.requestUpdate(); return true; }
        if (target == 2) { AppState.adjust(1); Ui.requestUpdate(); return true; }
        AppState.deliverUnits = AppState.computeUnits();
        if (AppState.deliverUnits < 0.05) { return true; }   // nothing to deliver
        var v = new HoldView();
        Ui.pushView(v, new HoldDelegate(v), Ui.SLIDE_LEFT);
        return true;
    }
}
