using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Lang;

// Minimal faBolus watch face: big time + a BG line. This is a starting scaffold — see the TODO in
// refreshBg() for wiring live glucose.
//
// How BG gets here: faBolus publishes a PUBLIC BG complication from the remote app
// (source/app/BgComplication.mc). A watch face is a separate app with its own storage, so it can't
// read the remote app's data directly — it reads the published complication instead
// (Complications.getComplication / subscribeToUpdates). That hook is stubbed below.
class FaBolusFaceView extends Ui.WatchFace {
    private var _bg as Lang.String = "--";

    function initialize() { WatchFace.initialize(); }

    function onShow() as Void { refreshBg(); }
    function onExitSleep() as Void { refreshBg(); }

    // TODO(watch-face contributor): populate _bg from the faBolus public BG complication.
    // Sketch:
    //   if (Toybox has :Complications) {
    //       var iter = Complications.getComplications();   // find the faBolus BG publisher
    //       // ...read its value, or Complications.subscribeToUpdates(id, method(:onComplication))
    //   }
    // Until implemented the face shows "--".
    private function refreshBg() as Void {
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        var t = System.getClockTime();
        var time = t.hour.format("%02d") + ":" + t.min.format("%02d");
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.42, Gfx.FONT_NUMBER_HOT, time, vc);

        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.72, Gfx.FONT_MEDIUM, "BG " + _bg, vc);
    }
}
