using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Lang;

// Compact glance shown in the widget/glance carousel: "faBolus" + last-known BG. It reads the same
// persisted values the app/complication write (`bg` / `bgEpoch`), so it shows a reading without
// opening the app. Runs in the limited glance-memory context, so it reads Storage directly and
// pulls in no app modules. A reading older than 6 minutes shows "--".
(:glance)
class FaBolusGlanceView extends Ui.GlanceView {
    function initialize() { GlanceView.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var vl = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.30, Gfx.FONT_TINY, "faBolus", vl);

        var bg = Storage.getValue("bg");
        var ep = Storage.getValue("bgEpoch");
        var epNum = (ep == null) ? 0 : ep;
        var stale = (bg == null) || (epNum <= 0) || ((Time.now().value() - epNum) > 360);
        var text = stale ? "--" : (bg.toString() + " mg/dL");
        dc.setColor(stale ? Gfx.COLOR_LT_GRAY : 0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.70, Gfx.FONT_MEDIUM, text, vl);
    }
}
