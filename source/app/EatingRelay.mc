using Toybox.Timer;
using Toybox.Communications as Comm;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;
using EatingSenseKit;

// Duty-cycled wrist eating sensing → streams `imu_window` messages to the phone, which runs the eating
// model (Garmin has no on-device ML). PHONE-GATED (start/stop on command) so it costs no battery unless
// the user turned eating nudges on. Advisory; degrades gracefully where raw accel+gyro streaming is
// unavailable (EatingSense.start() throws → we stop). See faBolusNudge MESSAGE_CONTRACT.md.
class EatingRelay {
    hidden const SENSE_MS = 8 * 1000;    // duty-cycle on  (BATTERY.md)
    hidden const IDLE_MS = 30 * 1000;    // duty-cycle off
    hidden const WINDOW = 150;           // 6 s @ 25 Hz — matches the model
    hidden const RATE = 25;

    hidden var _sensor;
    hidden var _timer;
    hidden var _sensing = false;
    hidden var _running = false;

    function initialize() {}

    function start() as Void {
        if (_running) { return; }
        _running = true;
        _sensor = new EatingSenseKit.EatingSense(WINDOW, RATE, method(:onWindow));
        _timer = new Timer.Timer();
        beginBurst();
    }

    function stop() as Void {
        _running = false;
        if (_sensing && _sensor != null) { _sensor.stop(); }
        _sensing = false;
        if (_timer != null) { _timer.stop(); }
    }

    function beginBurst() as Void {
        if (!_running || _sensor == null) { return; }
        try {
            _sensor.start();
            _sensing = true;
            _timer.start(method(:endBurst), SENSE_MS, false);
        } catch (e) {
            _running = false;   // device lacks raw streaming → don't keep retrying
        }
    }

    function endBurst() as Void {
        if (_sensing && _sensor != null) { _sensor.stop(); }
        _sensing = false;
        if (_running) { _timer.start(method(:beginBurst), IDLE_MS, false); }
    }

    // EatingSense hands us one raw window (Array<Float>, length WINDOW*6, [ax,ay,az,gx,gy,gz …]).
    function onWindow(window) as Void {
        if (!(System.getDeviceSettings().phoneConnected)) { return; }
        var msg = { "v" => 1, "type" => "imu_window", "fs" => RATE, "n" => WINDOW,
                    "ch" => ["ax", "ay", "az", "gx", "gy", "gz"],
                    "t0" => Time.now().value(), "data" => window };
        Comm.transmit(msg, null, new EatingCommListener());
    }
}

class EatingCommListener extends Comm.ConnectionListener {
    function initialize() { Comm.ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void {}
}
