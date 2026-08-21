using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// C2 §2.3 (Garmin half): the one-time, plain-language notice shown the FIRST time a bolus passcode is
// actually required. It explains that a 4-digit passcode set in faBolus on the phone now confirms a
// bolus — replacing the tap/hold. Purely informational: any confirm gesture continues to the passcode
// entry (PasscodeIntroDelegate), BACK returns to the launching screen. Shown exactly once (AppState
// persists the "shown" flag at display time, before this view is pushed — see Nav.openConfirm).
//
// The C2 plan's "prompt at pairing time" has NO on-watch equivalent — pairing is done phone-side on
// Garmin — so this first-use notice is the correct on-watch stand-in for that pairing-time explanation.
//
// Layout mirrors BolusIntroView: a title, a body pre-wrapped into short centered lines that fit the
// round screen on any declared device (venu3s and smaller), and a bottom hint.
class PasscodeIntroView extends Ui.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // Title.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Gfx.FONT_XTINY, "Bolus passcode", vc);

        // Body: short pre-wrapped lines (never clip the round edges), kept in the central band.
        var lines = [
            "Enter the 4-digit",
            "passcode set in",
            "faBolus on your",
            "phone to confirm",
            "a bolus."
        ];
        var top = 0.30, bottom = 0.70;
        var step = (bottom - top) / (lines.size() - 1);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(cx, h * (top + step * i), Gfx.FONT_XTINY, lines[i], vc);
        }

        // Continue hint (device-appropriate verb).
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.88, Gfx.FONT_XTINY,
                    DeviceProfile.isButtons() ? "START to continue" : "tap to continue", vc);
    }
}
