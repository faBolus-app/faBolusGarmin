using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// G5 (Garmin half): the one-time, plain-language notice shown the FIRST time the wearer opens the
// bolus flow. It tells them where the on/off switch lives — bolusing from the watch is off by default
// and is turned on/off from faBolus on the phone. Purely informational: any confirm gesture continues
// to bolus entry (BolusIntroDelegate), BACK returns to the launching screen. Shown exactly once
// (AppState persists the "shown" flag at display time, before this view is pushed).
//
// Layout mirrors DetailsView: a title, a body wrapped into short centered lines that fit the round
// screen on both the largest (venu3s) and smallest (fr245) declared devices, and a bottom hint.
class BolusIntroView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // Title.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Gfx.FONT_XTINY, "Watch bolus", vc);

        // Body: short lines (pre-wrapped so they never clip the round edges). Kept in the central band.
        var lines = [
            "Bolusing from",
            "the watch is off",
            "by default.",
            "Turn it on or off",
            "in faBolus on",
            "your phone."
        ];
        var top = 0.28, bottom = 0.72;
        var step = (bottom - top) / (lines.size() - 1);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(cx, h * (top + step * i), Gfx.FONT_XTINY, lines[i], vc);
        }

        // Continue hint (device-appropriate verb).
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.88, Gfx.FONT_XTINY,
                    DeviceProfile.isButtons() ? "START to continue" : "tap to continue", vc);
    }
}
