using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// The watch-side DISCLOSURE for a durable unresolved-send tombstone — a NON-BLOCKING interstitial.
//
// Why this screen exists: a tombstone records that a prior dispatch's outcome is unconfirmed. The
// tombstone no longer disables the Bolus button (canBolus()/reattemptBlocked() ignore it); instead this
// screen is shown at bolus-entry open (Nav.openBolusEntry) so the wearer sees the honest "verify on the
// pump" disclosure at the exact moment a re-dose-into-unknown decision is made. A confirm gesture
// continues to entry, BACK returns to the launching screen (UnresolvedSendDelegate). A short
// "Earlier dose unresolved" marker also shows alongside the enabled button (MainView/BolusOnlyView);
// this screen carries the full explanation, because a marker cannot honestly say faBolus does not know
// whether insulin went in.
//
// It is DELIBERATELY read-only: there is no unlock control here, and adding one would be wrong, not
// merely out of scope. The watch cannot know whether the dose was delivered; the phone owns the pump
// link, the reconciliation ledger and the history the wearer must actually consult. Clearing the
// tombstone is therefore the phone's act — an authoritatively-resolved bolusStatus echo for the matching
// requestId resolves the DOSE. Nothing on this screen can auto-clear anything.
//
// All copy comes from the pure AppState.unresolvedSendDisclosure() so its honesty properties — never
// claims delivered, never claims NOT delivered, points at the pump's own history, and fits the row
// budget — are asserted in tests/UnresolvedSendLockTest.mc instead of being eyeballed here.
class UnresolvedSendView extends Ui.View {

    function initialize() { View.initialize(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        // Caution, not alarm: nothing is wrong with the pump and no dose is in flight — an earlier one
        // simply never got confirmed. Yellow matches the "unknown" outcome colour HoldView already uses
        // for exactly this ambiguous case, so the two surfaces read as the same situation.
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.09, Gfx.FONT_XTINY, "Earlier dose", vc);

        // Reuses DetailsView.rowY (already pinned by tests/DetailsRowYTest.mc) rather than re-deriving
        // row spacing, and stays inside the central band so the round edges never clip the text.
        var lines = AppState.unresolvedSendDisclosure();
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(cx, h * DetailsView.rowY(lines.size(), i, 0.24, 0.74),
                        Gfx.FONT_XTINY, lines[i], vc);
        }

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.90, Gfx.FONT_XTINY,
                    DeviceProfile.isButtons() ? "START to continue" : "tap to continue", vc);
    }
}
