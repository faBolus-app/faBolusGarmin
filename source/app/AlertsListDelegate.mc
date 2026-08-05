using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Lang;

// Tapping an alert row sends a dismiss to the phone (which signs + clears it on the pump).
class AlertsListDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    private function inRect(c, r) {
        return c[0] >= r[0] && c[0] <= r[0] + r[2] && c[1] >= r[1] && c[1] <= r[1] + r[3];
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        var n = AppState.alerts.size();
        var shown = (n < AlertsListView.MAX_ROWS) ? n : AlertsListView.MAX_ROWS;
        for (var i = 0; i < shown; i += 1) {
            if (inRect(c, AlertsListView.rowRect(i, w, h))) {
                var a = AppState.alerts[i] as Lang.Dictionary;
                // Confirm before clearing — SYMMETRIC with the button path (onSelect). Clearing a pump
                // alert is a real action (the phone sends a signed dismiss to the pump), so a touch must
                // go through the same AlertConfirmDelegate the buttons use, not fire-and-clear on tap.
                Ui.pushView(new Ui.Confirmation("Clear: " + a["title"] + "?"),
                            new AlertConfirmDelegate(a["id"], a["kind"]), Ui.SLIDE_UP);
                return true;
            }
        }
        return true;
    }

    // Buttons: START opens a confirm to clear the top (most-serious) alert. (Up/down are used for
    // page navigation here, so button devices act on the top alert rather than a moving row cursor;
    // repeated presses clear them most-serious first.)
    function onSelect() as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }   // touch clears via onTap (tap the row)
        if (AppState.alerts.size() == 0) { return true; }
        var a = AppState.alerts[0] as Lang.Dictionary;
        Ui.pushView(new Ui.Confirmation("Clear: " + a["title"] + "?"),
                    new AlertConfirmDelegate(a["id"], a["kind"]), Ui.SLIDE_UP);
        return true;
    }

    // Swipe between screens in the user-configured order.
    function onNextPage() as Lang.Boolean { return Nav.goNext("alerts"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("alerts"); }
}
