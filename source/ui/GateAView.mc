using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

// Minimal Gate A status screen: shows the BLE lifecycle status + detail line. Content is kept in
// the central band so the round venu3s bezel doesn't clip it. Replaced by the ported UI once the
// gates pass.
class GateAView extends WatchUi.View {
    private var _controller as GateAController;

    function initialize(controller as GateAController) {
        View.initialize();
        _controller = controller;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.24, Graphics.FONT_TINY, "Gate A", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.42, Graphics.FONT_SMALL, _controller.status,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.62, Graphics.FONT_XTINY, _controller.detail,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
