using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

// Screen for the Milestone 0 handoff-resume probe: title + lifecycle status + detail line.
class ProbeView extends WatchUi.View {
    private var _c as ProbeController;

    function initialize(controller as ProbeController) {
        View.initialize();
        _c = controller;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.24, Graphics.FONT_TINY, "Handoff probe", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.44, Graphics.FONT_SMALL, _c.status,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.64, Graphics.FONT_XTINY, _c.detail,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
