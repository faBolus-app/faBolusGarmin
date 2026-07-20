using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Bench debug screen (last in the swipe rotation) for the Milestone 0 handoff test: tap to attempt
// a direct-to-pump connection using the secret shared from the phone, and watch the live status.
// Content kept in the central band so the round venu3s bezel doesn't clip it.
class DirectDebugView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.20, Gfx.FONT_TINY, "Direct (debug)", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.42, Gfx.FONT_SMALL, RemoteComm.directStatus(),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.58, Gfx.FONT_XTINY, RemoteComm.directDetail(),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        var hint = RemoteComm.hasStoredKey() ? "tap: connect direct" : "no key - send from phone";
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.80, Gfx.FONT_XTINY, hint, Gfx.TEXT_JUSTIFY_CENTER);
    }
}
