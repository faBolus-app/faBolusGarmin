using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi as Ui;

// The clock with glucose under it.
class ClockView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var t = System.getClockTime();
        if (Prefs.clockAnalog()) {
            drawAnalog(dc, cx, h * 0.40, (h < w ? h : w) * 0.40, t);
            drawGlucose(dc, cx, h * 0.82, Gfx.FONT_SMALL, now);
        } else {
            drawDigital(dc, cx, h * 0.40, t);
            drawGlucose(dc, cx, h * 0.70, Gfx.FONT_MEDIUM, now);
        }
    }

    // 12- or 24-hour as the watch is set.
    static function digitalText(hour as Lang.Number, minute as Lang.Number, is24 as Lang.Boolean) as [Lang.String, Lang.String] {
        if (is24) { return [hour.format("%02d") + ":" + minute.format("%02d"), ""]; }
        var suffix = (hour >= 12) ? " PM" : " AM";
        var hr = hour % 12;
        if (hr == 0) { hr = 12; }
        return [hr.format("%d") + ":" + minute.format("%02d"), suffix];
    }

    private function drawDigital(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, t as System.ClockTime) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var text = digitalText(t.hour, t.min, System.getDeviceSettings().is24Hour);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_NUMBER_HOT, text[0], vc);
        if (!text[1].equals("")) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + dc.getFontHeight(Gfx.FONT_NUMBER_HOT) / 2 + 6, Gfx.FONT_XTINY, text[1], vc);
        }
    }

    private function drawAnalog(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, r as Lang.Numeric,
                                t as System.ClockTime) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        for (var i = 0; i < 12; i += 1) {
            var a = i * Math.PI / 6.0;
            var major = (i % 3 == 0);
            var inner = major ? r * 0.80 : r * 0.90;
            dc.setColor(major ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(major ? 3 : 1);
            dc.drawLine(cx + inner * Math.sin(a), cy - inner * Math.cos(a), cx + r * Math.sin(a), cy - r * Math.cos(a));
        }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var n = 1; n <= 12; n += 1) {
            var na = n * Math.PI / 6.0;
            dc.drawText(cx + r * 0.66 * Math.sin(na), cy - r * 0.66 * Math.cos(na), Gfx.FONT_XTINY, n.toString(), vc);
        }
        drawHand(dc, cx, cy, ((t.hour % 12) + t.min / 60.0) * Math.PI / 6.0, r * 0.50, 6);
        drawHand(dc, cx, cy, t.min * Math.PI / 30.0, r * 0.80, 4);
        dc.fillCircle(cx, cy, 4);
        dc.setPenWidth(1);
    }

    private function drawHand(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, ang as Lang.Numeric,
                              len as Lang.Numeric, half as Lang.Numeric) as Void {
        var sn = Math.sin(ang);
        var cs = Math.cos(ang);
        var px = cs * half;
        var py = sn * half;
        dc.fillPolygon([[cx + px, cy + py], [cx + len * sn, cy - len * cs], [cx - px, cy - py],
                        [cx - len * 0.14 * sn, cy + len * 0.14 * cs]]);
    }

    private function drawGlucose(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, font as Gfx.FontType,
                                 now as Lang.Number) as Void {
        Screens.drawGlucose(dc, cx, cy, font, now);
        if (!Glucose.isHidden(now)) {
            dc.setColor(Glucose.stale(now) ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + dc.getFontHeight(font) / 2 + 6, Gfx.FONT_XTINY, Display.ago(Glucose.age(now)),
                        Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }
}

// The glucose chart over the chosen range, placed by each point's time.
class CgmView extends Ui.View {
    function initialize() { View.initialize(); }

    function onShow() as Void {
        if (History.stale(Status.now())) { Link.wantHistory(); }
    }

    // The gridlines strictly inside the plot: every 100 mg/dL, or every 50 when that leaves fewer than two.
    static function gridlines(floor as Lang.Number, ceiling as Lang.Number) as Lang.Array<Lang.Number> {
        var lines = multiplesBetween(floor, ceiling, 100);
        if (lines.size() < 2) { lines = multiplesBetween(floor, ceiling, 50); }
        return lines;
    }

    static function multiplesBetween(floor as Lang.Number, ceiling as Lang.Number, step as Lang.Number) as Lang.Array<Lang.Number> {
        var out = [] as Lang.Array<Lang.Number>;
        var v = (floor / step + 1) * step;
        if (v <= floor) { v += step; }
        while (v < ceiling) {
            out.add(v);
            v += step;
        }
        return out;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        var floor = Prefs.plotFloor();
        var ceiling = Prefs.plotCeiling();
        var vmin = floor.toFloat();
        var vmax = ceiling.toFloat();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var stale = Glucose.stale(now);
        var gone = Glucose.isHidden(now);

        dc.setColor((stale && !gone) ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.11, Gfx.FONT_XTINY, gone ? "--" : Display.ago(Glucose.age(now)), vc);
        Screens.drawGlucose(dc, cx, h * 0.22, Gfx.FONT_NUMBER_MEDIUM, now);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.32, Gfx.FONT_XTINY, Display.glucoseUnit(Prefs.glucoseUnit()), vc);

        var left = w * 0.16;
        var right = w * 0.84;
        var top = h * 0.42;
        var bottom = h * 0.82;
        var lines = gridlines(floor, ceiling);
        for (var i = 0; i < lines.size(); i += 1) {
            var v = lines[i];
            var y = bottom - ((v - vmin) / (vmax - vmin)) * (bottom - top);
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.drawLine(left, y, right, y);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(right + w * 0.02, y, Gfx.FONT_XTINY, Display.glucose(v, Prefs.glucoseUnit()),
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        var at = History.times();
        var mgdl = History.values();
        var start = now - CgmView.hours() * 3600;
        // The points' times are the phone's clock; placed on this watch's.
        var offset = Status.clockOffset();
        var drawn = 0;
        for (var k = 0; k < at.size() && k < mgdl.size(); k += 1) {
            var at0 = at[k];
            var g = mgdl[k];
            if (!(at0 instanceof Lang.Number) || !(g instanceof Lang.Number)) { continue; }
            var t = at0 + offset;
            if (t < start || t > now) { continue; }
            var v = g.toFloat();
            if (v < vmin) { v = vmin; }
            if (v > vmax) { v = vmax; }
            var x = left + (t - start).toFloat() / (now - start).toFloat() * (right - left);
            var y = bottom - ((v - vmin) / (vmax - vmin)) * (bottom - top);
            dc.setColor(Display.rangeColor(g), Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 2);
            drawn += 1;
        }
        if (drawn == 0) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, (top + bottom) / 2, Gfx.FONT_XTINY, "no history", vc);
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY, CgmView.hours().toString() + " Hours (tap)", vc);
    }

    // The chosen range, from the phone's list; tapping moves to the next.
    static var _hoursIndex as Lang.Number = 0;

    static function hours() as Lang.Number {
        var list = Prefs.chartHours();
        if (list.size() == 0) { return 3; }
        var v = list[_hoursIndex % list.size()];
        return (v instanceof Lang.Number) ? v : 3;
    }

    static function nextRange() as Void { _hoursIndex += 1; }
}

class CgmDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    private function cycle() as Lang.Boolean {
        CgmView.nextRange();
        Ui.requestUpdate();
        return true;
    }
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return cycle(); }
    function onSelect() as Lang.Boolean { return cycle(); }
    function onNextPage() as Lang.Boolean { return Nav.goNext("history"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("history"); }
}

// The pump's values, as rows in the order the phone sets. Each value older than its window is marked.
class DetailsView extends Ui.View {
    // Older than this, a value is marked as old.
    static const OLD_SEC = 900;

    function initialize() { View.initialize(); }

    static function amount(key as Lang.String, now as Lang.Number) as Lang.String {
        var mU = Status.field(key, "mU");
        if (mU == null) { return "--"; }
        return Display.units(mU) + " U" + mark(key, now);
    }

    static function mark(key as Lang.String, now as Lang.Number) as Lang.String {
        var age = Status.ageOf(key, now);
        return (age != null && age > OLD_SEC) ? " (old)" : "";
    }

    // A row's text, or null when the row has nothing to show.
    static function row(id as Lang.String, now as Lang.Number) as Lang.String? {
        var unit = Prefs.glucoseUnit();
        if (id.equals("iob")) { return "Active Insulin: " + amount("iob", now); }
        if (id.equals("reservoir")) { return "Reservoir: " + amount("reservoir", now); }
        if (id.equals("lastBolus")) { return "Last bolus: " + amount("lastBolus", now); }
        if (id.equals("battery")) {
            var pct = Status.field("battery", "percent");
            if (pct == null) { return "Battery: --"; }
            return "Battery: " + pct.toString() + "%" + (Status.charging() ? " · Charging" : "") + mark("battery", now);
        }
        if (id.equals("cgm")) { return "CGM: " + Glucose.text(now) + " " + Display.glucoseUnit(unit); }
        var ratio = Status.field("calculator", "carbRatioMg");
        if (id.equals("carbRatio")) {
            return "Carb ratio: " + ((ratio != null && ratio > 0) ? (ratio.toFloat() / 1000.0).format("%.1f") + " g/U" : "--");
        }
        var isf = Status.field("calculator", "isf");
        if (id.equals("isf")) {
            return "ISF: " + ((isf != null && isf > 0) ? Display.glucose(isf, unit) + " " + Display.isfUnit(unit) : "--");
        }
        var target = Status.field("calculator", "target");
        if (id.equals("target")) {
            return "Target: " + ((target != null && target > 0) ? Display.glucose(target, unit) + " " + Display.glucoseUnit(unit) : "--");
        }
        var max = Status.field("calculator", "maxBolusMU");
        if (id.equals("maxBolus")) { return "Max bolus: " + ((max != null) ? Display.units(max) + " U" : "--"); }
        if (id.equals("maxBasal")) {
            var maxBasal = Status.field("maxBasal", "mUPerHour");
            if (maxBasal == null || maxBasal <= 0) { return null; }
            if (Status.basalSuspended()) { return "Basal: suspended"; }
            var rate = Status.field("basal", "mUPerHour");
            if (rate == null) { return null; }
            var pct = (rate * 100 + maxBasal / 2) / maxBasal;
            if (pct > 100) { pct = 100; }
            return "Basal " + Display.units(rate) + "/" + Display.units(maxBasal) + " U/hr · " + pct.toString() + "%";
        }
        return null;
    }

    static function rowY(count as Lang.Number, i as Lang.Number, top as Lang.Float, bottom as Lang.Float) as Lang.Float {
        if (count <= 1) { return (top + bottom) / 2.0; }
        return top + (bottom - top) / (count - 1) * i;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Gfx.FONT_XTINY, Display.linkLine(now), vc);
        var rows = [] as Lang.Array<Lang.String>;
        var order = Prefs.details();
        for (var i = 0; i < order.size(); i += 1) {
            var id = order[i];
            if (id instanceof Lang.String) {
                var r = row(id, now);
                if (r != null) { rows.add(r); }
            }
        }
        var n = Alerts.shown().size();
        rows.add(n > 0 ? "Alerts: " + n.toString() : "No alerts");
        rows.add(AppVersion.label());
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < rows.size(); i += 1) {
            dc.drawText(cx, h * rowY(rows.size(), i, 0.28, 0.80), Gfx.FONT_XTINY, rows[i], vc);
        }
    }
}
