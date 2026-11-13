using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.System;
using Toybox.WatchUi as Ui;

// The digital clock with glucose under it.
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
        drawDate(dc, cx, h * 0.18);
        drawDigital(dc, cx, h * 0.35, t);
        drawGlucose(dc, cx, h * 0.62, Gfx.FONT_NUMBER_MILD, h * 0.79, now);
    }

    // The day and date in small caps above the time ("SAT 1").
    private function drawDate(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric) as Void {
        var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_XTINY, (d.day_of_week as Lang.String).toUpper() + " " + (d.day as Lang.Number).toString(),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // 12- or 24-hour as the watch is set.
    static function digitalText(hour as Lang.Number, minute as Lang.Number, is24 as Lang.Boolean) as [Lang.String, Lang.String] {
        if (is24) { return [hour.format("%02d") + ":" + minute.format("%02d"), ""]; }
        var suffix = (hour >= 12) ? "PM" : "AM";
        var hr = hour % 12;
        if (hr == 0) { hr = 12; }
        return [hr.format("%d") + ":" + minute.format("%02d"), suffix];
    }

    private function drawDigital(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, t as System.ClockTime) as Void {
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var text = digitalText(t.hour, t.min, System.getDeviceSettings().is24Hour);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_NUMBER_HOT, text[0], vc);
        // AM/PM small, beside the time's top right, so the time stays centred.
        if (!text[1].equals("")) {
            var tw = dc.getTextWidthInPixels(text[0], Gfx.FONT_NUMBER_HOT);
            var fh = dc.getFontHeight(Gfx.FONT_NUMBER_HOT);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx + tw / 2 + 4, cy - fh * 0.22, Gfx.FONT_XTINY, text[1],
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    // The reading, and its age in the same chip as the glance.
    private function drawGlucose(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, font as Gfx.FontType,
                                 chipY as Lang.Numeric, now as Lang.Number) as Void {
        Screens.drawGlucose(dc, cx, cy, font, now);
        if (!Glucose.isHidden(now)) { Screens.drawAgeChip(dc, cx, chipY, now); }
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

    // Whether a reading falls on the plot, bounds included. A reading off it isn't drawn, never pinned to
    // the edge, where it would read as a reading at the edge: the phone's plots follow the same rule.
    static function onPlot(mgdl as Lang.Number, floor as Lang.Number, ceiling as Lang.Number) as Lang.Boolean {
        return mgdl >= floor && mgdl <= ceiling;
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

        // The gridline labels sit right of the plot, inside the round screen at the plot's lower edge.
        var left = w * 0.16;
        var right = w * 0.78;
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
            if (!onPlot(g, floor, ceiling)) { continue; }
            var v = g.toFloat();
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

    // Each visit starts on the first page.
    function initialize() {
        View.initialize();
        _page = 0;
    }

    static function amount(key as Lang.String, now as Lang.Number) as Lang.String {
        var mU = Status.field(key, "mU");
        if (mU == null) { return "--"; }
        return Display.units(mU) + " U" + mark(key, now);
    }

    // " (old)" once the value under `key` is older than the phone's window for it: IOB's own, the
    // calculator's settings', and the pump status window for the rest.
    static function mark(key as Lang.String, now as Lang.Number) as Lang.String {
        var age = Status.ageOf(key, now);
        var window = Prefs.pumpStatusStaleSeconds();
        if (key.equals("iob")) { window = Prefs.iobStaleSeconds(); }
        if (key.equals("calculator")) { window = Prefs.therapyStaleSeconds(); }
        return (age != null && age > window) ? " (old)" : "";
    }

    // A row's text, or null when the row has nothing to show.
    static function row(id as Lang.String, now as Lang.Number) as Lang.String? {
        var unit = Prefs.glucoseUnit();
        if (id.equals("iob")) { return "Active Insulin: " + amount("iob", now); }
        // Whole units, as the pump shows the reservoir, rounded down.
        if (id.equals("reservoir")) {
            var mU = Status.field("reservoir", "mU");
            return "Reservoir: " + ((mU == null) ? "--" : (mU / 1000).toString() + " U" + mark("reservoir", now));
        }
        // Its time is when it was given, not how old a reading is, so it's never marked old.
        if (id.equals("lastBolus")) {
            var mU = Status.field("lastBolus", "mU");
            return "Last bolus: " + ((mU == null) ? "--" : Display.units(mU) + " U");
        }
        if (id.equals("battery")) {
            var pct = Status.field("battery", "percent");
            if (pct == null) { return "Battery: --"; }
            return "Battery: " + pct.toString() + "%" + (Status.charging() ? " · Charging" : "") + mark("battery", now);
        }
        if (id.equals("cgm")) {
            var old = (!Glucose.isHidden(now) && Glucose.stale(now)) ? " (old)" : "";
            return "CGM: " + Glucose.text(now) + " " + Display.glucoseUnit(unit) + old;
        }
        var ratio = Status.field("calculator", "carbRatioMg");
        if (id.equals("carbRatio")) {
            return "Carb ratio: " + ((ratio != null && ratio > 0) ? (ratio.toFloat() / 1000.0).format("%.1f") + " g/U" + mark("calculator", now) : "--");
        }
        var isf = Status.field("calculator", "isf");
        if (id.equals("isf")) {
            return "ISF: " + ((isf != null && isf > 0) ? Display.glucose(isf, unit) + " " + Display.isfUnit(unit) + mark("calculator", now) : "--");
        }
        var target = Status.field("calculator", "target");
        if (id.equals("target")) {
            return "Target: " + ((target != null && target > 0) ? Display.glucose(target, unit) + " " + Display.glucoseUnit(unit) + mark("calculator", now) : "--");
        }
        var max = Status.field("calculator", "maxBolusMU");
        if (id.equals("maxBolus")) { return "Max bolus: " + ((max != null) ? Display.units(max) + " U" + mark("calculator", now) : "--"); }
        if (id.equals("maxBasal")) {
            var maxBasal = Status.field("maxBasal", "mUPerHour");
            if (maxBasal == null || maxBasal <= 0) { return null; }
            if (Status.basalSuspended()) { return "Basal: suspended" + mark("basal", now); }
            var rate = Status.field("basal", "mUPerHour");
            if (rate == null) { return null; }
            var pct = (rate * 100 + maxBasal / 2) / maxBasal;
            if (pct > 100) { pct = 100; }
            return "Basal " + Display.units(rate) + "/" + Display.units(maxBasal) + " U/hr · " + pct.toString() + "%" + mark("basal", now);
        }
        // Left out while none is known: no recent auto-correction is the usual case, not a missing value.
        if (id.equals("autoCorrection")) {
            var age = Status.ageOf("lastAutoCorrection", now);
            return (age == null) ? null : "Auto-correction: " + Display.ago(age);
        }
        return null;
    }

    static function rowY(count as Lang.Number, i as Lang.Number, top as Lang.Float, bottom as Lang.Float) as Lang.Float {
        if (count <= 1) { return (top + bottom) / 2.0; }
        return top + (bottom - top) / (count - 1) * i;
    }

    // The page shown when the rows don't fit on one; a tap moves to the next.
    static var _page as Lang.Number = 0;

    static function nextPage() as Void { _page += 1; }

    // How many rows fit between top and bottom (fractions of `h`) without overlapping.
    static function perPage(h as Lang.Number, fontHeight as Lang.Number, top as Lang.Float, bottom as Lang.Float) as Lang.Number {
        var n = (((bottom - top) * h) / fontHeight).toNumber() + 1;
        return (n < 1) ? 1 : n;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.13, Gfx.FONT_XTINY, Display.linkLine(now), vc);
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
        var top = 0.24;
        var bottom = 0.80;
        var per = perPage(h, dc.getFontHeight(Gfx.FONT_XTINY), top, bottom);
        var pages = (rows.size() + per - 1) / per;
        var page = _page % pages;
        var first = page * per;
        var count = rows.size() - first;
        if (count > per) { count = per; }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < count; i += 1) {
            // A full page spaces its rows to the edges; the last page keeps the same spacing.
            dc.drawText(cx, h * rowY(per, i, top, bottom), Gfx.FONT_XTINY, rows[first + i], vc);
        }
        if (pages > 1) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.88, Gfx.FONT_XTINY, (page + 1).toString() + "/" + pages.toString()
                        + (Nav.isTouch() ? " · tap" : " · START"), vc);
        }
    }
}

class DetailsDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    private function page() as Lang.Boolean {
        DetailsView.nextPage();
        Ui.requestUpdate();
        return true;
    }
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return page(); }
    function onSelect() as Lang.Boolean { return Nav.isTouch() ? false : page(); }
    function onNextPage() as Lang.Boolean { return Nav.goNext("details"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("details"); }
}
