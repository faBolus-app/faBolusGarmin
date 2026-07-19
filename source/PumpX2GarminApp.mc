using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// App entry point for the standalone direct-to-pump PumpX2Garmin watch app.
//
// Currently boots the Gate A smoke test (BLE scan -> bond -> subscribe -> one CURRENT_STATUS
// notification), the first GO/NO-GO gate. The protocol/auth foundation under source/protocol and
// source/auth is byte-exact vs the oracle (see tests/). The full UI (Milestone 6) is layered on
// once the gates pass. Bench PoC only (saline).
class PumpX2GarminApp extends Application.AppBase {
    private var _gateA as GateAController or Null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary or Null) as Void {
        _gateA = new GateAController();
        _gateA.start();
    }

    function onStop(state as Lang.Dictionary or Null) as Void {
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        if (_gateA == null) {
            _gateA = new GateAController();
        }
        return [ new GateAView(_gateA) ];
    }
}
