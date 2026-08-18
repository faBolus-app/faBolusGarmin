using Toybox.ActivityMonitor;
using Toybox.Communications as Comm;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// Ambient heart-rate relay → piggybacks the newest AMBIENT HR sample onto the phone on the EXISTING
// status cadence (co-scheduled with FaBolusApp.requestStatus — no new timer / radio wake). Chart context
// only; HR rides an out-of-band `hr_window` envelope the phone's GarminRemoteBridge parses BEFORE
// RemoteCommand, so HR is NEVER a signed dose input.
//
// BATTERY-SAFE (D-08): reads ONLY the HR history the watch already samples 24/7 for its own tracking
// (`ActivityMonitor.getHeartRateHistory`). It MUST NOT enable real-time optical-sensor streaming
// (`Sensor.setEnabledSensors` / `Sensor.enableSensorType` / `Sensor.enableSensorEvents`) — ambient
// history only, so net marginal battery cost is negligible.
//
// PHONE-GATED (D-09, mirrors EatingRelay): reads AND sends ONLY while the phone's `hr_ctl` toggle is on.
// When off, emitIfDue() returns before any read or transmit → zero incremental cost when disabled.
class HeartRateRelay {
    hidden var _enabled = false;

    function initialize() {}

    // Phone `hr_ctl` on/off (out-of-band, not a RemoteCommand). Off ⇒ no read, no send.
    function setEnabled(on as Lang.Boolean) as Void { _enabled = on; }

    // Symmetry with EatingRelay.stop() — HR holds no sensor/timer, so this just disables the gate.
    function stop() as Void { _enabled = false; }

    // Called from FaBolusApp.requestStatus() (the existing 15s status tick). Reads the single most-recent
    // ambient HR sample and, if valid + phone-connected, sends the out-of-band `hr_window` envelope the
    // phone parses (samples = [[bpm, epoch]]). No-op when disabled or when the device lacks HR history.
    function emitIfDue() as Void {
        if (!_enabled) { return; }                                    // D-09: off → no read, no send
        if (!(System.getDeviceSettings().phoneConnected)) { return; }
        if (!(Toybox has :ActivityMonitor) ||
            !(ActivityMonitor has :getHeartRateHistory)) { return; }   // device lacks HR history
        // AMBIENT history only (D-08): the last sample the watch already collected. `newestFirst` = true.
        var iter = ActivityMonitor.getHeartRateHistory(1, true);
        var sample = iter.next();     // null when the ambient history is empty (no valid samples yet)
        if (sample == null) { return; }
        var bpm = sample.heartRate;   // Number (bpm); INVALID_HR_SAMPLE when there was no valid reading
        // Skip the no-reading sentinel and any non-physiologic value — mirrors the phone's fail-safe parse.
        if (bpm == ActivityMonitor.INVALID_HR_SAMPLE || bpm <= 0 || bpm >= 300) { return; }
        var epoch = (sample.when != null) ? sample.when.value() : Time.now().value();
        var msg = { "v" => 1, "type" => "hr_window", "t0" => Time.now().value(),
                    "samples" => [ [bpm, epoch] ] };
        Comm.transmit(msg, null, new HeartRateCommListener());
    }
}

class HeartRateCommListener extends Comm.ConnectionListener {
    function initialize() { Comm.ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void {}
}
