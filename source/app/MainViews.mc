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
        var bw = w * 0.58;
        var bh = h * 0.15;
        return [w / 2 - bw / 2, h * 0.705, bw, bh];
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

        Screens.drawGlucose(dc, cx, h * 0.31, Gfx.FONT_NUMBER_HOT, now);
        // The unit is part of the reading, so it sits close under the number, dim; the reading's age is a
        // status, so it gets a chip of its own, orange once the reading is stale.
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.475, Gfx.FONT_XTINY, Display.glucoseUnit(Prefs.glucoseUnit()), vc);
        if (!Glucose.isHidden(now)) { Screens.drawAgeChip(dc, cx, h * 0.595, now); }
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
        var trend = Glucose.isHidden(now) ? null : Glucose.trend(now);
        // The number and its arrow are centred together.
        var size = dc.getFontHeight(font) / 7;
        var gap = size;
        var aw = (trend != null) ? TrendArrow.width(trend, size) : 0;
        var tw = dc.getTextWidthInPixels(text, font);
        var left = cx - (tw + ((aw > 0) ? gap + aw : 0)) / 2;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(left + tw / 2, cy, font, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        if (trend != null && aw > 0) { TrendArrow.draw(dc, left + tw + gap + aw / 2, cy, size, trend, color); }
    }

    // The reading's age in a small dark chip: light text while current, orange once stale.
    function drawAgeChip(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, now as Lang.Number) as Void {
        var text = Display.ago(Glucose.age(now));
        if (text.length() == 0) { return; }
        var stale = Glucose.stale(now);
        var tw = dc.getTextWidthInPixels(text, Gfx.FONT_XTINY);
        var th = dc.getFontHeight(Gfx.FONT_XTINY);
        var pad = th / 2;
        dc.setColor(stale ? 0x3A2200 : 0x262626, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - tw / 2 - pad, cy - th / 2 - 1, tw + pad * 2, th + 2, (th + 2) / 2);
        dc.setColor(stale ? Gfx.COLOR_ORANGE : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_XTINY, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // The bolus button: Cancel while a bolus can be cancelled, Bolus when one may start, and otherwise a
    // disabled button that says why (below it, the round screen has no room for a reason). Read-only shows
    // no Bolus button at all.
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
        // A reason takes two lines of the smallest font, so a blocked button grows to hold them.
        var lines = dc.getFontHeight(Gfx.FONT_XTINY) * 2;
        var bh = (why != null && lines + 12 > r[3]) ? lines + 12 : r[3];
        var top = r[1] + r[3] / 2 - bh / 2;
        dc.setColor(fill, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(r[0], top, r[2], bh, 12);
        dc.setColor(labelColor, Gfx.COLOR_TRANSPARENT);
        if (why != null) {
            dc.drawText(cx, r[1] + r[3] / 2, Gfx.FONT_XTINY,
                        Gfx.fitTextToArea(why, Gfx.FONT_XTINY, r[2] * 0.90, lines + 6, true), vc);
        } else {
            dc.drawText(cx, r[1] + r[3] / 2, font, label, vc);
        }
    }
}

// The trend arrow, drawn: the watch's fonts can't show the arrow glyphs. The glance draws it too.
(:glance)
module TrendArrow {
    // The arrow's direction for a trend token, and whether it's doubled; null for an unknown token.
    function direction(token as Lang.String) as [Lang.Float, Lang.Float, Lang.Boolean]? {
        if (token.equals("flat")) { return [1.0, 0.0, false]; }
        if (token.equals("up")) { return [0.0, -1.0, false]; }
        if (token.equals("upup")) { return [0.0, -1.0, true]; }
        if (token.equals("up45")) { return [0.7071, -0.7071, false]; }
        if (token.equals("down")) { return [0.0, 1.0, false]; }
        if (token.equals("downdown")) { return [0.0, 1.0, true]; }
        if (token.equals("down45")) { return [0.7071, 0.7071, false]; }
        return null;
    }

    // How wide the arrow drawn at `size` is, for centering it with the number.
    function width(token as Lang.String, size as Lang.Numeric) as Lang.Number {
        var d = direction(token);
        if (d == null) { return 0; }
        return (size * ((d[2] as Lang.Boolean) ? 3.2 : 2.0)).toNumber();
    }

    // One arrow centred on (cx, cy): a shaft ending at the head's base, so the head's point is its end.
    function one(dc as Gfx.Dc, cx as Lang.Float, cy as Lang.Float, dx as Lang.Float, dy as Lang.Float, s as Lang.Float)
        as Void {
        var hl = s * 0.85;
        var hw = s * 0.62;
        var tipx = cx + dx * s;
        var tipy = cy + dy * s;
        var bx = tipx - dx * hl;
        var by = tipy - dy * hl;
        var px = -dy;
        var py = dx;
        // The shaft is a filled bar, so its tail is cut square to the arrow in every direction (a thick
        // line's end isn't, on a diagonal).
        var half = s * 0.16;
        var tx = cx - dx * s;
        var ty = cy - dy * s;
        var ex = bx + dx * 2;
        var ey = by + dy * 2;
        dc.fillPolygon([[tx + px * half, ty + py * half], [ex + px * half, ey + py * half],
                        [ex - px * half, ey - py * half], [tx - px * half, ty - py * half]]);
        dc.fillPolygon([[tipx, tipy], [bx + px * hw, by + py * hw], [bx - px * hw, by - py * hw]]);
    }

    // Centred on (cx, cy). A doubled arrow is two arrows side by side.
    function draw(dc as Gfx.Dc, cx as Lang.Numeric, cy as Lang.Numeric, size as Lang.Numeric, token as Lang.String,
                  color as Gfx.ColorType) as Void {
        var d = direction(token);
        if (d == null) { return; }
        var dx = d[0] as Lang.Float;
        var dy = d[1] as Lang.Float;
        var s = size.toFloat();
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        if (d[2] as Lang.Boolean) {
            one(dc, cx.toFloat() - s * 0.6, cy.toFloat(), dx, dy, s);
            one(dc, cx.toFloat() + s * 0.6, cy.toFloat(), dx, dy, s);
        } else {
            one(dc, cx.toFloat(), cy.toFloat(), dx, dy, s);
        }
    }
}
