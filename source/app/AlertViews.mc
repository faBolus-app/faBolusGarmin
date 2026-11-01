using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.WatchUi as Ui;

// The phone's active alerts. Tapping one asks to clear it on the pump when it can be cleared, and shows
// it otherwise.
class AlertsListView extends Ui.View {
    static const MAX_ROWS = 4;

    function initialize() { View.initialize(); }

    static function rowRect(i as Lang.Number, w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w * 0.12, h * (0.20 + 0.16 * i), w * 0.76, h * 0.15];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.13, Gfx.FONT_XTINY, "Alerts", vc);
        var list = Alerts.shown();
        if (list.size() == 0) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Gfx.FONT_SMALL, Status.present() ? "No alerts" : "Waiting for phone", vc);
            return;
        }
        var shown = (list.size() < MAX_ROWS) ? list.size() : MAX_ROWS;
        for (var i = 0; i < shown; i += 1) {
            var a = list[i] as Lang.Dictionary;
            var r = rowRect(i, w, h);
            var critical = Wire.text(a, "severity", "").equals("critical");
            dc.setColor(critical ? 0x4A0000 : 0x3A2A00, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 8);
            dc.setColor(critical ? Gfx.COLOR_RED : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_XTINY, Wire.text(a, "title", "Alert"), vc);
            if (!Nav.isTouch() && i == 0) {
                dc.setPenWidth(2);
                dc.drawRoundedRectangle(r[0], r[1], r[2], r[3], 8);
                dc.setPenWidth(1);
            }
        }
        var note = Alerts.note();
        dc.setColor(note != null ? Gfx.COLOR_ORANGE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY,
                    (note != null) ? note : (Nav.isTouch() ? "tap an alert" : "START: top alert"), vc);
    }
}

class AlertsListDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        var list = Alerts.shown();
        var n = (list.size() < AlertsListView.MAX_ROWS) ? list.size() : AlertsListView.MAX_ROWS;
        for (var i = 0; i < n; i += 1) {
            if (Nav.inRect(c[0], c[1], AlertsListView.rowRect(i, size[0], size[1]))) {
                Nav.pushAlert(list[i] as Lang.Dictionary);
                return true;
            }
        }
        return true;
    }

    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        var list = Alerts.shown();
        if (list.size() > 0) { Nav.pushAlert(list[0] as Lang.Dictionary); }
        return true;
    }

    function onNextPage() as Lang.Boolean { return Nav.goNext("alerts"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("alerts"); }
}

// "Clear: <alert>?" — the one dismiss path. Yes sends the dismiss; the alert stays listed until the pump
// confirms it cleared.
class AlertConfirmDelegate extends Ui.ConfirmationDelegate {
    private var _id as Lang.String;

    function initialize(id as Lang.String) {
        ConfirmationDelegate.initialize();
        _id = id;
    }

    function onResponse(response as Ui.Confirm) as Lang.Boolean {
        if (response == Ui.CONFIRM_YES) {
            Alerts.dismiss(_id, Status.now());
            Ui.requestUpdate();
        }
        return true;
    }
}

// An alert there's nothing to clear for on the watch: the phone's own, or one the pump won't let a remote
// dismiss.
class AlertNoticeView extends Ui.View {
    private var _alert as Lang.Dictionary;

    function initialize(alert as Lang.Dictionary) {
        View.initialize();
        _alert = alert;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var critical = Wire.text(_alert, "severity", "").equals("critical");
        dc.setColor(critical ? Gfx.COLOR_RED : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.30, Gfx.FONT_SMALL, Wire.text(_alert, "title", "Alert"), vc);
        var body = Wire.text(_alert, "body", "");
        if (body.length() > 0) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.56, Gfx.FONT_XTINY, Gfx.fitTextToArea(body, Gfx.FONT_XTINY, w * 0.80, h * 0.36, true), vc);
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.86, Gfx.FONT_XTINY, Nav.isTouch() ? "tap to close" : "START to close", vc);
    }
}
