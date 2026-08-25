using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Minimal app entry used ONLY by unit-test builds (test.jungle / manifest-test.xml). The real
// app (FaBolusApp) starts background services + repeating timers, which prevent the unit-test
// harness from starting/exiting cleanly in the simulator. This entry does nothing so the tests
// run and the process terminates.
class TestEntryApp extends Application.AppBase {
    // Runs once when the test app boots, before any (:test) runs. Suppress the physical Comm.transmit()
    // for the whole suite so the simulator's "no data connection / connect an Android device to ADB" modal
    // never pops for the many sends the tests drive (pollTick, sendBolus, cancel) — see RemoteComm.mc's
    // testSuppressTransmit note. Dispatch semantics the tests assert on are unchanged.
    function initialize() { AppBase.initialize(); RemoteComm.testSuppressTransmit = true; }
    function onStart(state as Lang.Dictionary or Null) as Void {}
    function onStop(state as Lang.Dictionary or Null) as Void {}
    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new TestEntryView() ];
    }
}

class TestEntryView extends WatchUi.View {
    function initialize() { View.initialize(); }
}
