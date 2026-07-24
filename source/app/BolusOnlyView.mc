using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// A screen that is JUST the bolus button — no glucose, no chrome. One of the swipeable screens
// (id "bolusonly"), added to the order from phone settings. Same button states/behavior as the
// glance's button; hidden (shows "Read-only") when the phone put Garmin in read-only mode.
// The button rect is centered; keep the geometry in sync with BolusOnlyDelegate.onTap.
class BolusOnlyView extends Ui.View {
    function initialize() { View.initialize(); }

    function onShow() as Void {
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // GA (round-2): read-only must never hide the ability to CANCEL an in-flight bolus. Draw the red
        // Cancel whenever canCancel() is true, even in read-only; only when there's nothing to cancel does
        // read-only fall back to the "Read-only" placeholder.
        var fill; var label; var labelColor;
        if (AppState.canCancel()) {
            fill = Gfx.COLOR_RED; label = "Cancel"; labelColor = Gfx.COLOR_WHITE;
        } else if (AppState.readOnly) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Gfx.FONT_SMALL, "Read-only", vc);
            return;
        } else if (AppState.canBolus()) {
            fill = 0x5C6BE6; label = "Bolus"; labelColor = Gfx.COLOR_WHITE;   // indigo
        } else {
            fill = Gfx.COLOR_DK_GRAY; label = "Bolus"; labelColor = Gfx.COLOR_LT_GRAY;
        }
        var bw = w * 0.60, bh = h * 0.28;
        var bx = cx - bw / 2, by = h / 2 - bh / 2;
        dc.setColor(fill, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, bw, bh, 14);
        dc.setColor(labelColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, by + bh / 2, Gfx.FONT_MEDIUM, label, vc);
    }
}
