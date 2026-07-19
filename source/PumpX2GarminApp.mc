using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

// App entry point for the standalone direct-to-pump PumpX2Garmin watch app.
// For now this is a placeholder shell; the BLE client, protocol, and UI are layered on top
// as the milestones land. The protocol/auth foundation lives under source/protocol and
// source/auth and is exercised by the unit tests in tests/.
class PumpX2GarminApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary or Null) as Void {
    }

    function onStop(state as Lang.Dictionary or Null) as Void {
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new PlaceholderView() ];
    }
}

// Minimal placeholder view until the ported UI (Milestone 6) is wired in.
class PlaceholderView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Toybox.Graphics.Dc) as Void {
        dc.setColor(Toybox.Graphics.COLOR_WHITE, Toybox.Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2,
            Toybox.Graphics.FONT_MEDIUM, "PumpX2Garmin",
            Toybox.Graphics.TEXT_JUSTIFY_CENTER | Toybox.Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
