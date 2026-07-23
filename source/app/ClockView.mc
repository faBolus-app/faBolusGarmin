using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Application.Storage;
using Toybox.Lang;

// A clock screen that also shows the current CGM value + trend, with NO bolus button. One of the
// swipeable screens (id "clock"), added to the order from phone settings. The clock style is
// user-selectable ON-WATCH: tap (or SELECT) toggles analog <-> digital, persisted in Storage. This
// is a screen inside the app — NOT a watch face.
class ClockView extends Ui.View {
    private const KEY_ANALOG = "clockAnalog";   // Bool; default false (digital)
    private const PI = 3.1415926535;

    function initialize() { View.initialize(); }

    // Pull a fresh status when the screen appears (same self-heal as the glance).
    function onShow() as Void {
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
    }

    function analog() as Lang.Boolean {
        var v = Storage.getValue(KEY_ANALOG);
        return (v == null) ? false : v;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var t = System.getClockTime();

        if (analog()) {
            var r = (h < w ? h : w) * 0.34;
            drawAnalog(dc, cx, h * 0.44, r, t);
            drawGlucose(dc, cx, h * 0.87, Gfx.FONT_SMALL);
        } else {
            drawDigital(dc, cx, h * 0.40, t);
            drawGlucose(dc, cx, h * 0.70, Gfx.FONT_MEDIUM);
        }

        // Hint that tapping switches the clock style.
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.06, Gfx.FONT_XTINY, "tap: analog / digital", vc);
    }

    private function drawDigital(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, t) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var is24 = System.getDeviceSettings().is24Hour;
        var hr = t.hour;
        var suffix = "";
        if (!is24) {
            suffix = (hr >= 12) ? " PM" : " AM";
            hr = hr % 12; if (hr == 0) { hr = 12; }
        }
        var s = (is24 ? hr.format("%02d") : hr.format("%d")) + ":" + t.min.format("%02d");
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_NUMBER_HOT, s, vc);
        if (!suffix.equals("")) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + dc.getFontHeight(Gfx.FONT_NUMBER_HOT) / 2 + 6, Gfx.FONT_XTINY, suffix, vc);
        }
    }

    // Simple analog dial: outer circle, 12 hour ticks, hour + minute hands. Angle 0 = 12 o'clock (top);
    // screen y grows downward, so endpoints use (+sin, -cos).
    private function drawAnalog(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, r as Lang.Numeric, t) as Void {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        for (var i = 0; i < 12; i += 1) {
            var a = i * PI / 6.0;
            var sn = Math.sin(a), cs = Math.cos(a);
            dc.drawLine(cx + (r * 0.86) * sn, cy - (r * 0.86) * cs, cx + r * sn, cy - r * cs);
        }
        var minA = t.min * PI / 30.0;
        var hrA = ((t.hour % 12) + t.min / 60.0) * PI / 6.0;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(cx, cy, cx + (r * 0.5) * Math.sin(hrA), cy - (r * 0.5) * Math.cos(hrA));
        dc.setPenWidth(2);
        dc.drawLine(cx, cy, cx + (r * 0.82) * Math.sin(minA), cy - (r * 0.82) * Math.cos(minA));
        dc.fillCircle(cx, cy, 4);
        dc.setPenWidth(1);
    }

    // BG value + trend, matching MainView/CgmView styling (range-colored, grayed when stale, "--" hidden).
    private function drawGlucose(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, font) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var isHidden = AppState.glucoseHidden();
        var stale = AppState.glucoseStale();
        var g = isHidden ? "--" : AppState.displayGlucose();
        var col = (stale || isHidden) ? Gfx.COLOR_LT_GRAY : AppState.glucoseColor();
        dc.setColor(col, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, g, vc);
        if (!isHidden && !AppState.trend.equals("")) {
            var gw = dc.getTextWidthInPixels(g, font);
            TrendArrow.draw(dc, cx + gw / 2 + 16, cy, 10, AppState.trend, col);
        }
    }
}
