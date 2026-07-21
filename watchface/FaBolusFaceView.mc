using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Complications;
using Toybox.Lang;

// Minimal faBolus watch face: big time + a range-colored BG line with a trend arrow.
//
// BG source: faBolus publishes a PUBLIC BG complication from the remote app (BgComplication.mc). A
// watch face is a separate app, so it reads that complication via the Complications framework (the
// only cross-app channel). We re-read it on every onUpdate so it tracks new readings, not just the
// value present when the face first showed. The published trend is a Latin token (Face It can't
// render Unicode); on our OWN face we map it to a proper Unicode arrow. Value is shown in the
// glucose-band color. Complication behavior needs on-device validation.
class FaBolusFaceView extends Ui.WatchFace {
    private var _compId as Complications.Id? = null;
    private var _num as Lang.Number? = null;      // numeric mg/dL, for band color (null = none/stale)
    private var _text as Lang.String = "--";      // the value text to draw
    private var _arrow as Lang.String = "";        // Unicode trend arrow

    function initialize() { WatchFace.initialize(); }

    function onShow() as Void { subscribe(); refreshBg(); }
    function onExitSleep() as Void { refreshBg(); }
    function onComplicationChanged(id as Complications.Id) as Void { refreshBg(); }

    // Find the faBolus public BG complication (custom type, short label "BG") and subscribe.
    private function subscribe() as Void {
        if (_compId != null || !(Toybox has :Complications)) { return; }
        try {
            Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
            var iter = Complications.getComplications();
            var c = iter.next();
            while (c != null) {
                if (c.getType() == Complications.COMPLICATION_TYPE_INVALID) {
                    var sl = c.shortLabel;
                    if (sl != null && sl.equals("BG")) {
                        _compId = c.complicationId;
                        Complications.subscribeToUpdates(_compId);
                        break;
                    }
                }
                c = iter.next();
            }
        } catch (e) {}
    }

    private function refreshBg() as Void {
        if (!(Toybox has :Complications)) { return; }
        if (_compId == null) { subscribe(); }
        if (_compId == null) { return; }
        try {
            var c = Complications.getComplication(_compId);
            if (c == null) { return; }
            var v = c.value;
            var arrowRaw = "";
            var u = null;
            try { u = c.unit; } catch (e) {}
            if (v instanceof Lang.Number) {
                _num = v; _text = v.toString();
                if (u instanceof Lang.String) { arrowRaw = u; }
            } else if (v instanceof Lang.Float || v instanceof Lang.Double) {
                _num = v.toNumber(); _text = _num.toString();
                if (u instanceof Lang.String) { arrowRaw = u; }
            } else if (v instanceof Lang.String) {
                // "124 ^" (string mode) or "--" (stale). Split leading digits (color) from the arrow.
                var n = leadingInt(v);
                _num = n;
                _text = (n != null) ? n.toString() : v;
                arrowRaw = (n != null) ? nonDigitTail(v) : "";
            } else {
                return;
            }
            _arrow = unicodeArrow(arrowRaw);
        } catch (e) {}
    }

    // Leading integer of a string ("124 ^" -> 124), or null if it doesn't start with a digit.
    private function leadingInt(s as Lang.String) as Lang.Number? {
        var out = "";
        for (var i = 0; i < s.length(); i += 1) {
            var ch = s.substring(i, i + 1);
            if ("0123456789".find(ch) != null) { out += ch; } else { break; }
        }
        return out.length() > 0 ? out.toNumber() : null;
    }
    // The trailing non-digit part, trimmed of spaces ("124 ^" -> "^").
    private function nonDigitTail(s as Lang.String) as Lang.String {
        var i = 0;
        while (i < s.length() && "0123456789".find(s.substring(i, i + 1)) != null) { i += 1; }
        var tail = (i < s.length()) ? s.substring(i, s.length()) : "";
        // strip spaces
        var out = "";
        for (var j = 0; j < tail.length(); j += 1) {
            var ch = tail.substring(j, j + 1);
            if (!ch.equals(" ")) { out += ch; }
        }
        return out;
    }
    // Map the Latin trend token (published for Face It compatibility) to a real Unicode arrow.
    private function unicodeArrow(a as Lang.String) as Lang.String {
        if (a.equals("^^")) { return "⇈"; }   // ⇈
        if (a.equals("^"))  { return "↑"; }   // ↑
        if (a.equals("/"))  { return "↗"; }   // ↗
        if (a.equals("->")) { return "→"; }   // →
        if (a.equals("\\")) { return "↘"; }   // ↘
        if (a.equals("v"))  { return "↓"; }   // ↓
        if (a.equals("vv")) { return "⇊"; }   // ⇊
        return "";
    }
    private function bandColor(n as Lang.Number) as Lang.Number {
        if (n < 70)  { return Gfx.COLOR_RED; }
        if (n < 180) { return Gfx.COLOR_GREEN; }
        if (n < 250) { return Gfx.COLOR_YELLOW; }
        return Gfx.COLOR_ORANGE;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        refreshBg();   // re-read the complication so BG tracks new readings
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        var t = System.getClockTime();
        var time = t.hour.format("%02d") + ":" + t.min.format("%02d");
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.42, Gfx.FONT_NUMBER_HOT, time, vc);

        var display = _arrow.equals("") ? _text : (_text + " " + _arrow);
        var col = (_num != null) ? bandColor(_num) : Gfx.COLOR_LT_GRAY;
        dc.setColor(col, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.72, Gfx.FONT_MEDIUM, display, vc);
    }
}
