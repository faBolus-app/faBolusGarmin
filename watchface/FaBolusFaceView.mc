using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Complications;
using Toybox.Lang;

// Minimal faBolus watch face: big time + a BG line.
//
// How BG gets here: faBolus publishes a PUBLIC BG complication from the remote app
// (source/app/BgComplication.mc). A watch face is a separate app with its own storage, so it reads
// the published complication via the Complications framework (the only cross-app channel). The
// published value string already reads "--" when the reading is stale.
// NOTE: complication discovery/subscription can't be verified without a device — validate on-device.
class FaBolusFaceView extends Ui.WatchFace {
    private var _bg as Lang.String = "--";
    private var _compId as Complications.Id? = null;

    function initialize() { WatchFace.initialize(); }

    function onShow() as Void { subscribe(); refreshBg(); }
    function onExitSleep() as Void { refreshBg(); }

    // Find the faBolus public BG complication (custom type, short label "BG") and subscribe to it.
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

    function onComplicationChanged(id as Complications.Id) as Void { refreshBg(); }

    private function refreshBg() as Void {
        if (_compId == null || !(Toybox has :Complications)) { return; }
        try {
            var c = Complications.getComplication(_compId);
            if (c != null && c.value != null) { _bg = c.value.toString(); }
        } catch (e) {}
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
