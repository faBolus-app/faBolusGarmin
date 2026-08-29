using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Math;
using Toybox.Timer;
using Toybox.Application.Storage;
using Toybox.Lang;

// A clock screen that also shows the current CGM value + trend, with NO bolus button. One of the
// swipeable screens (id "clock"), added to the order from phone settings. The clock style (analog vs
// digital) is DISPLAY-ONLY, driven by the phone's `clockAnalog` setting and persisted in
// Storage — there is no on-watch toggle. This is a screen inside the app — NOT a watch face.
class ClockView extends Ui.View {
    private const KEY_ANALOG = "clockAnalog";   // Bool from the phone (statusRead); default false (digital)
    private const PI = 3.1415926535;
    private var _timer as Timer.Timer?;

    function initialize() { View.initialize(); }

    // Pull a fresh status when the screen appears (same self-heal as the glance), and start a periodic
    // self-redraw so the analog hands advance even with no phone push (the minute hand must not sit
    // stale between the ~5-min status polls). 30 s keeps the minute hand crisp near minute boundaries.
    function onShow() as Void {
        // ROUTINE mint (fires on every screen show) — see RemoteComm.newRoutineRequestId().
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRoutineRequestId()));
        if (_timer == null) { _timer = new Timer.Timer(); }
        _timer.start(method(:onTick), 30000, true);
    }

    // Stop the redraw timer when the screen is not visible (battery — no point ticking off-screen).
    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function onTick() as Void { Ui.requestUpdate(); }

    // Coerce the Storage read to a real Boolean via an instanceof-guard — Storage.getValue()
    // returns an untyped Object?, which the `as Lang.Boolean` declaration below flags under a strict
    // typeCheckLevel; a corrupt/wrong-typed persisted value now fails to false (digital), matching the
    // prior null-fallback exactly.
    function analog() as Lang.Boolean {
        var v = Storage.getValue(KEY_ANALOG);
        return (v instanceof Lang.Boolean) ? v : false;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var t = System.getClockTime();

        if (analog()) {
            var r = (h < w ? h : w) * 0.40;
            drawAnalog(dc, cx, h * 0.40, r, t);
            drawGlucose(dc, cx, h * 0.82, Gfx.FONT_SMALL);   // below the dial; age line sits under it
        } else {
            drawDigital(dc, cx, h * 0.40, t);
            drawGlucose(dc, cx, h * 0.70, Gfx.FONT_MEDIUM);
        }
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

    // Conventional analog dial: rim, hour ticks emphasized at 12/3/6/9, hour NUMERALS
    // 1–12, and tapered hour/minute hands. Angle 0 = 12 o'clock (top); screen y grows downward, so a
    // direction is (+sin, -cos) and its perpendicular is (+cos, +sin).
    private function drawAnalog(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, r as Lang.Numeric, t) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        // Hour ticks — longer + brighter + thicker at the quarter hours (12/3/6/9).
        for (var i = 0; i < 12; i += 1) {
            var a = i * PI / 6.0;
            var sn = Math.sin(a), cs = Math.cos(a);
            var major = (i % 3 == 0);
            var inner = major ? r * 0.80 : r * 0.90;
            dc.setColor(major ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(major ? 3 : 1);
            dc.drawLine(cx + inner * sn, cy - inner * cs, cx + r * sn, cy - r * cs);
        }
        // Hour numerals 1–12, inset from the rim.
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var n = 1; n <= 12; n += 1) {
            var na = n * PI / 6.0;
            dc.drawText(cx + (r * 0.66) * Math.sin(na), cy - (r * 0.66) * Math.cos(na),
                        Gfx.FONT_XTINY, n.toString(), vc);
        }
        // Tapered hands (filled kites). Minute longer + slimmer than hour.
        var minA = t.min * PI / 30.0;
        var hrA = ((t.hour % 12) + t.min / 60.0) * PI / 6.0;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        drawHand(dc, cx, cy, hrA, r * 0.50, 6);
        drawHand(dc, cx, cy, minA, r * 0.80, 4);
        dc.fillCircle(cx, cy, 4);
        dc.setPenWidth(1);
    }

    // A tapered hand as a filled quadrilateral: two base corners `halfBase` px either side of the center
    // (along the perpendicular), the tip at `len`, and a short tail behind the center.
    private function drawHand(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric,
                              ang as Lang.Float, len as Lang.Numeric, halfBase as Lang.Numeric) as Void {
        var sn = Math.sin(ang), cs = Math.cos(ang);
        var px = Math.cos(ang) * halfBase, py = Math.sin(ang) * halfBase;   // perpendicular offset
        var tipX = cx + len * sn,        tipY = cy - len * cs;
        var tailX = cx - (len * 0.14) * sn, tailY = cy + (len * 0.14) * cs;
        dc.fillPolygon([[cx + px, cy + py], [tipX, tipY], [cx - px, cy - py], [tailX, tailY]]);
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
        // Reading age below the value (same source-epoch age + styling as MainView — orange when
        // stale, else gray). Suppressed when the value is hidden or the age is unknown ("").
        if (!isHidden) {
            var age = AppState.ageLabel();
            if (!age.equals("")) {
                dc.setColor(stale ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, cy + dc.getFontHeight(font) / 2 + 6, Gfx.FONT_XTINY, age, vc);
            }
        }
    }
}
