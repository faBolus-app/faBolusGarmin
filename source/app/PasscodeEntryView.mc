using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// C2 §2.3 (Garmin half): the 4-digit bolus passcode entry — the confirm surface shown INSTEAD of the
// tap/hold HoldView when the phone requires a passcode (AppState.bolusPasscodeRequired). §2.3: the
// passcode REPLACES the tap-sequence / two-button-hold, it does NOT stack.
//
// Two input models, chosen by device (DeviceProfile), mirroring the repo's both-input pattern
// (StaleBolusDelegate / HoldDelegate + the touch double-route guard in BolusEntryDelegate):
//   • Touch (e.g. venu3s): tap − / + to change the active digit, tap OK to commit-and-advance.
//   • Buttons: UP / DOWN change the active digit 0-9, START commits-and-advances.
//   • Either: BACK deletes the last committed digit, or cancels when none is entered.
// On the 4th committed digit the entry is complete and the delegate sends the code (via the shared
// funnel AppState.sendBolusNow) then switches to HoldView to show the delivery outcome.
//
// SECURITY (prior-art §3): the entered digits live ONLY in RAM on this view (`_entered`) for the
// lifetime of the entry — never written to Storage/Properties (which are plaintext on-device). The
// WATCH never verifies the code; it only collects it and transmits it. The PHONE is the sole authority
// and denies a wrong/absent code. clearBuffer() drops the digits on submit / cancel / hide.
class PasscodeEntryView extends Ui.View {
    public const LEN = 4;
    private var _entered as Lang.Array = [];      // committed digit values (0-9); size 0..LEN (RAM only)
    private var _current as Lang.Number = 0;      // the active (uncommitted) digit value 0..9

    function initialize() { View.initialize(); }

    // Drop the entered digits when we leave the screen (backstop to the explicit clearBuffer() on
    // submit/cancel) — no secret lingers on a backgrounded view.
    function onHide() as Void { clearBuffer(); }
    function clearBuffer() as Void { _entered = []; _current = 0; }

    // --- entry logic (mutated by the delegate; kept here so the view owns its own state) ---
    function bump(dir as Lang.Number) as Void { _current = (_current + dir + 10) % 10; }   // wrap 0-9
    // Commit the active digit and advance. Returns true when this was the 4th (final) digit — the caller
    // then reads code() and sends. Does nothing once already full.
    function commit() as Lang.Boolean {
        if (_entered.size() >= LEN) { return true; }
        _entered.add(_current);
        _current = 0;
        return _entered.size() >= LEN;
    }
    // BACK: delete the last committed digit. Returns true if one was removed (stay on screen), false if
    // there was nothing to delete (the caller then cancels — pops back to bolus entry).
    function backspace() as Lang.Boolean {
        if (_entered.size() == 0) { return false; }
        _entered = _entered.slice(0, _entered.size() - 1);
        _current = 0;
        return true;
    }
    // The entered 4-digit code as a String (called by the delegate once full, before clearBuffer()).
    function code() as Lang.String {
        var s = "";
        for (var i = 0; i < _entered.size(); i += 1) { s += (_entered[i] as Lang.Number).toString(); }
        return s;
    }

    // --- shared geometry (pixels), so touch hit-testing matches what's drawn (mirrors BolusEntryView).
    // Values chosen so the flanking − / + circles never overlap the 4 slot glyphs on a small round
    // screen; layout is subject to on-hardware validation. ---
    static function minusCenter(w, h) { return [w * 0.13, h * 0.44]; }
    static function plusCenter(w, h) { return [w * 0.87, h * 0.44]; }
    static function stepRadius(w) { return w * 0.10; }
    static function okRect(w, h) { return [w / 2 - w * 0.28, h * 0.72, w * 0.56, h * 0.15]; }
    // Center x of digit slot i (0..3), evenly spaced across the middle of the screen.
    static function slotX(i, w) { return (w / 2 + (i - 1.5) * w * 0.12).toNumber(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;
        var buttons = DeviceProfile.isButtons();

        // Title + the dose being confirmed (deliverUnits was captured before this screen was opened).
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.11, Gfx.FONT_XTINY, "Passcode", vc);
        dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.22, Gfx.FONT_SMALL, AppState.deliverUnits.format("%.2f") + " U", vc);

        // Four slots: committed → masked "*", active → the current numeral (accent + underline), the
        // rest → "_". Never shows a committed digit's value (masked); the active one must be visible so
        // the wearer can dial it in.
        var n = _entered.size();
        var slotY = h * 0.44;
        for (var i = 0; i < LEN; i += 1) {
            var x = slotX(i, w);
            var ch; var col;
            if (i < n) { ch = "*"; col = Gfx.COLOR_WHITE; }
            else if (i == n) { ch = _current.toString(); col = 0x8AB4FF; }
            else { ch = "_"; col = Gfx.COLOR_DK_GRAY; }
            dc.setColor(col, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, slotY, Gfx.FONT_NUMBER_MEDIUM, ch, vc);
            if (i == n && n < LEN) {   // underline the active slot
                dc.setColor(0x8AB4FF, Gfx.COLOR_TRANSPARENT);
                dc.fillRectangle(x - w * 0.04, slotY + h * 0.10, w * 0.08, 2);
            }
        }

        // − / + change the active digit. On buttons these label the physical keys (UP/DOWN); on touch
        // they are the tappable controls.
        var mc = minusCenter(w, h), pc = plusCenter(w, h), r = stepRadius(w);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(mc[0], mc[1], r);
        dc.setColor(0x333333, Gfx.COLOR_TRANSPARENT); dc.fillCircle(pc[0], pc[1], r);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(mc[0], mc[1], Gfx.FONT_MEDIUM, "-", vc);
        dc.drawText(pc[0], pc[1], Gfx.FONT_MEDIUM, "+", vc);

        // OK = commit the active digit and advance (touch: tappable; buttons: labels START).
        var ok = okRect(w, h);
        dc.setColor(0x5C6BE6, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(ok[0], ok[1], ok[2], ok[3], 10);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, ok[1] + ok[3] / 2, Gfx.FONT_SMALL, buttons ? "Next (START)" : "Next", vc);

        // Bottom hint (device-appropriate).
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY,
                    buttons ? "UP/DOWN digit · BACK del" : "BACK deletes", vc);
    }
}
