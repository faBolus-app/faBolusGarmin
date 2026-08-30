using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Input for UnresolvedSendView — the disclosure shown when a durable unresolved-send tombstone has locked
// the bolus affordance.
//
// Every input does the SAME thing: leave. This screen is read-only by design (see UnresolvedSendView's
// own comment): it carries no unlock control, because the watch cannot know whether the earlier dose was
// delivered and releasing the lock is the phone's act. There is therefore no destructive choice to guard,
// no cursor, and no confirm — which is also why it needs no deliberate-input model of its own.
//
// Mirrors the touch/button split the rest of the app uses (StaleBolusDelegate / HoldDelegate): on a touch
// device a tap also arrives as onSelect/next-page, so those return false there and fall through to onTap.
class UnresolvedSendDelegate extends Ui.BehaviorDelegate {

    function initialize() { BehaviorDelegate.initialize(); }

    private function leave() as Lang.Boolean {
        Ui.popView(Ui.SLIDE_RIGHT);
        return true;
    }

    // Touch: a tap anywhere dismisses. No hit-testing — there is nothing here to hit wrongly.
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return leave(); }

    function onBack() as Lang.Boolean { return leave(); }

    function onSelect() as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        return leave();
    }

    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        if (DeviceProfile.isTouch()) { return false; }
        var k = evt.getKey();
        if (k == Ui.KEY_ENTER || k == Ui.KEY_START || k == Ui.KEY_ESC) { return leave(); }
        return false;
    }
}
