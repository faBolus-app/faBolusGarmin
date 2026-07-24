using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Lang;

// Bolus-only screen input: the whole centered button responds to tap / SELECT; swipe moves between
// screens. Mirrors MainDelegate's bolus logic but with the centered geometry of BolusOnlyView.
class BolusOnlyDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    private function pressBolusButton() as Lang.Boolean {
        // GA-02: cancelling an in-flight bolus must work even in read-only (check it BEFORE the gate).
        if (AppState.canCancel()) {
            RemoteComm.send(RemoteComm.cancelBolus(AppState.pendingRequestId as Lang.String));
            AppState.status = "cancelling";
            Ui.requestUpdate();
            return true;
        }
        if (AppState.readOnly) { return true; }      // read-only blocks STARTING a bolus, not cancel
        if (!AppState.canBolus()) { return true; }   // inert when bolusing isn't possible
        AppState.reset();
        var v = new BolusEntryView();
        Ui.pushView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
        return true;
    }

    // Hit-test the centered button rect — keep in sync with BolusOnlyView.onUpdate geometry.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        var bw = w * 0.60, bh = h * 0.28;
        var bx = (w - bw) / 2, by = h / 2 - bh / 2;
        if (c[0] >= bx && c[0] <= bx + bw && c[1] >= by && c[1] <= by + bh) {
            return pressBolusButton();
        }
        return true;
    }

    // GA-06: on touch, a tap also fires onSelect/onKey — suppress them (fall through to onTap) so a
    // single tap can't double-route into pressBolusButton().
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return pressBolusButton(); }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return pressBolusButton(); }
        return false;
    }

    function onNextPage() as Lang.Boolean { return Nav.goNext("bolusonly"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("bolusonly"); }
}
