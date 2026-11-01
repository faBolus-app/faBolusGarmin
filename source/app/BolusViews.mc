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
    static function deliverRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.28, h * 0.74, w * 0.56, h * 0.15];
    }
    static function minusCenter(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> { return [w * 0.17, h * 0.45]; }
    static function plusCenter(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> { return [w * 0.83, h * 0.45]; }
    static function stepRadius(w as Lang.Number) as Lang.Numeric { return w * 0.13; }

    // The line under the value: the units the carbs come to, or why there's no number.
    static function previewLine(now as Lang.Number) as Lang.String {
        var block = BolusFlow.calculatorBlock(now);
        if (block != null) {
            if (block.equals("low")) { return "CGM LOW: use units"; }
            if (block.equals("high")) { return "CGM HIGH: use units"; }
            return "Waiting for pump settings";
        }
        var est = BolusFlow.estimate(now);
        if (est < 0) { return "Calculator unavailable"; }
        if (est > BolusFlow.dialMax()) { return "Over the " + Display.units(BolusFlow.dialMax()) + " U limit"; }
        return "~ " + Display.units(est) + " U";
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
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.63, Gfx.FONT_XTINY, previewLine(now), vc);
        }

        var dr = deliverRect(w, h);
        dc.setColor(0x5C6BE6, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(dr[0], dr[1], dr[2], dr[3], 10);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
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
        if (BolusFlow.mode.equals("carbs")) {
            if (BolusFlow.staleChoiceNeeded(now)) {
                var v = new StaleBolusView();
                Ui.pushView(v, new StaleBolusDelegate(v), Ui.SLIDE_LEFT);
                return true;
            }
            if (BolusFlow.calculatorBlock(now) != null) { return true; }
        }
        if (BolusFlow.arm(now)) { Nav.openConfirm(false); }
        return true;
    }
}

// The reading is stale: correct from it anyway, use the carbs only, or go back. A reading outside
// 40–400 mg/dL can't be corrected from, so that choice isn't offered for one.
class StaleBolusView extends Ui.View {
    public var cursor as Lang.Number = 0;

    function initialize() { View.initialize(); }

    // The choices on offer, in order.
    static function choices() as Lang.Array<Lang.String> {
        return BolusFlow.staleIncludable(Status.now()) ? ["include", "carbsOnly", "cancel"] : ["carbsOnly", "cancel"];
    }

    static function rowRect(i as Lang.Number, w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w * 0.14, h * (0.32 + 0.165 * i), w * 0.72, h * 0.145];
    }

    static function label(choice as Lang.String) as Lang.String {
        if (choice.equals("include")) { return "Include reading"; }
        if (choice.equals("carbsOnly")) { return "Carbs only"; }
        return "Cancel";
    }

    function onShow() as Void {
        // Buttons start on the choice that doesn't correct from the old reading.
        cursor = BolusFlow.staleIncludable(Status.now()) ? 1 : 0;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Gfx.FONT_XTINY, "Stale CGM", vc);
        var g = Status.glucose();
        var head = (g != null ? Display.glucose(g, Prefs.glucoseUnit()) : "--") + " " + Display.glucoseUnit(Prefs.glucoseUnit())
            + " · " + Display.ago(Glucose.age(now));
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.21, Gfx.FONT_XTINY, head, vc);
        var list = choices();
        for (var i = 0; i < list.size(); i += 1) {
            var r = rowRect(i, w, h);
            dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 8);
            if (!Nav.isTouch() && i == cursor) {
                dc.setPenWidth(2);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(r[0], r[1], r[2], r[3], 8);
                dc.setPenWidth(1);
            }
            var choice = list[i];
            dc.setColor(choice.equals("include") ? Gfx.COLOR_YELLOW : choice.equals("cancel") ? Gfx.COLOR_LT_GRAY : Gfx.COLOR_WHITE,
                        Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_XTINY, label(choice), vc);
        }
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
        var list = StaleBolusView.choices();
        for (var i = 0; i < list.size(); i += 1) {
            if (Nav.inRect(c[0], c[1], StaleBolusView.rowRect(i, size[0], size[1]))) { return choose(list[i]); }
        }
        return true;
    }

    function onPreviousPage() as Lang.Boolean { return Nav.isTouch() ? false : move(-1); }
    function onNextPage() as Lang.Boolean { return Nav.isTouch() ? false : move(1); }
    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        var list = StaleBolusView.choices();
        return choose(list[_view.cursor % list.size()]);
    }
    function onBack() as Lang.Boolean { return choose("cancel"); }

    private function move(d as Lang.Number) as Lang.Boolean {
        var n = StaleBolusView.choices().size();
        _view.cursor = (_view.cursor + d + n) % n;
        Ui.requestUpdate();
        return true;
    }

    // "include" is the only choice that corrects from the stale reading; it holds for this attempt only.
    // Cancel sends nothing.
    function choose(choice as Lang.String) as Lang.Boolean {
        var now = Status.now();
        if (choice.equals("cancel")) {
            BolusFlow.includeStale = false;
            Ui.popView(Ui.SLIDE_RIGHT);
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
    static function radius(w as Lang.Number) as Lang.Number { return (w * 0.11).toNumber(); }
    static function cancelRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        return [w / 2 - w * 0.26, h * 0.66, w * 0.52, h * 0.15];
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
        dc.drawText(cx, h * 0.14, Gfx.FONT_SMALL, Display.units(BolusFlow.armedDose()) + " U", vc);
        if (Nav.isTouch()) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.28, Gfx.FONT_XTINY, "Tap 1 - 2 - 3 in order", vc);
            var r = radius(w);
            for (var i = 0; i < 3; i += 1) {
                var c = center(i, w, h);
                dc.setColor((i + 1) <= _taps ? Gfx.COLOR_GREEN : 0x333333, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(c[0], c[1], r);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(c[0], c[1], Gfx.FONT_NUMBER_MEDIUM, (i + 1).toString(), vc);
            }
        } else {
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
            dc.drawText(cx, h * 0.76, Gfx.FONT_XTINY, "release cancels", vc);
        }
    }

    private function drawRequest(dc as Gfx.Dc, w as Lang.Number, h as Lang.Number, cx as Lang.Number,
                                 vc as Lang.Number) as Void {
        var state = BolusFlow.state();
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
        } else if (state.equals("refused") || state.equals("failed") || state.equals("notSent")) {
            color = Gfx.COLOR_RED;
        } else if (state.equals("unknown") || state.equals("noAnswer")) {
            color = Gfx.COLOR_YELLOW;
        }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.30, Gfx.FONT_MEDIUM, BolusFlow.headline(Status.now()), vc);
        var delivered = BolusFlow.deliveredMU();
        var line = BolusFlow.text();
        if (delivered != null) { line = Display.units(delivered) + " U delivered"; }
        if (line != null) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.47, Gfx.FONT_XTINY, Gfx.fitTextToArea(line, Gfx.FONT_XTINY, w * 0.80, h * 0.20, true), vc);
        }
        if (BolusFlow.canCancel()) {
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
            if (BolusFlow.canCancel() && Nav.inRect(c[0], c[1], HoldView.cancelRect(w, h))) { cancel(); }
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
            if (BolusFlow.canCancel() && (k == Ui.KEY_ENTER || k == Ui.KEY_START)) { cancel(); }
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

    // Leaving: a settled request is forgotten; an open one is kept and still asked about.
    function onBack() as Lang.Boolean {
        stop();
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
