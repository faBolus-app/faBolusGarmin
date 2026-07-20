using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Entry point for the Milestone 0 handoff-resume probe build (probe.jungle / manifest-probe.xml).
// Standalone from the main app so it can be sideloaded on its own for the test.
class ProbeApp extends Application.AppBase {
    private var _probe as ProbeController or Null;

    function initialize() { AppBase.initialize(); }

    function onStart(state as Lang.Dictionary or Null) as Void {
        _probe = new ProbeController();
        _probe.start();
    }

    function onStop(state as Lang.Dictionary or Null) as Void {}

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        if (_probe == null) { _probe = new ProbeController(); }
        return [ new ProbeView(_probe) ];
    }
}
