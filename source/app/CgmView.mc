using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Time;

// CGM history screen (swipe up from the glance): "Nm ago", the current reading + trend,
// and a 3-hour glucose plot whose Y-axis domain + gridlines follow the phone-configured plot
// floor/ceiling (Phase 09.13, D-05/D-06/D-07 — AppState.plotFloor/plotCeiling). Data comes from the
// phone (AppState.history, ~5-min spacing). A stale reading is shown grayed with its age called out.
// CGM-agnostic: works with whatever sensor the phone is sourcing.
class CgmView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        // Phase 09.13 (D-05/D-06/D-07/D-08): Garmin's Y-axis domain, read fresh every draw from the
        // small-screen-resolved AppState bounds (override when set, else the shared/phone bounds) —
        // no more hardcoded 40.0/300.0. The clamps below already pin both edges symmetrically, so this
        // becomes a symmetric clamp over the NEW bounds automatically (D-08).
        var VMIN = AppState.plotFloor.toFloat();
        var VMAX = AppState.plotCeiling.toFloat();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var stale = AppState.glucoseStale();
        var isHidden = AppState.glucoseHidden();

        // "N M AGO"
        var age = AppState.ageMinutes();
        var ageStr = (isHidden || age < 0) ? "--" : (age == 0 ? "NOW" : (age.toString() + "M AGO"));
        dc.setColor((stale && !isHidden) ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.11, Gfx.FONT_XTINY, ageStr, vc);

        // Current reading + trend arrow.
        var g = isHidden ? "--" : AppState.displayGlucose();
        dc.setColor((stale || isHidden) ? Gfx.COLOR_LT_GRAY : AppState.glucoseColor(), Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.22, Gfx.FONT_NUMBER_MEDIUM, g, vc);
        if (!isHidden && !stale && !AppState.trend.equals("")) {
            var gw = dc.getTextWidthInPixels(g, Gfx.FONT_NUMBER_MEDIUM);
            TrendArrow.draw(dc, cx + gw / 2 + 20, h * 0.22, 11, AppState.trend, AppState.glucoseColor());
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.32, Gfx.FONT_XTINY, AppState.glucoseUnitLabel(), vc);

        // Plot area.
        var plotL = w * 0.16, plotR = w * 0.84;
        var plotT = h * 0.42, plotB = h * 0.82;
        var plotH = plotB - plotT;

        // Gridlines with right-edge labels (y-axis max = VMAX). D-10: computed strictly INSIDE the
        // resolved [plotFloor, plotCeiling] domain (AppState.plotGridlines) so a gridline never lands
        // on the edge itself — never a hardcoded [100, 200, 300]. Positions (y) stay computed from the
        // mg/dL breakpoints — only the rendered LABEL TEXT converts to the active unit (same
        // domain-vs-label-text split as the phone's GlucoseChartView Y-axis, so a mmol user's plot
        // never shows a bare mg/dL gridline number).
        var lines = AppState.plotGridlines(AppState.plotFloor, AppState.plotCeiling);
        for (var i = 0; i < lines.size(); i += 1) {
            var v = lines[i];
            var y = plotB - ((v - VMIN) / (VMAX - VMIN)) * plotH;
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(plotL, y, plotR, y);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(plotR + w * 0.02, y, Gfx.FONT_XTINY, AppState.formatMgdl(v), Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        // Data dots (CGM-style). E5: when the phone sent per-point source timestamps (historyEpochs,
        // aligned 1:1 with history — enforced by the AppState parse), position each reading on a REAL
        // time x-axis so a data GAP renders as a horizontal gap, not evenly-spaced dots. When epochs
        // are unavailable/misaligned (historyEpochs empty), fall back to the exact prior uniform-index
        // spacing (~12 points/hour at 5-min spacing; newest points at the end of the array).
        var full = AppState.history;
        var epochs = AppState.historyEpochs;
        var size = full.size();
        var startIdx = (size > 288) ? (size - 288) : 0;   // ≤288 safety bound
        var timed = (epochs.size() == size) && (size > 0);
        var drawn = 0;
        if (timed) {
            // Real-time x-axis: window = [now - plotHours*3600, now]; only points inside it are drawn.
            var now = Time.now().value();
            var winStart = now - AppState.plotHours * 3600;
            var winSpan = now - winStart;
            if (winSpan < 1) { winSpan = 1; }   // guard divide-by-zero
            for (var k = startIdx; k < size; k += 1) {
                var val = full[k];
                var ep = epochs[k];
                if (!(val instanceof Lang.Number) && !(val instanceof Lang.Float)) { continue; }
                if (!(ep instanceof Lang.Number) && !(ep instanceof Lang.Float)) { continue; }
                var t = ep.toNumber();
                if (t < winStart || t > now) { continue; }   // outside the visible window
                var vv = val.toFloat();
                if (vv < VMIN) { vv = VMIN; }
                if (vv > VMAX) { vv = VMAX; }
                var px = plotL + (t - winStart).toFloat() / winSpan.toFloat() * (plotR - plotL);
                var py = plotB - ((vv - VMIN) / (VMAX - VMIN)) * plotH;
                dc.setColor(AppState.rangeColor(val.toNumber()), Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(px, py, 2);
                drawn += 1;
            }
        } else if (size >= 1) {
            // Fallback (no aligned epochs): uniform index spacing over the newest plotHours*12 points.
            var want = AppState.plotHours * 12;
            var start = (size > want) ? (size - want) : 0;
            var n = size - start;
            var span = (n > 1) ? (plotR - plotL) / (n - 1) : 0;
            for (var k = 0; k < n; k += 1) {
                var val = full[start + k];
                if (!(val instanceof Lang.Number) && !(val instanceof Lang.Float)) { continue; }
                var vv = val.toFloat();
                if (vv < VMIN) { vv = VMIN; }
                if (vv > VMAX) { vv = VMAX; }
                var px = plotL + span * k;
                var py = plotB - ((vv - VMIN) / (VMAX - VMIN)) * plotH;
                dc.setColor(AppState.rangeColor(val.toNumber()), Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(px, py, 2);
                drawn += 1;
            }
        }
        if (drawn == 0) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, (plotT + plotB) / 2, Gfx.FONT_XTINY, "no history", vc);
        }

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY, AppState.plotHours.toString() + " Hours (tap)", vc);
    }
}
