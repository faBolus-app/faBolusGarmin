using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.System;
using Toybox.Math;

// Bolus entry input, portable across devices:
//   • Touch (venu3s): onTap hit-tests the drawn controls (− / + / mode chip / Deliver).
//   • Buttons: UP / DOWN adjust the amount directly, MENU toggles Units/Carbs, START delivers —
//     button-native, no on-screen focus cursor.
class BolusEntryDelegate extends Ui.BehaviorDelegate {
    private var _view as BolusEntryView;
    function initialize(view as BolusEntryView) { BehaviorDelegate.initialize(); _view = view; }

    private function inRect(c, r) {
        return c[0] >= r[0] && c[0] <= r[0] + r[2] && c[1] >= r[1] && c[1] <= r[1] + r[3];
    }
    private function nearCircle(c, center, radius) {
        var dx = c[0] - center[0], dy = c[1] - center[1];
        return Math.sqrt(dx * dx + dy * dy) <= radius * 1.3;   // a little forgiving
    }

    // Touch: map the tapped coordinates to a control.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean {
        var c = evt.getCoordinates();
        var s = System.getDeviceSettings();
        var w = s.screenWidth, h = s.screenHeight;
        if (nearCircle(c, BolusEntryView.minusCenter(w, h), BolusEntryView.stepRadius(w))) { AppState.adjust(-1); Ui.requestUpdate(); return true; }
        if (nearCircle(c, BolusEntryView.plusCenter(w, h), BolusEntryView.stepRadius(w))) { AppState.adjust(1); Ui.requestUpdate(); return true; }
        if (inRect(c, BolusEntryView.chipRect(w, h))) { AppState.toggleMode(); Ui.requestUpdate(); return true; }
        if (inRect(c, BolusEntryView.deliverRect(w, h))) { return deliver(); }
        return true;
    }

    // Buttons: UP = increase, DOWN = decrease, MENU = switch mode, START = deliver.
    // Gated to button devices — on a touchscreen a tap is ALSO delivered as onSelect/next-page
    // behaviors, which would otherwise hijack every tap. Returning false lets touch fall through to
    // onTap (the validated touch path).
    function onPreviousPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.adjust(1); Ui.requestUpdate(); return true; }   // UP
    function onNextPage() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.adjust(-1); Ui.requestUpdate(); return true; }       // DOWN
    function onMenu() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } AppState.toggleMode(); Ui.requestUpdate(); return true; }
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return deliver(); }

    private function deliver() as Lang.Boolean {
        // FB-01: never deliver a carb bolus when the calculator inputs haven't synced from the phone —
        // the wrist would otherwise dose off an unverified assumption. Block + tell the user.
        if (!AppState.carbCalcAvailable()) {
            AppState.message = "Calculator unavailable — open faBolus on the phone.";
            Ui.requestUpdate();
            return true;
        }
        // AB4 (Addendum B): if the CGM reading is stale at compose, warn with the three-way choice BEFORE
        // composing the dose — include the stale reading, bolus for carbs only, or cancel. A fresh reading
        // (or none) composes straight through. Only carbs mode has a correction term, so units mode (a
        // fixed manual dose, no BG) bypasses the prompt entirely. Mirrors faBolusCore StaleBolusPrompt.
        if (AppState.mode.equals("carbs") && AppState.staleBolusShouldWarn()) {
            var sv = new StaleBolusView();
            Ui.pushView(sv, new StaleBolusDelegate(sv), Ui.SLIDE_LEFT);
            return true;
        }
        if (!captureDose()) { return true; }   // nothing to deliver
        // C2 §2.3: open the confirm surface. When the phone requires a passcode, Nav pushes the passcode
        // entry (with a one-time notice the first time) INSTEAD of the tap/hold HoldView — §2.3: the
        // passcode REPLACES the tap/hold, it does not stack. PUSH here (fresh path) as today.
        Nav.openConfirm(false);
        return true;
    }

    // Capture the dose to deliver from the current compose state (honoring whatever stale-BG choice is in
    // effect via AppState.includeStaleBg). Returns false when there's nothing to deliver (< 0.05 U) so the
    // caller leaves the compose screen up. Shared by the fresh path and the AB4 three-way choice.
    static function captureDose() as Lang.Boolean {
        AppState.deliverUnits = AppState.computeUnits();
        // VA-07: snapshot the current eligibility generation as we arm this dose. A later statusRead that
        // changes the eligibility fingerprint bumps AppState.bolusEligibilityGen past this snapshot, which
        // tears the armed confirm down (mustTeardownArmedBolus) / refuses the send (sendBolusNow).
        AppState.armBolus();
        return AppState.deliverUnits >= 0.05;
    }
}
