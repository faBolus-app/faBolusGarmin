using Toybox.WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Minimal probe view: shows the last direct-BLE glucose (or the client's status) so the on-device
// test can confirm the passive G7 link works without the phone.
class CgmProbeView extends WatchUi.View {
    private var _app as CgmProbeApp;

    function initialize(app as CgmProbeApp) {
        View.initialize();
        _app = app;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var text = (_app.lastGlucose != null) ? _app.lastGlucose.toString() : "G7 …";
        dc.drawText(cx, cy, Gfx.FONT_NUMBER_MEDIUM, text,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }
}
