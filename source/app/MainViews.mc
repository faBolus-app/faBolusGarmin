using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi as Ui;

// The glance screen (glucose and the bolus button) and the glucose-only screen.
class MainView extends Ui.View {
    private var _showBolus as Lang.Boolean;

    function initialize(showBolus as Lang.Boolean) {
        View.initialize();
        _showBolus = showBolus;
    }

    static function buttonRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        var bw = w * 0.52;
        var bh = h * 0.17;
        return [w / 2 - bw / 2, h * 0.68, bw, bh];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var now = Status.now();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // A hint that more screens are a swipe away.
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, h * 0.045], [cx - 9, h * 0.075], [cx + 9, h * 0.075]]);

        Screens.drawGlucose(dc, cx, h * 0.36, Gfx.FONT_NUMBER_HOT, now);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.55, Gfx.FONT_XTINY, Display.glucoseUnit(Prefs.glucoseUnit()), vc);
        if (!Glucose.isHidden(now)) {
            dc.setColor(Glucose.stale(now) ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.63, Gfx.FONT_XTINY, Display.ago(Glucose.age(now)), vc);
        }
        if (_showBolus) {
            Screens.drawBolusButton(dc, buttonRect(w, h), now, Gfx.FONT_SMALL);
        } else {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.78, Gfx.FONT_XTINY, Display.linkLine(now), vc);
        }
    }
}

class MainDelegate extends Ui.BehaviorDelegate {
    private var _showBolus as Lang.Boolean;
    private var _id as Lang.String;

    function initialize(showBolus as Lang.Boolean, id as Lang.String) {
        BehaviorDelegate.initialize();
        _showBolus = showBolus;
        _id = id;
    }

    function press() as Lang.Boolean {
        if (_showBolus) { Nav.pressBolus(); }
        return true;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        if (Nav.inRect(c[0], c[1], MainView.buttonRect(size[0], size[1]))) { return press(); }
        // Taps elsewhere are swallowed, so a stray touch doesn't open the bolus.
        return true;
    }

    function onSelect() as Lang.Boolean { return Nav.isTouch() ? false : press(); }
    function onNextPage() as Lang.Boolean { return Nav.goNext(_id); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev(_id); }
}

// A screen that is only the bolus button.
class BolusOnlyView extends Ui.View {
    function initialize() { View.initialize(); }

    static function buttonRect(w as Lang.Number, h as Lang.Number) as Lang.Array<Lang.Numeric> {
        var bw = w * 0.60;
        var bh = h * 0.28;
        return [w / 2 - bw / 2, h / 2 - bh / 2, bw, bh];
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        Screens.drawBolusButton(dc, buttonRect(dc.getWidth(), dc.getHeight()), Status.now(), Gfx.FONT_MEDIUM);
    }
}

class BolusOnlyDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var size = Nav.screenSize();
        if (Nav.inRect(c[0], c[1], BolusOnlyView.buttonRect(size[0], size[1]))) { Nav.pressBolus(); }
        return true;
    }
    function onSelect() as Lang.Boolean {
        if (Nav.isTouch()) { return false; }
        Nav.pressBolus();
        return true;
    }
    function onNextPage() as Lang.Boolean { return Nav.goNext("bolusonly"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("bolusonly"); }
}

// What more than one screen draws.
module Screens {
    // The glucose number with its trend arrow while current; "--" once hidden.
    function drawGlucose(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, font as Gfx.FontType,
                         now as Lang.Number) as Void {
        var text = Glucose.text(now);
        var color = Glucose.color(now);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        var trend = Glucose.trend(now);
        if (trend != null && !Glucose.isHidden(now)) {
            var tw = dc.getTextWidthInPixels(text, font);
            TrendArrow.draw(dc, cx + tw / 2 + 22, cy, 12, trend, color);
        }
    }

    // The bolus button: Cancel while a bolus can be cancelled, Bolus when one may start, and a disabled
    // Bolus with the reason otherwise. Read-only shows no Bolus button at all.
    function drawBolusButton(dc as Gfx.Dc, r as Lang.Array<Lang.Numeric>, now as Lang.Number,
                             font as Gfx.FontType) as Void {
        var cx = r[0] + r[2] / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var fill = Gfx.COLOR_DK_GRAY;
        var labelColor = Gfx.COLOR_LT_GRAY;
        var label = "Bolus";
        var why = null as Lang.String?;
        if (BolusFlow.canCancel()) {
            fill = Gfx.COLOR_RED;
            labelColor = Gfx.COLOR_WHITE;
            label = BolusFlow.cancelling() ? "Cancelling" : "Cancel";
        } else if (Prefs.readOnly()) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_XTINY, "Read-only", vc);
            return;
        } else {
            why = BolusFlow.startBlock(now);
            if (why == null) {
                fill = 0x5C6BE6;
                labelColor = Gfx.COLOR_WHITE;
            }
        }
        dc.setColor(fill, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(r[0], r[1], r[2], r[3], 12);
        dc.setColor(labelColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, r[1] + r[3] / 2, font, label, vc);
        var below = r[1] + r[3] + dc.getFontHeight(Gfx.FONT_XTINY) / 2 + 4;
        if (why != null) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, below, Gfx.FONT_XTINY, why, vc);
        } else if (BolusFlow.hasRequest() && !BolusFlow.canCancel()) {
            // The last request's result, until the next one.
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(cx, below, Gfx.FONT_XTINY, BolusFlow.headline(), vc);
        }
    }
}

// The trend arrow, drawn: the watch's fonts can't show the arrow glyphs.
module TrendArrow {
    function head(dc as Gfx.Dc, tx as Lang.Float, ty as Lang.Float, dx as Lang.Float, dy as Lang.Float,
                  size as Lang.Numeric) as Void {
        var hl = size * 0.6;
        var hw = size * 0.5;
        var bx = tx - dx * hl;
        var by = ty - dy * hl;
        var px = -dy;
        var py = dx;
        dc.fillPolygon([[tx, ty], [bx + px * hw, by + py * hw], [bx - px * hw, by - py * hw]]);
    }

    function draw(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, size as Lang.Numeric, token as Lang.String,
                  color as Gfx.ColorType) as Void {
        var dx = 1.0;
        var dy = 0.0;
        var twice = false;
        if (token.equals("up")) { dx = 0.0; dy = -1.0; }
        else if (token.equals("upup")) { dx = 0.0; dy = -1.0; twice = true; }
        else if (token.equals("up45")) { dx = 0.7; dy = -0.7; }
        else if (token.equals("down")) { dx = 0.0; dy = 1.0; }
        else if (token.equals("downdown")) { dx = 0.0; dy = 1.0; twice = true; }
        else if (token.equals("down45")) { dx = 0.7; dy = 0.7; }
        else if (!token.equals("flat")) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var s = size.toFloat();
        var tipx = cx.toFloat() + dx * s;
        var tipy = cy.toFloat() + dy * s;
        dc.setPenWidth(3);
        dc.drawLine(cx.toFloat() - dx * s, cy.toFloat() - dy * s, tipx, tipy);
        head(dc, tipx, tipy, dx, dy, s);
        if (twice) { head(dc, tipx - dx * s * 0.55, tipy - dy * s * 0.55, dx, dy, s); }
        dc.setPenWidth(1);
    }
}
