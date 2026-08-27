using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Bolus entry.
//   • Touch (venu3s): tap the mode chip (Units/Carbs), − / + to adjust, Deliver.
//   • Buttons: UP / DOWN adjust the amount directly, MENU switches Units/Carbs, START delivers —
//     button-native, no on-screen cursor.
class BolusEntryView extends Ui.View {
    function initialize() { View.initialize(); }

    // Poll once on entering the bolus screen: ask the phone to force a fresh CGM read so the estimate
    // is current (not continuously — battery). The phone also re-reads + runs the guard at delivery.
    function onShow() as Void {
        // 19-03 (G-M1): ROUTINE mint (fires on every screen show) — see RemoteComm.newRoutineRequestId().
        RemoteComm.send(RemoteComm.statusReadFresh(RemoteComm.newRoutineRequestId()));
    }

    // Shared geometry (pixels), so touch hit-testing matches what's drawn. [x,y,w,h] / [cx,cy].
    static function chipRect(w, h) { return [w / 2 - w * 0.24, h * 0.09, w * 0.48, h * 0.14]; }
    static function deliverRect(w, h) { return [w / 2 - w * 0.28, h * 0.74, w * 0.56, h * 0.15]; }
    static function minusCenter(w, h) { return [w * 0.17, h * 0.45]; }
    static function plusCenter(w, h) { return [w * 0.83, h * 0.45]; }
    static function stepRadius(w) { return w * 0.13; }

    // Greedy word-wrap: split `text` into centered lines each ≤ `maxW` pixels wide in `font`. Never
    // splits a single word (a too-long word gets its own line). Used only for the B2 disclosure copy so
    // the exact contract string renders in full on the small round screen instead of clipping.
    static function wrapLines(dc as Gfx.Dc, text as Lang.String, font, maxW as Lang.Number) as Lang.Array {
        var words = splitWords(text);
        var lines = [];
        var cur = "";
        for (var i = 0; i < words.size(); i += 1) {
            var word = words[i] as Lang.String;
            var trial = cur.equals("") ? word : cur + " " + word;
            if (cur.equals("") || dc.getTextWidthInPixels(trial, font) <= maxW) {
                cur = trial;
            } else {
                lines.add(cur);
                cur = word;
            }
        }
        if (!cur.equals("")) { lines.add(cur); }
        return lines;
    }

    // Split on spaces (Monkey C's String has no portable split-by-string across API levels; keep it
    // local and simple — the disclosure copy is plain ASCII words separated by single spaces).
    static function splitWords(text as Lang.String) as Lang.Array {
        var out = [];
        var cur = "";
        for (var i = 0; i < text.length(); i += 1) {
            var ch = text.substring(i, i + 1);
            if (ch.equals(" ")) {
                if (!cur.equals("")) { out.add(cur); cur = ""; }
            } else {
                cur += ch;
            }
        }
        if (!cur.equals("")) { out.add(cur); }
        return out;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var isUnits = AppState.mode.equals("units");
        var buttons = DeviceProfile.isButtons();

        // Mode chip.
        var cr = chipRect(w, h);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cr[0], cr[1], cr[2], cr[3], 8);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var chipHint = buttons ? " (MENU)" : " (tap)";
        dc.drawText(cx, cr[1] + cr[3] / 2, Gfx.FONT_TINY, (isUnits ? "Units" : "Carbs") + chipHint, vc);

        // − / + indicators. On buttons these are labelled with the physical keys that adjust.
        var mc = minusCenter(w, h), pc = plusCenter(w, h), r = stepRadius(w);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(mc[0], mc[1], r);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(pc[0], pc[1], r);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(mc[0], mc[1], Gfx.FONT_MEDIUM, "-", vc);
        dc.drawText(pc[0], pc[1], Gfx.FONT_MEDIUM, "+", vc);

        // Big value.
        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.45, Gfx.FONT_NUMBER_MEDIUM, AppState.valueLabel(), vc);

        var dr = deliverRect(w, h);

        // B2 (S1 + O3) auto-correction DISCLOSURE + SG (task #93) Insulin Stacking Guard DISCLOSURE — up
        // to two independent lines in the SAME band directly above the Deliver button (the S1 caution or
        // O3 ambient line, and separately the SG1/SG3a line; "" from either ⇒ that line just isn't
        // included). Bottom-anchored just above the button and grown UPWARD, each wrapped to the width in
        // FONT_XTINY so the exact faBolusCore contract strings render in full, each independently colored
        // (S1/SG3a-escalated = caution yellow, O3/SG1-only = neutral gray). DISPLAY-ONLY — neither ever
        // touches the button. The SG3a friction ceiling on this watch is the existing single HoldView
        // tap/hold below (Nav.mc:85 / HoldView.mc) — no new dialog, no re-type step is added here for any
        // SG friction tier.
        var discTopY = null;   // pixel y of the topmost disclosure block's top edge, when any is shown
        var discBlocks = [];   // [ [text, isCaution], ... ] one entry per disclosure that fired
        var ctrlLine = AppState.controllerDisclosureLine();
        if (!ctrlLine.equals("")) { discBlocks.add([ctrlLine, AppState.controllerDisclosureIsCaution()]); }
        var sgLine = AppState.sgDisclosureLine();
        if (!sgLine.equals("")) { discBlocks.add([sgLine, AppState.sgDisclosureIsCaution()]); }
        if (discBlocks.size() > 0) {
            var dfont = Gfx.FONT_XTINY;
            var maxW = (w * 0.92).toNumber();
            var fh = dc.getFontHeight(dfont);
            var lineH = fh * 0.95;
            var lines = [];      // physical lines, top-to-bottom, across ALL blocks
            var lineCaution = []; // parallel array: which color each physical line uses
            for (var b = 0; b < discBlocks.size(); b += 1) {
                var block = discBlocks[b];
                var wrapped = wrapLines(dc, block[0], dfont, maxW);
                for (var i = 0; i < wrapped.size(); i += 1) {
                    lines.add(wrapped[i]);
                    lineCaution.add(block[1]);
                }
            }
            var n = lines.size();
            var bottomCy = dr[1] - h * 0.02 - fh / 2.0;   // center of the LAST line, just above Deliver
            for (var i = 0; i < n; i += 1) {
                dc.setColor(lineCaution[i] ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, bottomCy - (n - 1 - i) * lineH, dfont, lines[i], vc);
            }
            discTopY = bottomCy - (n - 1) * lineH - fh / 2.0;
        }

        // Computed insulin (carbs mode) — kept clear of the value, the disclosure, and the Deliver
        // button. Default position is h*0.63; when a disclosure is shown it sits just ABOVE the block,
        // and is dropped for the frame only if there is no clean room (a rare long S1 on the smallest
        // device) — the exact deliverable dose is always shown on the hold-to-deliver screen regardless.
        // task #93 op-109 parity check: computeUnits()'s IOB term reads AppState.iob, which is a pure,
        // unrounded pass-through of the host's statusRead "units" field (op-109 swan6hrIOB — see
        // AppState.handle()) — the watch never re-derives IOB itself, on this line or on the Details
        // screen. The phone remains the single calculator + 0.10 U divergence guard at delivery.
        if (!isUnits) {
            var cuY = h * 0.63;
            var showCu = true;
            if (discTopY != null) {
                var above = discTopY - dc.getFontHeight(Gfx.FONT_XTINY);
                if (above < h * 0.55) { showCu = false; }
                else if (above < cuY) { cuY = above; }
            }
            if (showCu) {
                dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, cuY, Gfx.FONT_XTINY,
                            "~ " + AppState.computeUnits().format("%.2f") + " U", vc);
            }
        }

        // Deliver button.
        dc.setColor(0x5C6BE6, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(dr[0], dr[1], dr[2], dr[3], 10);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, dr[1] + dr[3] / 2, Gfx.FONT_SMALL,
                    buttons ? "Deliver (START)" : "Deliver", vc);

        // Button-mode hint: which physical keys do what (no on-screen cursor needed).
        if (buttons) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY, "UP / DOWN adjust", vc);
        }
    }
}
