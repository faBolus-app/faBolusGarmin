using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.WatchUi as Ui;

// The glance: glucose and how old it is. It runs in the glance process and reads the stored status itself.
(:glance, :typecheck(disableBackgroundCheck))
class FaBolusGlanceView extends Ui.GlanceView {
    private var _timer as Timer.Timer?;

    function initialize() { GlanceView.initialize(); }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 30000, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); }
        _timer = null;
    }

    function onTick() as Void { Ui.requestUpdate(); }

    // What the glance shows: [reading or "--", age text, stale, trend token or null].
    static function line(now as Lang.Number) as Lang.Array {
        Status.load();
        Prefs.load(Status.revision());
        var g = Status.glucose();
        var age = Status.ageOf("glucose", now);
        if (g == null || age == null) { return ["--", "", true, null]; }
        var stale = age > Prefs.staleSeconds();
        var hide = Prefs.hideDelaySeconds();
        if (hide != null && age > Prefs.staleSeconds() + hide) { return ["--", "", true, null]; }
        var mins = age / 60;
        var ago = (mins <= 0) ? "now" : mins.toString() + "m ago";
        return [Display.glucose(g, Prefs.glucoseUnit()), ago, stale, stale ? null : Status.trend()];
    }

    // A tag line (the app's name, and the reading's age, orange once stale) over the reading, its arrow and
    // its unit.
    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var vl = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        var l = line(Status.now());
        var text = l[0] as Lang.String;
        var ago = l[1] as Lang.String;
        var stale = l[2] as Lang.Boolean;
        var trend = l[3] as Lang.String?;
        // The tag line: the app's name left, always, and the reading's age right (orange once stale),
        // shortened ("20m ago", then "20m") when both don't fit.
        var w = dc.getWidth();
        var tag = "faBolus";
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.26, Gfx.FONT_XTINY, tag, vl);
        if (ago.length() > 0) {
            var room = w - dc.getTextWidthInPixels(tag + "  ", Gfx.FONT_XTINY);
            if (dc.getTextWidthInPixels(ago, Gfx.FONT_XTINY) > room && ago.find(" ago") != null) {
                ago = ago.substring(0, ago.find(" ago") as Lang.Number) as Lang.String;
            }
            dc.setColor(stale ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(w, h * 0.26, Gfx.FONT_XTINY, ago, Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
        var g = Status.glucose();
        var color = (stale || g == null || text.equals("--")) ? Gfx.COLOR_LT_GRAY : Display.rangeColor(g);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.68, Gfx.FONT_MEDIUM, text, vl);
        var x = dc.getTextWidthInPixels(text, Gfx.FONT_MEDIUM) + 6;
        if (trend != null) {
            var size = dc.getFontHeight(Gfx.FONT_MEDIUM) / 5;
            var aw = TrendArrow.width(trend, size);
            TrendArrow.draw(dc, x + aw / 2, h * 0.68, size, trend, color);
            x += aw + 8;
        }
        if (!text.equals("--")) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, h * 0.72, Gfx.FONT_XTINY, Display.glucoseUnit(Prefs.glucoseUnit()), vl);
        }
    }
}
