using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Screen carousel for the faBolus remote. The swipe order and the first screen are configurable
// (from phone settings, held in AppState.screenOrder / AppState.defaultScreen). Instead of a fixed
// push/pop stack, screens are swapped with switchToView() so any order works and the default
// screen is simply the initial view. The bolus screen is a modal push on top (not in this order),
// so popView() from bolus returns to whatever screen launched it.
module Nav {
    // [View, Delegate] for a screen id. Falls back to the glance for an unknown id.
    function viewFor(id as Lang.String) as Lang.Array {
        if (id.equals("alerts"))  { return [new AlertsListView(), new AlertsListDelegate()]; }
        if (id.equals("history")) { return [new CgmView(), new CgmDelegate()]; }
        if (id.equals("details")) { return [new DetailsView(), new DetailsDelegate()]; }
        // CGM-only glance: same current-glucose screen, no bolus button (user's choice, via screen order).
        if (id.equals("glucose")) { return [new MainView(false), new MainDelegate(false, "glucose")]; }
        // Clock (analog/digital, tap-to-toggle) + glucose, no bolus button.
        if (id.equals("clock")) { return [new ClockView(), new ClockDelegate()]; }
        // Just the bolus button, nothing else.
        if (id.equals("bolusonly")) { return [new BolusOnlyView(), new BolusOnlyDelegate()]; }
        return [new MainView(true), new MainDelegate(true, "glance")];
    }

    // The first screen shown at launch.
    function initialView() as Lang.Array {
        return viewFor(AppState.defaultScreen);
    }

    // Open the bolus compose flow (a modal push on top of whatever screen launched it). Both bolus
    // entry points (the glance button and the bolus-only screen) route through here so the reset + the
    // G5 one-time notice live in ONE place.
    //
    // G5 (Garmin half): the FIRST time bolusing is used, show a one-time plain-language notice that
    // bolusing from the watch is off by default and is turned on/off from faBolus on the phone. The
    // flag is persisted (AppState.markBolusIntroShown) at DISPLAY time, so it shows exactly once even
    // if the wearer backs out of it. Thereafter this opens bolus entry directly.
    function openBolusEntry() as Void {
        AppState.reset();
        if (!AppState.bolusIntroShown()) {
            AppState.markBolusIntroShown();
            Ui.pushView(new BolusIntroView(), new BolusIntroDelegate(), Ui.SLIDE_LEFT);
            return;
        }
        pushBolusEntry();
    }

    // Push the bolus-entry screen on top of the launching screen (glance / bolus-only). A later
    // popView from entry returns to that launching screen. Used on the direct path (notice already
    // shown) and, indirectly, as the shape of the G5 continue below.
    function pushBolusEntry() as Void {
        var v = new BolusEntryView();
        Ui.pushView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
    }

    // Continue past the G5 one-time notice: REPLACE the notice with bolus entry (switchToView, not
    // push). The notice was pushed on top of the launching screen, so swapping it out here means a
    // later BACK/popView from entry returns to the launching screen — not back to the dismissed notice.
    function continueToBolusEntry() as Void {
        var v = new BolusEntryView();
        Ui.switchToView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
    }

    // C2 §2.3: open the CONFIRM surface for a composed dose. Both bolus push sites route through here so
    // the passcode branch + the first-use notice live in ONE place:
    //   • BolusEntryDelegate (fresh path)  → openConfirm(false): PUSH on top of bolus entry (as today).
    //   • StaleBolusDelegate (stale path)  → openConfirm(true):  REPLACE the stale prompt (switchToView).
    // `replace` preserves each site's existing stack semantics; both converge to the same final stack.
    //
    // §2.3: when the phone requires a passcode (AppState.bolusPasscodeRequired) the passcode entry
    // REPLACES the tap/hold confirm — it does NOT stack — and the FIRST time a passcode is required a
    // one-time notice is shown first (flag persisted at DISPLAY time → shows exactly once). Otherwise the
    // HoldView tap/hold confirm exactly as before. Both surfaces funnel their send through the identical
    // AppState.sendBolusNow(), so delivery semantics never diverge.
    function openConfirm(replace as Lang.Boolean) as Void {
        if (AppState.bolusPasscodeRequired) {
            if (!AppState.passcodeIntroShown()) {
                AppState.markPasscodeIntroShown();
                openConfirmView(new PasscodeIntroView(), new PasscodeIntroDelegate(), replace);
                return;
            }
            var pv = new PasscodeEntryView();
            openConfirmView(pv, new PasscodeEntryDelegate(pv), replace);
            return;
        }
        var hv = new HoldView();
        openConfirmView(hv, new HoldDelegate(hv), replace);
    }

    // Push vs switch, preserving the caller's stack semantics (SLIDE_LEFT like both original push sites).
    function openConfirmView(view as Ui.Views, delegate as Ui.InputDelegates, replace as Lang.Boolean) as Void {
        if (replace) { Ui.switchToView(view, delegate, Ui.SLIDE_LEFT); }
        else { Ui.pushView(view, delegate, Ui.SLIDE_LEFT); }
    }

    // Continue past the C2 one-time passcode notice: REPLACE it with passcode entry (switchToView, not
    // push), so a later BACK/popView from entry returns to the launching screen — not the dismissed
    // notice. Mirrors continueToBolusEntry().
    function continueToPasscodeEntry() as Void {
        var pv = new PasscodeEntryView();
        Ui.switchToView(pv, new PasscodeEntryDelegate(pv), Ui.SLIDE_LEFT);
    }

    function indexOf(id as Lang.String) as Lang.Number {
        var order = AppState.screenOrder;
        for (var i = 0; i < order.size(); i += 1) {
            if ((order[i] as Lang.String).equals(id)) { return i; }
        }
        return -1;
    }

    // Swipe up → next screen in the order (clamped at the last screen).
    function goNext(currentId as Lang.String) as Lang.Boolean {
        var order = AppState.screenOrder;
        var i = indexOf(currentId);
        if (i < 0 || i + 1 >= order.size()) { return true; }   // at the end: swallow, no move
        var vd = viewFor(order[i + 1] as Lang.String);
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_UP);
        return true;
    }

    // Swipe down → previous screen in the order (clamped at the first screen).
    function goPrev(currentId as Lang.String) as Lang.Boolean {
        var order = AppState.screenOrder;
        var i = indexOf(currentId);
        if (i <= 0) { return true; }                            // at the start: swallow, no move
        var vd = viewFor(order[i - 1] as Lang.String);
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_DOWN);
        return true;
    }
}
