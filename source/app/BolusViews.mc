using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi as Ui;

// Shown the first time the bolus is opened: where bolusing from the watch is turned on.
class BolusIntroView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Gfx.FONT_XTINY, "Watch bolus", vc);
        var lines = ["Bolusing from", "the watch is off", "by default.", "Turn it on or off", "in faBolus on",
                     "your phone."];
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(cx, h * (0.28 + 0.088 * i), Gfx.FONT_XTINY, lines[i], vc);
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.88, Gfx.FONT_XTINY, Nav.isTouch() ? "tap to continue" : "START to continue", vc);
    }
}

class BolusIntroDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return go(); }
    function onSelect() as Lang.Boolean { return Nav.isTouch() ? false : go(); }
    private function go() as Lang.Boolean {
        Nav.continueToEntry();
        return true;
    }
}

// Dialing the bolus: carbs through the calculator, or units.
class BolusEntryView extends Ui.View {
    function initialize() { View.initialize(); }

    static function chipRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.24, h * 0.09, w * 0.48, h * 0.14];
    }
    // Lower on a touch watch, where no button hint sits under it, to give the lines above room.
    static function deliverRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.28, Nav.isTouch() ? h * 0.77 : h * 0.74, w * 0.56, h * 0.15];
    }
    static function minusCenter(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> { return [w * 0.17, h * 0.45]; }
    static function plusCenter(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> { return [w * 0.83, h * 0.45]; }
    static function stepRadius(w as Lang.Number) as Lang.Numeric { return w * 0.13; }

    // The line under the value: the units the carbs come to, or why there's no number.
    static function previewLine(now as Lang.Number) as Lang.String {
        var block = BolusFlow.calculatorBlock(now);
        if (block != null) {
            // Outside the calculator's 20–600 mg/dL: said plainly, as what happened. The units mode is on the
            // same screen, and under 20 the advice isn't to dose.
            if (block.equals("low")) { return "Too low for a carb dose"; }
            if (block.equals("high")) { return "Too high for a carb dose"; }
            return "Waiting for pump settings";
        }
        var est = BolusFlow.estimate(now);
        if (est < 0) { return "Calculator unavailable"; }
        if (est > BolusFlow.dialMax()) { return "Over the " + Display.units(BolusFlow.dialMax()) + " U limit"; }
        // Both doses the question will offer, in its order: with the correction, then without.
        if (BolusFlow.correctionChoiceNeeded(now)) {
            return Display.units(est) + " U or " + Display.units(BolusFlow.estimateFrom(null)) + " U";
        }
        return Display.units(est) + " U";
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var units = BolusFlow.mode.equals("units");
        var touch = Nav.isTouch();

        var cr = chipRect(w, h);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cr[0], cr[1], cr[2], cr[3], 8);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cr[1] + cr[3] / 2, Gfx.FONT_TINY, (units ? "Units" : "Carbs") + (touch ? " (tap)" : " (MENU)"), vc);

        var mc = minusCenter(w, h);
        var pc = plusCenter(w, h);
        var r = stepRadius(w);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(mc[0], mc[1], r);
        dc.fillCircle(pc[0], pc[1], r);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(mc[0], mc[1], Gfx.FONT_MEDIUM, "-", vc);
        dc.drawText(pc[0], pc[1], Gfx.FONT_MEDIUM, "+", vc);

        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        var value = units ? Display.units(BolusFlow.unitsMU) + " U" : BolusFlow.carbs.toString() + " g";
        dc.drawText(cx, h * 0.45, Gfx.FONT_NUMBER_MEDIUM, value, vc);
        if (!units) {
            // Why the dose is what it is, under the number, when there's something to say.
            var message = BolusFlow.message(now);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            var touch2 = Nav.isTouch();
            dc.drawText(cx, message != null ? (touch2 ? h * 0.615 : h * 0.605) : h * 0.63, Gfx.FONT_XTINY,
                        previewLine(now), vc);
            if (message != null) {
                dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, touch2 ? h * 0.695 : h * 0.675, Gfx.FONT_XTINY, message, vc);
            }
        }

        var dr = deliverRect(w, h);
        // Grey while a press can't send anything, so it never looks ready when it isn't.
        var ready = BolusFlow.canDeliver(now);
        dc.setColor(ready ? 0x5C6BE6 : 0x333333, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(dr[0], dr[1], dr[2], dr[3], 10);
        dc.setColor(ready ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, dr[1] + dr[3] / 2, Gfx.FONT_SMALL, touch ? "Deliver" : "Deliver (START)", vc);
        if (!touch) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.92, Gfx.FONT_XTINY, "UP / DOWN adjust", vc);
        }
    }
}

class BolusEntryDelegate extends Ui.BehaviorDelegate {
    private var _view as BolusEntryView;

    function initialize(view as BolusEntryView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    private function near(x as Lang.Numeric, y as Lang.Numeric, c as Lang.Array<Lang.Numeric>, r as Lang.Numeric) as Lang.Boolean {
        var dx = x - c[0];
        var dy = y - c[1];
        return Math.sqrt(dx * dx + dy * dy) <= r * 1.3;
    }

    private function step(direction as Lang.Number) as Lang.Boolean {
        BolusFlow.adjust(direction);
        Ui.requestUpdate();
        return true;
    }

    private function toggle() as Lang.Boolean {
        BolusFlow.toggleMode();
        Ui.requestUpdate();
        return true;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        var w = size[0];
        var h = size[1];
        if (near(c[0], c[1], BolusEntryView.minusCenter(w, h), BolusEntryView.stepRadius(w))) { return step(-1); }
        if (near(c[0], c[1], BolusEntryView.plusCenter(w, h), BolusEntryView.stepRadius(w))) { return step(1); }
        if (Nav.inRect(c[0], c[1], BolusEntryView.chipRect(w, h))) { return toggle(); }
        if (Nav.inRect(c[0], c[1], BolusEntryView.deliverRect(w, h))) { return deliver(); }
        return true;
    }

    function onPreviousPage() as Lang.Boolean { return Nav.isTouch() ? false : step(1); }
    function onNextPage() as Lang.Boolean { return Nav.isTouch() ? false : step(-1); }
    function onMenu() as Lang.Boolean { return Nav.isTouch() ? false : toggle(); }
    function onSelect() as Lang.Boolean { return Nav.isTouch() ? false : deliver(); }

    private function deliver() as Lang.Boolean {
        var now = Status.now();
        // Asked again on every Deliver: an answer holds for the attempt it was given in.
        BolusFlow.declineCorrection = false;
        if (BolusFlow.mode.equals("carbs")) {
            if (BolusFlow.staleChoiceNeeded(now)) {
                var v = new StaleBolusView(now);
                Ui.pushView(v, new StaleBolusDelegate(v), Ui.SLIDE_LEFT);
                return true;
            }
            if (BolusFlow.calculatorBlock(now) != null) { return true; }
            if (BolusFlow.correctionChoiceNeeded(now)) {
                var c = new CorrectionView(now);
                Ui.pushView(c, new CorrectionDelegate(c), Ui.SLIDE_LEFT);
                return true;
            }
        }
        if (BolusFlow.arm(now)) { Nav.openConfirm(false); }
        return true;
    }
}

// Add a correction? (above target) / Reduce the bolus? (below it), asked from 70 mg/dL up when correcting
// changes the dose, as on the phone. Two halves, so a finger can't land one row off: correct on the left,
// carbs only on the right; BACK cancels. The next screen names the choice, and BACK there returns here.
// If the doses change while it shows (a new reading, IOB), a full screen says so, and a press
// there only brings back the question with the new doses, so a press aimed at the old ones never picks one.
// If the question no longer applies (under 70, stale, or correcting no longer changes the dose), a full
// screen says that too, and any press goes back to the dose screen.
class CorrectionView extends Ui.View {
    // On a button watch, the half START picks: 0 left, 1 right. It starts on the right, carbs only.
    public var cursor as Lang.Number = 1;
    // What the screen shows: the doses and which question. A change is noticed against it.
    private var _shown as Lang.String = "";
    // The reading the screen showed, and the one before it when the last change was a new reading.
    private var _shownGlucose as Lang.Number? = null;
    private var _was as Lang.Number? = null;
    // The doses changed and the user hasn't seen the new ones yet.
    public var changed as Lang.Boolean = false;

    function initialize(now as Lang.Number) {
        View.initialize();
        _shown = shownKey(BolusFlow.correctionDoses(now));
        _shownGlucose = Status.glucose();
    }

    // The doses and question the screen would draw for `doses` (BolusFlow.correctionDoses).
    static function shownKey(doses as Lang.Array<Lang.Number>?) as Lang.String {
        return doses == null ? "" : (above() ? "a" : "b") + doses[0] + "/" + doses[1];
    }

    // Whether the doses changed since the screen last showed them; if so, the change screen shows until the
    // user has seen it. True once per change.
    function noticeChange(now as Lang.Number) as Lang.Boolean { return noticeChangeIn(BolusFlow.correctionDoses(now)); }

    function noticeChangeIn(doses as Lang.Array<Lang.Number>?) as Lang.Boolean {
        var key = shownKey(doses);
        if (key.equals(_shown)) { return false; }
        _shown = key;
        var g = Status.glucose();
        _was = g != _shownGlucose ? _shownGlucose : null;
        _shownGlucose = g;
        changed = true;
        return true;
    }

    // The user saw the new doses: the question again.
    function seen() as Void { changed = false; }

    // The first line of a change screen: the BG the question showed and the one now, or `text` when it isn't
    // the BG that changed (or there's none to show).
    function drawWhatChanged(dc as Gfx.Dc, cx as Lang.Numeric, y as Lang.Numeric, old as Lang.Number?,
                             text as Lang.String?) as Void {
        if (text == null && old != null && Status.glucose() != null && old != Status.glucose()) {
            drawChange(dc, cx, y, old);
            return;
        }
        if (text == null) {
            drawReading(dc, cx, y);
            return;
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Gfx.FONT_XTINY, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // "BG", the reading the question showed and the one now, centred at `y`: the old one grey, an arrow, the
    // new one in its range's colour, the unit once. The arrow is drawn: the watch fonts have no arrow glyph.
    static function drawChange(dc as Gfx.Dc, cx as Lang.Numeric, y as Lang.Numeric, old as Lang.Number) as Void {
        var g = Status.glucose();
        var unit = Prefs.glucoseUnit();
        var font = Gfx.FONT_SMALL;
        var head = "BG ";
        var was = Display.glucose(old, unit) + " ";
        var now = " " + (g != null ? Display.glucose(g, unit) : "--") + " " + Display.glucoseUnit(unit);
        var arrow = (dc.getFontHeight(font) * 0.55).toNumber();
        var total = dc.getTextWidthInPixels(head, font) + dc.getTextWidthInPixels(was, font) + arrow
            + dc.getTextWidthInPixels(now, font);
        var x = cx - total / 2;
        var lv = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, head, lv);
        x += dc.getTextWidthInPixels(head, font);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, was, lv);
        x += dc.getTextWidthInPixels(was, font);
        var tip = arrow / 3;
        dc.setPenWidth(3);
        dc.drawLine(x, y, x + arrow - tip, y);
        dc.setPenWidth(1);
        dc.fillPolygon([[x + arrow - tip, y - tip], [x + arrow, y], [x + arrow - tip, y + tip]]);
        x += arrow;
        dc.setColor(g != null ? Display.rangeColor(g) : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, now, lv);
    }

    // "BG" and the reading, centred at `y`: the reading in its range's colour, as on the glucose screens.
    static function drawReading(dc as Gfx.Dc, cx as Lang.Numeric, y as Lang.Numeric) as Void {
        var g = Status.glucose();
        var unit = Prefs.glucoseUnit();
        var head = "BG ";
        var value = (g != null ? Display.glucose(g, unit) : "--") + " " + Display.glucoseUnit(unit);
        var font = Gfx.FONT_SMALL;
        var wHead = dc.getTextWidthInPixels(head, font);
        var x = cx - (wHead + dc.getTextWidthInPixels(value, font)) / 2;
        var lv = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, head, lv);
        dc.setColor(g != null ? Display.rangeColor(g) : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + wHead, y, font, value, lv);
    }

    static function halfRect(i as Lang.Number, w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [i == 0 ? w * 0.07 : w * 0.515, h * 0.45, w * 0.415, h * 0.28];
    }

    static function above() as Lang.Boolean { return BolusFlow.correctionAbove(); }

    // The two answers, left then right: the dose each gives, named as the confirm screen names it. The
    // number under it is the whole dose, not an amount added.
    static function label(choice as Lang.String) as Lang.String {
        if (choice.equals("apply")) { return above() ? "Corrected" : "Reduced"; }
        return above() ? "Carbs only" : "Not reduced";
    }

    static function dose(choice as Lang.String) as Lang.String {
        return doseText(BolusFlow.estimateFrom(choice.equals("apply") ? Status.glucose() : null));
    }

    static function doseText(mu as Lang.Number) as Lang.String { return Display.units(mu < 0 ? 0 : mu) + " U"; }

    // With the question gone, there's no dose to go on to: a reduction took it all, or there's none to give
    // (a CGM reading outside 20–600, the pump's settings not in, or a dose over the limit).
    static function noDoseToSee(now as Lang.Number) as Lang.Boolean {
        var est = BolusFlow.estimate(now);
        return BolusFlow.calculatorBlock(now) != null || est > BolusFlow.dialMax() || est < Calculator.STEP_MU;
    }

    // What the question going means for the dose: the reduction may leave a smaller dose, or take it all,
    // and with no dose to give at all, what the dose screen says.
    static function goneMeaning(now as Lang.Number) as Lang.String {
        var est = BolusFlow.estimate(now);
        // No dose to give at all: what the dose screen says, shorter where its line wouldn't fit this font.
        var block = BolusFlow.calculatorBlock(now);
        if (block != null && block.equals("waiting")) { return "Waiting for the pump"; }
        if (block == null && est < 0) { return "Can't calculate"; }
        if (block != null || est > BolusFlow.dialMax()) { return BolusEntryView.previewLine(now); }
        if (est < Calculator.STEP_MU) { return "No bolus"; }
        var g = Status.glucose();
        if (g == null || BolusFlow.glucoseStale(now) || Status.glucoseCaution() != null) { return "Carbs only now"; }
        return g < Calculator.LOW_GLUCOSE ? "Dose reduced" : "No correction needed";
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var now = Status.now();
        // The question no longer applies (a reading under 70 or gone stale, or IOB that took the correction
        // away): what changed, and the way back to the dose screen, which says why.
        // A change while the question shows reads in order: what changed, what it means, then what to do.
        var doses = BolusFlow.correctionDoses(now);
        if (doses == null) {
            // The question went: a low reduces the dose with no choice, IOB (or a BG now on target) leaves
            // no correction to add, a reduction took the whole dose, there's no current reading to correct
            // from, or no dose to give (a CGM reading outside 20–600, the pump's settings not in, or a dose
            // over the limit).
            var g = Status.glucose();
            var caution = Status.glucoseCaution();
            var noBG = g == null || BolusFlow.glucoseStale(now) || caution != null;
            var low = !noBG && (g as Lang.Number) < Calculator.LOW_GLUCOSE;
            // The question last showed `_shownGlucose`.
            // The lines centred as a group: the change and what it means either side of the middle, and for a
            // low the three (with what to do) about it.
            var top = low ? 0.40 : 0.44;
            if (caution != null) {
                // Why the pump flags it, in yellow as the dose screen's line and the stale question's.
                dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * top, Gfx.FONT_XTINY, BolusFlow.cautionTitle(caution as Lang.String), vc);
            } else {
                drawWhatChanged(dc, cx, h * top, _shownGlucose, noBG ? "No current BG" : null);
            }
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            var none = noDoseToSee(now);
            var meaning = goneMeaning(now);
            // A size down for a line too wide for the round screen at this height.
            var font = dc.getTextWidthInPixels(meaning, Gfx.FONT_SMALL) > w * 0.8 ? Gfx.FONT_TINY : Gfx.FONT_SMALL;
            dc.drawText(cx, h * (top + 0.13), font, meaning, vc);
            if (low) {
                dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.64, Gfx.FONT_XTINY, "Eat carbs", vc);
            }
            // At the bottom, where the other screens' hints are, apart from what the screen says.
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            // With no bolus there's no dose to see: the press just goes back.
            var hint = none ? (Nav.isTouch() ? "Tap to go back" : "START to go back")
                            : (Nav.isTouch() ? "Tap to see the dose" : "START to see the dose");
            dc.drawText(cx, h * 0.82, Gfx.FONT_XTINY, hint, vc);
            return;
        }
        noticeChangeIn(doses);
        if (changed) {
            // As prominent as the question: the doses moved under the user, and a press here picks nothing.
            // `_was`: the reading before this change (the shown one is already the new one).
            drawWhatChanged(dc, cx, h * 0.44, _was, _was == null ? "IOB or settings changed" : null);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.57, Gfx.FONT_SMALL, "Choose again", vc);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.82, Gfx.FONT_XTINY, Nav.isTouch() ? "Tap to see the doses" : "START to see the doses", vc);
            return;
        }
        var target = Status.field("calculator", "target");
        var unit = Prefs.glucoseUnit();
        // Low enough that the widest line clears the round edge.
        drawReading(dc, cx, h * 0.185);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.285, Gfx.FONT_XTINY,
                    (above() ? "above" : "below") + " target " + (target != null ? Display.glucose(target, unit) : "--")
                        + " " + Display.glucoseUnit(unit), vc);
        // White, so the reading's colour is the only one above the answers.
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.37, Gfx.FONT_XTINY, above() ? "Add a correction?" : "Reduce the bolus?", vc);
        var choices = ["apply", "carbsOnly"];
        for (var i = 0; i < 2; i += 1) {
            var r = halfRect(i, w, h);
            dc.setColor(i == 0 ? 0x2E4A7A : 0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 12);
            if (!Nav.isTouch() && i == cursor) {
                dc.setPenWidth(3);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(r[0], r[1], r[2], r[3], 12);
                dc.setPenWidth(1);
            }
            var mx = r[0] + r[2] / 2;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(mx, r[1] + r[3] * 0.32, Gfx.FONT_XTINY, label(choices[i]), vc);
            dc.drawText(mx, r[1] + r[3] * 0.66, Gfx.FONT_SMALL, doseText((doses as Lang.Array<Lang.Number>)[i]), vc);
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.825, Gfx.FONT_XTINY, Nav.isTouch() ? "BACK to cancel" : "UP/DOWN · START", vc);
    }
}

class CorrectionDelegate extends Ui.BehaviorDelegate {
    private var _view as CorrectionView;

    function initialize(view as CorrectionView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        // No question any more: any tap goes back to the dose screen. The change screen: any tap shows the
        // question again, with the new doses.
        if (!BolusFlow.correctionChoiceNeeded(Status.now())) { return choose("cancel"); }
        if (_view.noticeChange(Status.now()) || _view.changed) { return acknowledge(); }
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        if (Nav.inRect(c[0], c[1], CorrectionView.halfRect(0, size[0], size[1]))) { return choose("apply"); }
        if (Nav.inRect(c[0], c[1], CorrectionView.halfRect(1, size[0], size[1]))) { return choose("carbsOnly"); }
        return true;
    }

    function onPreviousPage() as Lang.Boolean { return Nav.isTouch() ? false : move(); }
    function onNextPage() as Lang.Boolean { return Nav.isTouch() ? false : move(); }
    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        if (!BolusFlow.correctionChoiceNeeded(Status.now())) { return choose("cancel"); }
        if (_view.noticeChange(Status.now()) || _view.changed) { return acknowledge(); }
        return choose(_view.cursor == 0 ? "apply" : "carbsOnly");
    }

    private function acknowledge() as Lang.Boolean {
        _view.seen();
        Ui.requestUpdate();
        return true;
    }
    function onBack() as Lang.Boolean { return choose("cancel"); }

    private function move() as Lang.Boolean {
        _view.cursor = 1 - _view.cursor;
        Ui.requestUpdate();
        return true;
    }

    // The answer holds for this attempt; the dose armed is the one the chosen half showed. Cancel sends
    // nothing.
    function choose(choice as Lang.String) as Lang.Boolean {
        var now = Status.now();
        if (choice.equals("cancel")) {
            BolusFlow.declineCorrection = false;
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        if (!BolusFlow.correctionChoiceNeeded(now)) { return choose("cancel"); }
        // Doses that changed since the screen showed them aren't what the user aimed at: the change screen
        // shows instead, and nothing is armed.
        if (_view.noticeChange(Status.now()) || _view.changed) {
            Ui.requestUpdate();
            return true;
        }
        BolusFlow.declineCorrection = choice.equals("carbsOnly");
        if (BolusFlow.calculatorBlock(now) != null || !BolusFlow.arm(now)) {
            BolusFlow.declineCorrection = false;
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        Nav.openConfirm(true);
        return true;
    }
}

// The reading is stale: correct from it anyway or use the carbs only, laid out as the correction question
// so a finger can't land one row off: include on the left, carbs only on the right, each with the whole
// dose it gives; BACK cancels. Asked only while the reading may be included: past that (or outside 20–600
// mg/dL) the dose screen says carbs only instead. If the question goes while it shows (the reading ages past
// it, or a fresh one arrives), a full screen says so, as the correction question's does, and any press goes
// back to the dose screen. Doses that change while it shows are drawn again, and a press aimed at the old
// ones picks nothing.
class StaleBolusView extends Ui.View {
    // On a button watch, the choice START picks. It starts on carbs only.
    public var cursor as Lang.Number = 0;
    // The doses the screen showed, so a press is only taken for doses the user saw.
    public var shown as Lang.String = "";

    function initialize(now as Lang.Number) {
        View.initialize();
        shown = shownKey(now);
    }

    // The choices, left to right.
    static function choices() as Lang.Array<Lang.String> { return ["include", "carbsOnly"]; }

    // The dose a choice gives, in milliunits.
    static function doseMU(choice as Lang.String) as Lang.Number {
        return BolusFlow.estimateFrom(choice.equals("include") ? Status.glucose() : null);
    }

    static function shownKey(now as Lang.Number) as Lang.String {
        if (!BolusFlow.staleChoiceNeeded(now)) { return ""; }
        var list = choices();
        var key = "";
        for (var i = 0; i < list.size(); i += 1) { key += list[i] + doseMU(list[i]) + "/"; }
        return key;
    }


    static function label(choice as Lang.String) as Lang.String {
        return choice.equals("include") ? "Include" : "Carbs only";
    }

    function onShow() as Void {
        // Buttons start on the choice that doesn't correct from the old reading.
        cursor = 1;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        shown = shownKey(now);
        var unit = Prefs.glucoseUnit();
        var g = Status.glucose();
        if (!BolusFlow.staleChoiceNeeded(now)) {
            // The question went: what changed, what it means, and the way back to the dose screen, which
            // says it too. Laid out as the correction question's.
            var fresh = g != null && !BolusFlow.glucoseStale(now);
            if (fresh) {
                CorrectionView.drawReading(dc, cx, h * 0.44);
            } else {
                dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.44, Gfx.FONT_XTINY,
                            g == null ? "No CGM" : "Stale CGM · " + Display.ago(Glucose.age(now)), vc);
            }
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            // What it means for the dose, as the correction question's gone screen says it ("Carbs only now",
            // or no dose to give); with no dose to see, the press just goes back.
            var meaning = fresh ? "New reading" : CorrectionView.goneMeaning(now);
            var font = dc.getTextWidthInPixels(meaning, Gfx.FONT_SMALL) > w * 0.8 ? Gfx.FONT_TINY : Gfx.FONT_SMALL;
            dc.drawText(cx, h * 0.57, font, meaning, vc);
            var none = !fresh && CorrectionView.noDoseToSee(now);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.82, Gfx.FONT_XTINY,
                        none ? (Nav.isTouch() ? "Tap to go back" : "START to go back")
                             : (Nav.isTouch() ? "Tap to see the dose" : "START to see the dose"), vc);
            return;
        }
        // The old reading in grey: it isn't current, so it doesn't take its range's colour.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.185, Gfx.FONT_SMALL,
                    "BG " + (g != null ? Display.glucose(g, unit) : "--") + " " + Display.glucoseUnit(unit), vc);
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.285, Gfx.FONT_XTINY, "Stale CGM · " + Display.ago(Glucose.age(now)), vc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.37, Gfx.FONT_XTINY, "Include it?", vc);
        var list = choices();
        for (var i = 0; i < list.size(); i += 1) {
            var r = CorrectionView.halfRect(i, w, h);
            dc.setColor(list[i].equals("include") ? 0x2E4A7A : 0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 12);
            if (!Nav.isTouch() && i == cursor) {
                dc.setPenWidth(3);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(r[0], r[1], r[2], r[3], 12);
                dc.setPenWidth(1);
            }
            var mx = r[0] + r[2] / 2;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(mx, r[1] + r[3] * 0.32, Gfx.FONT_XTINY, label(list[i]), vc);
            dc.drawText(mx, r[1] + r[3] * 0.66, Gfx.FONT_SMALL, CorrectionView.doseText(doseMU(list[i])), vc);
        }
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.825, Gfx.FONT_XTINY, Nav.isTouch() ? "BACK to cancel" : "UP/DOWN · START", vc);
    }
}

class StaleBolusDelegate extends Ui.BehaviorDelegate {
    private var _view as StaleBolusView;

    function initialize(view as StaleBolusView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        // No question any more: any tap goes back to the dose screen.
        if (!BolusFlow.staleChoiceNeeded(Status.now())) { return choose("cancel"); }
        var list = StaleBolusView.choices();
        for (var i = 0; i < list.size(); i += 1) {
            if (Nav.inRect(c[0], c[1], CorrectionView.halfRect(i, size[0], size[1]))) { return choose(list[i]); }
        }
        return true;
    }

    function onPreviousPage() as Lang.Boolean { return Nav.isTouch() ? false : move(); }
    function onNextPage() as Lang.Boolean { return Nav.isTouch() ? false : move(); }
    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        return choose(StaleBolusView.choices()[_view.cursor % 2]);
    }
    function onBack() as Lang.Boolean { return choose("cancel"); }

    private function move() as Lang.Boolean {
        _view.cursor = 1 - _view.cursor;
        Ui.requestUpdate();
        return true;
    }

    // "include" is the only choice that corrects from the stale reading; it holds for this attempt only.
    // Cancel sends nothing.
    function choose(choice as Lang.String) as Lang.Boolean {
        var now = Status.now();
        // The question went (the reading aged past includable, or a fresh one came): back to the dose screen,
        // which says what applies.
        if (choice.equals("cancel") || !BolusFlow.staleChoiceNeeded(now)) {
            BolusFlow.includeStale = false;
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        // Doses other than the ones shown: drawn again, and this press picks nothing.
        if (!StaleBolusView.shownKey(now).equals(_view.shown)) {
            Ui.requestUpdate();
            return true;
        }
        BolusFlow.includeStale = choice.equals("include") && BolusFlow.staleIncludable(now);
        if (BolusFlow.calculatorBlock(now) != null || !BolusFlow.arm(now)) {
            BolusFlow.includeStale = false;
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        Nav.openConfirm(true);
        return true;
    }
}

// The deliberate confirm: tap 1 → 2 → 3 in order on a touch watch (a wrong tap starts over), or hold UP
// then hold START on a button watch. Then the request's progress, from the phone.
class HoldView extends Ui.View {
    private var _taps as Lang.Number = 0;
    public var armed as Lang.Boolean = false;
    public var holdProgress as Lang.Float = 0.0;
    private var _homeTimer as Timer.Timer?;
    // The confirm went through and a request went out; from here the screen shows the request.
    public var sent as Lang.Boolean = false;
    // Another view is over this one. A press or hold that view took isn't this confirm's.
    public var covered as Lang.Boolean = false;

    function initialize() { View.initialize(); }

    function onShow() as Void { covered = false; }

    // Covered (an alert card, say), the confirm starts over: the release of a hold goes to the view on top,
    // so a hold left running here would finish and send a bolus the user had let go of.
    function onHide() as Void {
        var t = _homeTimer;
        if (t != null) { t.stop(); }
        _homeTimer = null;
        covered = true;
        if (!sent) {
            _taps = 0;
            armed = false;
            holdProgress = 0.0;
        }
    }

    static function center(i as Lang.Number, w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        var xs = [0.23, 0.50, 0.77];
        return [(w * xs[i]).toNumber(), (h * 0.50).toNumber()];
    }

    // The dose as the phone's review splits it, in one line: the food, then what the glucose did to it, or
    // null for a units dose. The parts add up to the dose; "-" for a reduction, as the watch fonts have no
    // minus sign. The second part also names the answer when the dose came from the correction question.
    static function splitParts() as Lang.Array<Lang.String>? {
        var split = BolusFlow.armedSplit();
        if (split == null) { return null; }
        var food = Display.units(split[0]) + " food";
        var choice = BolusFlow.armedChoice();
        if (!BolusFlow.armedCorrects()) {
            return [food, choice != null && choice.equals("Not reduced") ? " · not reduced" : " · no correction"];
        }
        var c = split[1];
        if (c > -5 && c < 5) { return [food, " · no correction"]; }
        return [food, c > 0 ? " + " + Display.units(c) + " correction" : " - " + Display.units(-c) + " reduction"];
    }

    static function splitText() as Lang.String? {
        var parts = splitParts();
        return parts == null ? null : parts[0] + parts[1];
    }

    // The split centred at `y`: the food grey, the rest yellow when it is the user's answer, so a mistap on
    // the question shows before anything is sent.
    static function drawSplit(dc as Gfx.Dc, cx as Lang.Numeric, y as Lang.Numeric) as Void {
        var parts = splitParts();
        if (parts == null) { return; }
        var font = Gfx.FONT_XTINY;
        var w0 = dc.getTextWidthInPixels(parts[0], font);
        var x = cx - (w0 + dc.getTextWidthInPixels(parts[1], font)) / 2;
        var lv = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, parts[0], lv);
        dc.setColor(BolusFlow.armedChoice() != null ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + w0, y, font, parts[1], lv);
    }
    static function radius(w as Lang.Number) as Lang.Number { return (w * 0.11).toNumber(); }
    static function cancelRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.26, h * 0.66, w * 0.52, h * 0.15];
    }
    // Wider than Cancel, for the dose it names.
    static function goOnRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.33, h * 0.66, w * 0.66, h * 0.15];
    }

    function taps() as Lang.Number { return _taps; }

    // A tap on circle `n`: in order it counts, out of order it starts over; the third sends.
    function tapped(n as Lang.Number) as Void {
        if (sent) { return; }
        if (n == _taps + 1) {
            _taps += 1;
            if (_taps >= 3) { deliver(); }
        } else {
            _taps = 0;
        }
        Ui.requestUpdate();
    }

    function deliver() as Void {
        if (sent) { return; }
        if (BolusFlow.send(Status.now())) {
            sent = true;
        } else {
            _taps = 0;
            armed = false;
            holdProgress = 0.0;
        }
    }

    // The phone asked for a confirmation before the dose goes: the same dose is armed again, with what it
    // asked confirmed, and the user confirms it with 1 → 2 → 3 (or the holds) as before. Never sent here.
    function reconfirm() as Void {
        if (!sent) { return; }
        if (BolusFlow.armConfirmed(Status.now())) {
            sent = false;
            _taps = 0;
            armed = false;
            holdProgress = 0.0;
        } else {
            Toast.show("Can't confirm — start over");
        }
        Ui.requestUpdate();
    }

    // Back to the first screen a moment after a delivered bolus.
    function goHome() as Void {
        BolusFlow.forgetIfSettled();
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        var vd = Nav.initialView();
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_RIGHT);
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        if (sent) {
            drawRequest(dc, w, h, cx, vc);
            return;
        }
        var block = BolusFlow.armBlock(now);
        if (block != null) {
            // The state the dose was confirmed against has moved: nothing is sent, and the user starts over.
            _taps = 0;
            armed = false;
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.40, Gfx.FONT_SMALL, BolusFlow.armBlockText(block), vc);
            dc.drawText(cx, h * 0.54, Gfx.FONT_XTINY, "not sent — start over", vc);
            dc.drawText(cx, h * 0.80, Gfx.FONT_XTINY, "BACK to exit", vc);
            return;
        }
        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        var choice = BolusFlow.armedChoice();
        if (Nav.isTouch()) {
            // The dose and what it's made of (with the answer it came from) on top; how to send it under the
            // circles.
            dc.drawText(cx, h * 0.20, Gfx.FONT_MEDIUM, Display.units(BolusFlow.armedDose()) + " U", vc);
            drawSplit(dc, cx, h * 0.31);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.69, Gfx.FONT_XTINY, "Tap 1 - 2 - 3 in order", vc);
            // Always the way out: back to the question that gave the dose, or back to the dose screen. Nothing
            // is sent either way.
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.83, Gfx.FONT_XTINY, choice != null ? "BACK to change" : "BACK to cancel", vc);
            var r = radius(w);
            for (var i = 0; i < 3; i += 1) {
                var c = center(i, w, h);
                dc.setColor((i + 1) <= _taps ? Gfx.COLOR_GREEN : 0x333333, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(c[0], c[1], r);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(c[0], c[1], Gfx.FONT_NUMBER_MEDIUM, (i + 1).toString(), vc);
            }
        } else {
            dc.drawText(cx, h * 0.14, Gfx.FONT_SMALL, Display.units(BolusFlow.armedDose()) + " U", vc);
            drawSplit(dc, cx, h * 0.22);
            dc.setColor(armed ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.34, Gfx.FONT_XTINY, armed ? "1. armed" : "1. Hold UP to arm", vc);
            dc.setColor(armed ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.48, Gfx.FONT_XTINY, armed ? "2. Hold START to deliver" : "2. then hold START", vc);
            var bx = w * 0.22;
            var bw = w * 0.56;
            var by = h * 0.62;
            var bh = h * 0.06;
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, bw, bh, 4);
            if (holdProgress > 0.0) {
                dc.setColor(armed ? Gfx.COLOR_GREEN : Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(bx, by, bw * holdProgress, bh, 4);
            }
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.74, Gfx.FONT_XTINY, "release cancels", vc);
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.84, Gfx.FONT_XTINY, BolusFlow.armedChoice() != null ? "BACK to change" : "BACK to cancel", vc);
        }
    }

    private function drawRequest(dc as Gfx.Dc, w as Lang.Number, h as Lang.Number, cx as Lang.Number,
                                 vc as Lang.Number) as Void {
        var state = BolusFlow.state();
        var now = Status.now();
        // Once per frame, so the headline, the text and the button agree at the 2-minute edge.
        var asking = BolusFlow.confirmable(now);
        var color = Gfx.COLOR_BLUE;
        if (state.equals("delivered")) {
            color = Gfx.COLOR_GREEN;
            if (_homeTimer == null) {
                var t = new Timer.Timer();
                t.start(method(:goHome), 2500, false);
                _homeTimer = t;
            }
        } else if (state.equals("stopped")) {
            color = Gfx.COLOR_ORANGE;
        } else if (asking) {
            // A question, not a failure.
            color = Gfx.COLOR_YELLOW;
        } else if (state.equals("refused") || state.equals("failed") || state.equals("notSent")) {
            color = Gfx.COLOR_RED;
        } else if (state.equals("unknown") || state.equals("noAnswer")) {
            color = Gfx.COLOR_YELLOW;
        }
        // What the phone asks to confirm needs more room than a reason: the headline moves up for it.
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, asking ? h * 0.20 : h * 0.30, Gfx.FONT_MEDIUM, BolusFlow.headline(now), vc);
        var delivered = BolusFlow.deliveredMU();
        var line = BolusFlow.text();
        if (delivered != null) { line = Display.units(delivered) + " U delivered"; }
        if (line != null) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            var y = asking ? h * 0.44 : h * 0.47;
            var area = asking ? h * 0.36 : h * 0.20;
            dc.drawText(cx, y, Gfx.FONT_XTINY, Gfx.fitTextToArea(line, Gfx.FONT_XTINY, w * 0.80, area, true), vc);
        }
        if (asking) {
            var r = goOnRect(w, h);
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 10);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            // The dose on the button: the phone's message can be cut short, and this is what going on sends.
            var mu = BolusFlow.requestedMU();
            var label = mu != null ? "Go on: " + Display.units(mu) + " U" : "Go on";
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_SMALL, Nav.isTouch() ? label : label + " (START)", vc);
        } else if (BolusFlow.canCancel()) {
            var r = cancelRect(w, h);
            dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 10);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_SMALL, Nav.isTouch() ? "Cancel" : "Cancel (START)", vc);
        } else {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.80, Gfx.FONT_XTINY, "BACK to exit", vc);
        }
    }
}

class HoldDelegate extends Ui.BehaviorDelegate {
    private const HOLD_MS = 1500;
    private var _view as HoldView;
    private var _timer as Timer.Timer?;
    private var _holding as Lang.Number? = null;
    private var _holdStart as Lang.Number = 0;

    function initialize(view as HoldView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        var w = size[0];
        var h = size[1];
        if (_view.sent) {
            if (BolusFlow.confirmable(Status.now())) {
                if (Nav.inRect(c[0], c[1], HoldView.goOnRect(w, h))) { _view.reconfirm(); }
            } else if (BolusFlow.canCancel() && Nav.inRect(c[0], c[1], HoldView.cancelRect(w, h))) {
                cancel();
            }
            return true;
        }
        var r = HoldView.radius(w);
        for (var i = 0; i < 3; i += 1) {
            var ctr = HoldView.center(i, w, h);
            var dx = c[0] - ctr[0];
            var dy = c[1] - ctr[1];
            if (Math.sqrt(dx * dx + dy * dy) <= r * 1.3) {
                _view.tapped(i + 1);
                return true;
            }
        }
        return true;
    }

    function onKeyPressed(evt as Ui.KeyEvent) as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        var k = evt.getKey();
        if (_view.sent) {
            if (k == Ui.KEY_ENTER || k == Ui.KEY_START) {
                if (BolusFlow.confirmable(Status.now())) { _view.reconfirm(); }
                else if (BolusFlow.canCancel()) { cancel(); }
            }
            return true;
        }
        if (!_view.armed && k == Ui.KEY_UP) { begin(k); }
        else if (_view.armed && (k == Ui.KEY_ENTER || k == Ui.KEY_START)) { begin(k); }
        return true;
    }

    function onKeyReleased(evt as Ui.KeyEvent) as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        if (_holding != null && evt.getKey() == _holding) { release(); }
        return true;
    }

    // Leaving: a settled request is forgotten; an open one is kept and still asked about. Before sending, a
    // dose that came from the correction question goes back to it, to change the answer.
    function onBack() as Lang.Boolean {
        stop();
        if (!_view.sent && BolusFlow.armedChoice() != null) {
            BolusFlow.declineCorrection = false;
            var c = new CorrectionView(Status.now());
            Ui.switchToView(c, new CorrectionDelegate(c), Ui.SLIDE_RIGHT);
            return true;
        }
        BolusFlow.forgetIfSettled();
        return false;
    }

    private function begin(k as Lang.Number) as Void {
        holdFrom(k, System.getTimer());
        var t = new Timer.Timer();
        t.start(method(:onTick), 80, true);
        _timer = t;
    }

    // A hold of key `k` starting at `startMs` (System.getTimer()).
    function holdFrom(k as Lang.Number, startMs as Lang.Number) as Void {
        stop();
        _holding = k;
        _holdStart = startMs;
        _view.holdProgress = 0.0;
    }

    function holding() as Lang.Number? { return _holding; }

    function onTick() as Void { tickAt(System.getTimer()); }

    // A hold ends when its key is released, or, finished, arms (UP) or sends (START). One whose screen was
    // covered meanwhile just ends: its release went elsewhere.
    function tickAt(nowMs as Lang.Number) as Void {
        var k = _holding;
        if (k == null || _view.covered) {
            _holding = null;
            _view.holdProgress = 0.0;
            stop();
            return;
        }
        var frac = (nowMs - _holdStart).toFloat() / HOLD_MS;
        if (frac >= 1.0) {
            _holding = null;
            _view.holdProgress = 0.0;
            stop();
            // START sends only while the confirm is still armed: the screen disarms it when the dose can't go,
            // and says so.
            if (k == Ui.KEY_UP) { _view.armed = true; } else if (_view.armed) { _view.deliver(); }
        } else {
            _view.holdProgress = frac;
        }
        Ui.requestUpdate();
    }

    private function release() as Void {
        _holding = null;
        _view.holdProgress = 0.0;
        stop();
        Ui.requestUpdate();
    }

    private function stop() as Void {
        var t = _timer;
        if (t != null) { t.stop(); }
        _timer = null;
    }

    private function cancel() as Void {
        Toast.show(BolusFlow.cancel(Status.now()) ? "Cancel sent" : "Not sent — try again");
        Ui.requestUpdate();
    }
}
