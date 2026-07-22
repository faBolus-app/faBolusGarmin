using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Lang;

// Glance: current glucose + mg/dL, and (optionally) a single Bolus button. `showBolus` is false for
// the dedicated CGM-only screen; the button is also hidden when the phone put Garmin in read-only mode.
class MainView extends Ui.View {
    private var _showBolus as Lang.Boolean;
    function initialize(showBolus as Lang.Boolean) { View.initialize(); _showBolus = showBolus; }

    // Pull a fresh status every time the glance appears (open, resume, or swipe back to it). This
    // self-heals a stale connection string — e.g. a transient "Disconnected" left from an overnight
    // reconnect whose recovery push never reached the watch — that would otherwise leave the Bolus
    // button stuck greyed until the next 15s poll happened to land.
    function onShow() as Void {
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // Subtle "swipe up for details" chevron near the top edge.
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, h * 0.045], [cx - 9, h * 0.075], [cx + 9, h * 0.075]]);

        // Glucose (large, range-colored), vertically centered so the glyph baseline can't
        // collide with the unit label below it.
        var isHidden = AppState.glucoseHidden();
        var stale = AppState.glucoseStale();
        var g = isHidden ? "--" : AppState.displayGlucose();   // "--" when hidden or no reading
        var gColor = (stale || isHidden) ? Gfx.COLOR_LT_GRAY : AppState.glucoseColor();
        dc.setColor(gColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.36, Gfx.FONT_NUMBER_HOT, g, vc);
        // Trend arrow (drawn shape, from the phone's direction token) just right of the number;
        // grayed when stale, omitted when hidden.
        if (!isHidden && !AppState.trend.equals("")) {
            var gw = dc.getTextWidthInPixels(g, Gfx.FONT_NUMBER_HOT);
            TrendArrow.draw(dc, cx + gw / 2 + 24, h * 0.36, 13, AppState.trend, gColor);
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.55, Gfx.FONT_XTINY, "mg/dL", vc);
        // Reading age — shown while a value is visible; called out in orange when stale.
        var age = AppState.ageLabel();
        if (!isHidden && !age.equals("")) {
            dc.setColor(stale ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.63, Gfx.FONT_XTINY, age, vc);
        }

        // Bolus button (bottom) — omitted on the CGM-only screen and in read-only mode.
        if (!_showBolus || AppState.readOnly) { return; }

        // While a bolus is delivering it turns into a red "Cancel" (so you can cancel after leaving the
        // delivery screen); greyed + inert when bolusing isn't possible (phone unreachable or pump
        // disconnected); otherwise the indigo "Bolus" button.
        var fill; var label; var labelColor;
        if (AppState.canCancel()) {
            fill = Gfx.COLOR_RED; label = "Cancel"; labelColor = Gfx.COLOR_WHITE;
        } else if (AppState.canBolus()) {
            fill = 0x5C6BE6; label = "Bolus"; labelColor = Gfx.COLOR_WHITE;   // indigo
        } else {
            fill = Gfx.COLOR_DK_GRAY; label = "Bolus"; labelColor = Gfx.COLOR_LT_GRAY;   // disabled
        }
        var bw = w * 0.52, bh = h * 0.17;
        var bx = cx - bw / 2, by = h * 0.68;
        dc.setColor(fill, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, bw, bh, 12);
        dc.setColor(labelColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, by + bh / 2, Gfx.FONT_SMALL, label, vc);
    }
}
