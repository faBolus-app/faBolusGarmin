using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Lang;

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
    // matching the button's appearance in MainView.
    private function pressBolusButton() as Lang.Boolean {
        // No bolus button on the CGM-only screen: swallow the input.
        if (!_showBolus) { return true; }
        // GA-02: read-only must block STARTING a bolus, but NEVER block CANCELLING one already in
        // flight — cancel is a safety action. So check canCancel() BEFORE the read-only gate.
        if (AppState.canCancel()) {
            RemoteComm.send(RemoteComm.cancelBolus(AppState.pendingRequestId as Lang.String));
            AppState.status = "cancelling";
            Ui.requestUpdate();
            return true;
        }
        // Read-only (or a hidden button): don't open bolus entry.
        if (AppState.readOnly) { return true; }
        // Inert when bolusing isn't possible (phone unreachable or pump disconnected) — matches the
        // greyed button. Swallow the input so nothing opens.
        if (!AppState.canBolus()) { return true; }
        AppState.reset();
        var v = new BolusEntryView();
        Ui.pushView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
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

    function onSelect() as Lang.Boolean { return pressBolusButton(); }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return pressBolusButton(); }
        return false;
    }

    // Swipe between screens in the user-configured order (default: glance → alerts → history → details).
    function onNextPage() as Lang.Boolean { return Nav.goNext(_screenId); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev(_screenId); }
}
