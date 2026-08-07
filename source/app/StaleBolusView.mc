using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// AB4 (Addendum B): the three-way stale-CGM choice, shown BEFORE composing a carb bolus when the current
// CGM reading is stale (AppState.staleBolusShouldWarn). Today a stale reading is silently dropped from the
// correction (carbs-only); this makes that explicit and offers a warned, per-attempt override:
//   • Include reading — dose the correction off the stale-but-REAL reading (insulin-INCREASING override),
//   • Carbs only      — today's silent behavior, now acknowledged,
//   • Cancel          — pure UI back-out; composes and sends NOTHING.
// Mirrors faBolusCore StaleBolusPrompt so the framing is identical to the phone. Two input models
// (StaleBolusDelegate):
//   • Touch: tap a row.
//   • Buttons: UP/DOWN move the cursor, START selects. The cursor defaults to "Carbs only" (the SAFE,
//     non-increasing path) — "include" is NEVER the default and is never auto-selected.
class StaleBolusView extends Ui.View {
    public var cursor as Lang.Number = AppState.STALE_CARBS_ONLY;   // buttons default: the safe path

    function initialize() { View.initialize(); }

    // Row rect (pixels) for choice index i (0..2): [x, y, w, h]. Shared with the delegate's hit-testing.
    static function rowRect(i, w, h) {
        var rowH = h * 0.145;
        var y = h * (0.32 + 0.165 * i);
        return [w * 0.14, y, w * 0.72, rowH];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var buttons = DeviceProfile.isButtons();

        // Warning lead: the reading, its age, and that it was left out of the dose.
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Gfx.FONT_XTINY, "Stale CGM", vc);
        var head = AppState.displayGlucose() + " mg/dL";
        var age = AppState.ageLabel();
        if (!age.equals("")) { head = head + " · " + age; }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.21, Gfx.FONT_XTINY, head, vc);

        // Three choices. "Include" is drawn cautionary (insulin-increasing); "Cancel" muted.
        var labels = ["Include reading", "Carbs only", "Cancel"];
        for (var i = 0; i < 3; i += 1) {
            var rr = rowRect(i, w, h);
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rr[0], rr[1], rr[2], rr[3], 8);
            if (buttons && i == cursor) {
                dc.setPenWidth(2);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(rr[0], rr[1], rr[2], rr[3], 8);
                dc.setPenWidth(1);
            }
            var tc = Gfx.COLOR_WHITE;
            if (i == AppState.STALE_INCLUDE) { tc = Gfx.COLOR_YELLOW; }
            else if (i == AppState.STALE_CANCEL) { tc = Gfx.COLOR_LT_GRAY; }
            dc.setColor(tc, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, rr[1] + rr[3] / 2, Gfx.FONT_XTINY, labels[i], vc);
        }

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY, buttons ? "UP/DOWN · START" : "tap a choice", vc);
    }
}
