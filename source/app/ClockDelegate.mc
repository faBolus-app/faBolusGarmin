using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Clock screen input: swipe moves between screens in the configured order. The analog-vs-digital clock
// style is DISPLAY-ONLY, driven by the phone's `clockAnalog` setting (P15 E4b) — there is no longer an
// on-watch tap/SELECT toggle. Kept as its own delegate so the screen still joins the swipe carousel.
class ClockDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onNextPage() as Lang.Boolean { return Nav.goNext("clock"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("clock"); }
}
