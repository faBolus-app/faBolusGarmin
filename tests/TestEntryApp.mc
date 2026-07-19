using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Minimal app entry used ONLY by unit-test builds (test.jungle / manifest-test.xml). The real
// app (ControlX2App) starts background services + repeating timers, which prevent the unit-test
// harness from starting/exiting cleanly in the simulator. This entry does nothing so the tests
// run and the process terminates.
class TestEntryApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function onStart(state as Lang.Dictionary or Null) as Void {}
    function onStop(state as Lang.Dictionary or Null) as Void {}
    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new TestEntryView() ];
    }
}

class TestEntryView extends WatchUi.View {
    function initialize() { View.initialize(); }
}
