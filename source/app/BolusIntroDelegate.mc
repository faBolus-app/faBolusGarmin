using Toybox.WatchUi as Ui;
using Toybox.Lang;

// G5 (Garmin half): input for the one-time bolus-enable notice (BolusIntroView). Any confirm gesture
// continues to bolus entry; BACK falls through to the default pop, returning to the launching screen.
// The "shown" flag was already persisted at display time (Nav.openBolusEntry), so either exit — continue
// or back out — leaves the notice permanently dismissed; it is informational, never a gate.
class BolusIntroDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    // Touch: a tap anywhere continues. Buttons: SELECT / START continue. Mirrors the touch/button
    // double-route guard used elsewhere (MainDelegate/BolusOnlyDelegate) — on a touch device a tap is
    // ALSO delivered as onSelect/onKey, so those return false there and fall through to onTap.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return go(); }
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return go(); }
    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return go(); }
        return false;
    }

    private function go() as Lang.Boolean { Nav.continueToBolusEntry(); return true; }
}
