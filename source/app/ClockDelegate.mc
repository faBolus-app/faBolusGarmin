using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;
using Toybox.Lang;

// Clock screen input: tap (or SELECT) toggles the clock style analog <-> digital (persisted); swipe
// moves between screens in the configured order.
class ClockDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    private function toggleStyle() as Lang.Boolean {
        var v = Storage.getValue("clockAnalog");
        Storage.setValue("clockAnalog", (v == null) ? true : !(v as Lang.Boolean));
        Ui.requestUpdate();
        return true;
    }

    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return toggleStyle(); }
    // GA-06: a touch tap fires onTap AND onSelect; suppress the button handler on touch so a tap can't
    // toggle twice (which would cancel itself out). Physical-button devices keep SELECT → toggle.
    function onSelect() as Lang.Boolean { if (DeviceProfile.isTouch()) { return false; } return toggleStyle(); }

    function onNextPage() as Lang.Boolean { return Nav.goNext("clock"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("clock"); }
}
