using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// Standalone entry for the direct-CGM probe build (direct-cgm.jungle / manifest-directcgm.xml).
// Compile-verified only; needs an on-device test with a live G7 (see DIRECT_CGM_STATUS.md).
class CgmProbeApp extends Application.AppBase {
    private var _client as DirectCgm.G7BleClient or Null = null;
    public var lastGlucose as Lang.Number or Null = null;
    public var lastTrend as Lang.String = "flat";

    function initialize() { AppBase.initialize(); }

    function onStart(state as Lang.Dictionary or Null) as Void {
        _client = new DirectCgm.G7BleClient();
        _client.onGlucose = method(:onGlucose);
        _client.start();
    }

    function onStop(state as Lang.Dictionary or Null) as Void {}

    function onGlucose(m as Lang.Dictionary) as Void {
        lastGlucose = m[:glucose];
        lastTrend = m[:trendToken];
        WatchUi.requestUpdate();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        if (_client == null) { _client = new DirectCgm.G7BleClient(); }
        return [new CgmProbeView(self)];
    }
}
