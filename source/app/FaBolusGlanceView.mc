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

    // What the glance shows, and whether it's current: [text, stale].
    static function line(now as Lang.Number) as Lang.Array {
        Status.load();
        Prefs.load(Status.revision());
        var g = Status.glucose();
        var age = Status.ageOf("glucose", now);
        if (g == null || age == null) { return ["--", true]; }
        var unit = Prefs.glucoseUnit();
        var stale = age > Prefs.staleSeconds();
        var hide = Prefs.hideDelaySeconds();
        if (hide != null && age > Prefs.staleSeconds() + hide) { return ["--", true]; }
        var text = Display.glucose(g, unit) + " " + Display.glucoseUnit(unit);
        if (stale) { text = text + " · " + (age / 60).toString() + "m"; }
        return [text, stale];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var vl = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.30, Gfx.FONT_TINY, "faBolus", vl);
        var l = line(Status.now());
        dc.setColor((l[1] as Lang.Boolean) ? Gfx.COLOR_LT_GRAY : 0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.70, Gfx.FONT_MEDIUM, l[0] as Lang.String, vl);
    }
}
