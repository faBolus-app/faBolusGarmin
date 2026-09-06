using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Input for UnresolvedSendView — the NON-BLOCKING disclosure shown at bolus-entry open when a durable
// unresolved-send tombstone is outstanding (see Nav.openBolusEntry).
//
// The tombstone no longer locks the bolus affordance: the watch discloses an unconfirmed prior dose
// rather than walling off a new one. So this screen is an interstitial, not a dead-end. A confirm gesture
// CONTINUES to bolus entry (the wearer has read the "verify on the pump" disclosure and chosen to dose
// anyway); BACK returns to the launching screen (they chose not to). It carries no unlock control — the
// watch cannot know whether the earlier dose was delivered, and clearing the tombstone is the phone's act.
//
// Mirrors BolusIntroDelegate (the G5 one-time notice): the reset already ran in Nav.openBolusEntry before
// this was pushed, and continueToBolusEntry() REPLACES this notice with entry (switchToView) so a later
// BACK from entry returns to the launching screen, not to the dismissed disclosure. On a touch device a
// tap also arrives as onSelect/onKey, so those return false there and fall through to onTap.
class UnresolvedSendDelegate extends Ui.BehaviorDelegate {

    function initialize() { BehaviorDelegate.initialize(); }

    private function go() as Lang.Boolean { Nav.continueToBolusEntry(); return true; }

    // Touch: a tap anywhere continues past the disclosure to bolus entry.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return go(); }

    // BACK cancels: return to the launching screen without composing a new dose.
    function onBack() as Lang.Boolean { Ui.popView(Ui.SLIDE_RIGHT); return true; }

    function onSelect() as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        return go();
    }

    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START) { return go(); }
        if (k == Ui.KEY_ESC) { Ui.popView(Ui.SLIDE_RIGHT); return true; }
        return false;
    }
}
