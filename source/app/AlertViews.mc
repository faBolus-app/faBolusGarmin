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

// An alert's card: what it is, in its severity's colour, and what it says. One the pump lets a remote clear
// has a "Clear on pump" button, the one dismiss path; any other press closes the card. The alert stays
// listed until the pump confirms it cleared.
class AlertNoticeView extends Ui.View {
    private var _alert as Lang.Dictionary;

    function initialize(alert as Lang.Dictionary) {
        View.initialize();
        _alert = alert;
    }

    function alert() as Lang.Dictionary { return _alert; }

    // What the latest status says, not the card's copy: an alert that went, or that a remote may no longer
    // clear, offers no Clear.
    function clearable() as Lang.Boolean {
        var now = Alerts.current(Alerts.idOf(_alert));
        return now != null && Alerts.dismissable(now);
    }

    static function clearRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w * 0.20, h * 0.68, w * 0.60, h * 0.13];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var touch = Nav.isTouch();
        var clear = clearable();
        var critical = Wire.text(_alert, "severity", "").equals("critical");
        dc.setColor(critical ? Gfx.COLOR_RED : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        // Up to two lines, inside the round screen's width near the top; the explanation starts below them.
        var lineH = dc.getFontHeight(Gfx.FONT_SMALL);
        // The fit needs a little headroom over two lines' height to wrap rather than truncate.
        var fitted = Gfx.fitTextToArea(Wire.text(_alert, "title", "Alert"), Gfx.FONT_SMALL, w * 0.72, lineH * 2 + lineH / 2,
                                       true);
        var title = (fitted != null) ? fitted : Wire.text(_alert, "title", "Alert");
        var titleH = (title.find("\n") != null) ? lineH * 2 : lineH;
        var titleTop = h * 0.16;
        dc.drawText(cx, titleTop + titleH / 2, Gfx.FONT_SMALL, title, vc);
        var body = Wire.text(_alert, "body", "");
        if (body.length() > 0) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            var bodyTop = titleTop + titleH + h * 0.02;
            var bodyH = (clear ? h * 0.66 : h * 0.80) - bodyTop;
            dc.drawText(cx, bodyTop + bodyH / 2, Gfx.FONT_XTINY,
                        Gfx.fitTextToArea(body, Gfx.FONT_XTINY, w * 0.80, bodyH, true), vc);
        }
        if (clear) {
            var r = clearRect(w, h);
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 10);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_XTINY, touch ? "Clear on pump" : "START: clear on pump", vc);
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        var close = touch ? "tap to close" : (clear ? "BACK to close" : "START to close");
        dc.drawText(cx, h * 0.85, Gfx.FONT_XTINY, close, vc);
    }
}

class AlertCardDelegate extends Ui.BehaviorDelegate {
    private var _view as AlertNoticeView;

    function initialize(view as AlertNoticeView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        if (_view.clearable() && Nav.inRect(c[0], c[1], AlertNoticeView.clearRect(size[0], size[1]))) { return clear(); }
        return close();
    }

    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        return _view.clearable() ? clear() : close();
    }

    // Asks the phone to clear it on the pump; what happened shows on the Alerts screen.
    private function clear() as Lang.Boolean {
        var sent = Alerts.dismiss(Alerts.idOf(_view.alert()), Status.now());
        Toast.show(sent ? "Clearing on pump…" : "Phone not connected — not cleared");
        return close();
    }

    private function close() as Lang.Boolean {
        Ui.popView(Ui.SLIDE_DOWN);
        return true;
    }
}
