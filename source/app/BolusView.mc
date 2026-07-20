using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Bolus entry. On touch devices: tap the mode chip (Units/Carbs), − / + to adjust, Deliver.
// On button devices: the focus cursor (moved with up/down) highlights one control and START
// activates it — same controls, no taps. Focus order: 0 chip, 1 minus, 2 plus, 3 deliver.
class BolusEntryView extends Ui.View {
    public var focus as Lang.Number = 3;   // button-mode cursor; starts on Deliver-adjacent (+)

    function initialize() { View.initialize(); focus = 2; }

    // Shared geometry (pixels), so touch hit-testing and the focus highlight match what's drawn.
    static function chipRect(w, h) { return [w / 2 - w * 0.24, h * 0.09, w * 0.48, h * 0.14]; }
    static function deliverRect(w, h) { return [w / 2 - w * 0.28, h * 0.74, w * 0.56, h * 0.15]; }
    static function minusCenter(w, h) { return [w * 0.17, h * 0.45]; }
    static function plusCenter(w, h) { return [w * 0.83, h * 0.45]; }
    static function stepRadius(w) { return w * 0.13; }
    static const TARGET_COUNT = 4;   // chip, minus, plus, deliver

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var isUnits = AppState.mode.equals("units");
        var buttons = DeviceProfile.isButtons();
        var hint = buttons ? "" : " (tap)";

        // Mode chip.
        var cr = chipRect(w, h);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cr[0], cr[1], cr[2], cr[3], 8);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cr[1] + cr[3] / 2, Gfx.FONT_TINY, (isUnits ? "Units" : "Carbs") + hint, vc);

        // − / + buttons.
        var mc = minusCenter(w, h), pc = plusCenter(w, h), r = stepRadius(w);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(mc[0], mc[1], r);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(pc[0], pc[1], r);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(mc[0], mc[1], Gfx.FONT_MEDIUM, "-", vc);
        dc.drawText(pc[0], pc[1], Gfx.FONT_MEDIUM, "+", vc);

        // Big value.
        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.45, Gfx.FONT_NUMBER_MEDIUM, AppState.valueLabel(), vc);

        // Computed insulin (carbs mode) — clear of the value and the Deliver button.
        if (!isUnits) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.63, Gfx.FONT_XTINY,
                        "~ " + AppState.computeUnits().format("%.2f") + " U", vc);
        }

        // Deliver button.
        var dr = deliverRect(w, h);
        dc.setColor(0x5C6BE6, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(dr[0], dr[1], dr[2], dr[3], 10);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, dr[1] + dr[3] / 2, Gfx.FONT_SMALL, "Deliver", vc);

        // Button-mode focus cursor: outline the focused control (up/down moves it, START activates).
        if (buttons) {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            if (focus == 0) { dc.drawRoundedRectangle(cr[0], cr[1], cr[2], cr[3], 8); }
            else if (focus == 1) { dc.drawCircle(mc[0], mc[1], r + 2); }
            else if (focus == 2) { dc.drawCircle(pc[0], pc[1], r + 2); }
            else { dc.drawRoundedRectangle(dr[0], dr[1], dr[2], dr[3], 10); }
            dc.setPenWidth(1);
        }
    }
}
