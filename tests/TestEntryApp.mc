using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

// The unit tests' entry: no timers, no background registration, and no real transmits (the simulator has
// no phone, and a transmit there opens a dialog).
(:background)
class TestEntryApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {}
    function onStop(state as Lang.Dictionary?) as Void {}

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new TestEntryView()];
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new FaBolusGlanceView()];
    }
}

(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
class TestEntryView extends WatchUi.View {
    function initialize() { View.initialize(); }
}
