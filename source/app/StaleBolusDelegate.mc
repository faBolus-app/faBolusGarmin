using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Lang;

// AB4 (Addendum B): input for the three-way stale-CGM choice (StaleBolusView). Two portable models:
//   • Touch: tap a row → that choice.
//   • Buttons: UP/DOWN move the cursor, START selects; BACK = cancel.
// The chosen path sets the per-attempt include flag and either composes the dose (replacing this prompt
// with the hold-to-confirm) or, for cancel, backs out sending NOTHING. Semantics live in pure AppState
// predicates (staleChoiceProceeds / staleChoiceIncludesBg) so they mirror faBolusCore StaleBolusPrompt
// and stay unit-testable. Confirm idiom matches HoldDelegate/BolusEntryDelegate (touch double-route guard).
class StaleBolusDelegate extends Ui.BehaviorDelegate {
    private var _view as StaleBolusView;
    function initialize(view as StaleBolusView) { BehaviorDelegate.initialize(); _view = view; }

    private function inRect(c, r) {
        return c[0] >= r[0] && c[0] <= r[0] + r[2] && c[1] >= r[1] && c[1] <= r[1] + r[3];
    }

    // Touch: tap a row → that choice.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        for (var i = 0; i < 3; i += 1) {
            if (inRect(c, StaleBolusView.rowRect(i, w, h))) { return choose(i); }
        }
        return true;
    }

    // Buttons: UP/DOWN move the cursor, START selects. On a touch device a tap is ALSO delivered as
    // onSelect / next-page, so those return false there and fall through to the validated onTap path.
    function onPreviousPage() as Lang.Boolean {   // UP
        if (DeviceProfile.isTouch()) { return false; }
        _view.cursor = (_view.cursor + 2) % 3; Ui.requestUpdate(); return true;
    }
    function onNextPage() as Lang.Boolean {       // DOWN
        if (DeviceProfile.isTouch()) { return false; }
        _view.cursor = (_view.cursor + 1) % 3; Ui.requestUpdate(); return true;
    }
    function onSelect() as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        return choose(_view.cursor);
    }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return choose(_view.cursor); }
        return false;
    }

    // BACK is the same as Cancel — a pure UI back-out that sends nothing.
    function onBack() as Lang.Boolean { return choose(AppState.STALE_CANCEL); }

    // Apply the chosen path. Cancel composes/sends NOTHING (pure back-out to the compose screen). The two
    // proceeding paths set the per-attempt include flag (insulin-INCREASING only for "include"; never
    // sticky) and then compose + REPLACE this prompt with the confirm surface via Nav.openConfirm (the
    // tap/hold HoldView, or the C2 §2.3 passcode entry when the phone requires one) — so a later BACK from
    // the confirm returns to the compose screen, not back to this dismissed prompt.
    private function choose(opt as Lang.Number) as Lang.Boolean {
        if (!AppState.staleChoiceProceeds(opt)) {   // cancel
            AppState.includeStaleBg = false;        // never leave the flag set on a back-out
            Ui.popView(Ui.SLIDE_RIGHT);             // back to BolusEntryView; NOTHING sent
            return true;
        }
        AppState.includeStaleBg = AppState.staleChoiceIncludesBg(opt);
        if (!BolusEntryDelegate.captureDose()) {    // nothing to deliver → back to entry
            AppState.includeStaleBg = false;
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        // C2 §2.3: REPLACE this stale prompt with the confirm surface (switchToView) — the passcode entry
        // when the phone requires one (§2.3: it replaces the tap/hold, doesn't stack), else HoldView. A
        // later BACK from the confirm returns to the compose screen, not this dismissed prompt.
        Nav.openConfirm(true);
        return true;
    }
}
