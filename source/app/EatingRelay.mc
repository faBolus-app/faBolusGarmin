using Toybox.Timer;
using Toybox.Communications as Comm;
using Toybox.System;
using Toybox.Time;
using Toybox.Math;
using Toybox.Lang;
using EatingSenseKit;

// G-M3 (19-04): pure, EatingRelay-instance-free construction of the `imu_window` wire envelope — a
// MODULE (not class members) so its consts (CHANNEL_SCALES etc.) are externally accessible as
// `EatingImuEnvelope.CONST` (mirrors AppState's own module-const convention, e.g.
// AppState.POLL_REPLY_DEADLINE_SEC) and tests/EatingImuQuantizeTest.mc can drive the quantize/
// dequantize/build functions directly without an EatingRelay instance.
module EatingImuEnvelope {
    // The v2 compact int16 imu_window envelope's channel count — accel x/y/z, gyro x/y/z, same order
    // as the old v1 "ch" name array (["ax","ay","az","gx","gy","gz"]).
    const CH = 6;
    // Fixed per-channel dequantization scale (float = int16 * scale[ch % CH]): accel channels use a
    // +/-8g full-scale (~0.000244 g resolution), gyro channels a +/-1000 dps full-scale (~0.0305 dps
    // resolution) — generous headroom for wrist eating-gesture motion while keeping ~16-bit precision.
    // NOT a hardcoded duplicate on the phone side: this SAME array travels IN the wire envelope's
    // "scale" key and 19-05's GarminImuWindowDecode.decodeV2 reads it back out of the envelope (never a
    // separately-maintained Swift constant), so the two sides can never silently drift apart. The
    // faBolusNudge MESSAGE_CONTRACT.md is the external document-of-record for these units/ranges to
    // sync (deferred owner note: that repo is not present in this checkout).
    const ACCEL_SCALE = 8.0 / 32767.0;
    const GYRO_SCALE = 1000.0 / 32767.0;
    const CHANNEL_SCALES = [ACCEL_SCALE, ACCEL_SCALE, ACCEL_SCALE, GYRO_SCALE, GYRO_SCALE, GYRO_SCALE];

    // Builds the v2 compact int16 imu_window envelope for one raw window. Keys mirror 19-05's
    // phone-side GarminImuWindowDecode.decodeV2 EXACTLY: ch (Int channel count), n (Int
    // samples/channel), scale (Array<Float>, length ch, IN the envelope — never a hardcoded duplicate
    // constant), data (packed int16 ByteArray, n*ch*2 bytes, little-endian pairs, sample-major).
    function buildEnvelope(window as Lang.Array, fs as Lang.Number, n as Lang.Number, t0 as Lang.Number) as Lang.Dictionary {
        return { "v" => 2, "type" => "imu_window", "fs" => fs, "n" => n, "ch" => CH,
                 "scale" => CHANNEL_SCALES, "t0" => t0, "data" => quantizeWindow(window, n, CH) };
    }

    // Quantizes a raw sample-major Float window (length n*ch) into a packed int16 ByteArray (n*ch*2
    // bytes, little-endian pairs) using CHANNEL_SCALES[i % ch] per element — the exact inverse of
    // 19-05's GarminImuWindowDecode.decodeV2. ByteArray element reads/writes are SIGNED (a 0xFF byte
    // reads back as -1), so every byte is masked with `& 0xFF` on write. Fail-safe:
    // EatingSense always hands a full n*ch window in production, but a SHORT/empty window (e.g. a
    // test double's []) zero-fills the missing tail rather than throwing an Array Out Of Bounds Error
    // — an unguarded index here used to escape EVEN a surrounding try/catch in this SDK/simulator (see
    // tests/RelayResilienceTest.mc, eatingRelayTransmitThrowDoesNotStrandItsTimer).
    function quantizeWindow(window as Lang.Array, n as Lang.Number, ch as Lang.Number) as Lang.ByteArray {
        var out = new [n * ch * 2]b;
        var have = window.size();
        for (var i = 0; i < n * ch; i += 1) {
            var scale = CHANNEL_SCALES[i % ch];
            var v = (i < have) ? window[i] : 0.0;
            var q = Math.round(v / scale).toNumber();
            if (q > 32767) { q = 32767; } else if (q < -32768) { q = -32768; }   // clamp to int16 range
            out[2 * i] = q & 0xFF;          // low byte
            out[2 * i + 1] = (q >> 8) & 0xFF;   // high byte (>> is sign-preserving; masked to 8 bits)
        }
        return out;
    }

    // Test-only mirror of the PHONE's decodeV2 (19-05's GarminImuWindowDecode.decodeV2) — lets
    // tests/EatingImuQuantizeTest.mc assert the quantize/dequantize pair round-trips within the fixed
    // scale's resolution without depending on the phone/Swift code. NEVER called by production code —
    // the phone owns the real dequantize.
    function dequantizeWindow(bytes as Lang.ByteArray, n as Lang.Number, ch as Lang.Number) as Lang.Array {
        var out = [];
        for (var i = 0; i < n * ch; i += 1) {
            var lo = bytes[2 * i] & 0xFF;
            var hi = bytes[2 * i + 1] & 0xFF;
            var u = (hi << 8) | lo;
            var q = (u >= 32768) ? (u - 65536) : u;   // reinterpret as signed int16
            out.add(q * CHANNEL_SCALES[i % ch]);
        }
        return out;
    }
}

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
    // G-M3: observable count of dropped imu_window sends — EatingCommListener.onError used to be a
    // no-op, making a silently-dropped send invisible. Test-only-seam style (mirrors
    // FaBolusApp.scheduleCount()/isRunning() above).
    hidden var _dropCount as Lang.Number = 0;
    // 13-LW-01 (LOW): observable count of onWindow's own empty-catch guard firing (a
    // buildEnvelope/transmitWindow throw) — previously silent, giving zero observability into a
    // persistent transmit failure. A DIFFERENT failure mode from _dropCount above (that one counts an
    // ASYNC EatingCommListener.onError after a send was actually dispatched; this counts a SYNCHRONOUS
    // throw during envelope-build/dispatch itself) — mirrors the same simple counter pattern.
    hidden var _onWindowGuardFailureCount as Lang.Number = 0;

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

    // Test-observable running state (see tests/RelayResilienceTest.mc, C5-02).
    function isRunning() as Lang.Boolean { return _running; }

    // Test-observable drop count (see tests/EatingImuQuantizeTest.mc, G-M3).
    function dropCount() as Lang.Number { return _dropCount; }
    function recordDrop() as Void { _dropCount += 1; }

    // Test-observable onWindow guard-failure count (13-LW-01; see tests/RelayResilienceTest.mc).
    function onWindowGuardFailureCount() as Lang.Number { return _onWindowGuardFailureCount; }

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
        // C5-02: EatingRelay owns its OWN timer lifecycle (beginBurst/endBurst above), completely
        // independent of FaBolusApp's poll loop — so pollTick's "scheduleNextPoll still runs" guarantee
        // does not apply here. onWindow is invoked as an EatingSenseKit callback; an unguarded throw
        // propagating out of it could crash the relay's owning process out from under its own
        // still-armed duty-cycle timer. Guard independently. G-M3 (19-04): the guard now wraps
        // buildEnvelope too (not just transmitWindow) — quantizeWindow indexes into `window`, so a
        // malformed/short window (e.g. a test double's []) can throw during envelope-building itself,
        // before transmitWindow is ever reached (see tests/RelayResilienceTest.mc,
        // eatingRelayTransmitThrowDoesNotStrandItsTimer).
        try {
            var msg = EatingImuEnvelope.buildEnvelope(window, RATE, WINDOW, Time.now().value());
            transmitWindow(msg);
        } catch (e) {
            // 13-LW-01: was silently swallowed with zero observability — now counted (see
            // _onWindowGuardFailureCount above), still deliberately non-fatal (the duty-cycle timer must
            // not be stranded by a transmit failure).
            _onWindowGuardFailureCount += 1;
        }
    }

    // Isolated so a test double (see tests/RelayResilienceTest.mc) can force a synchronous throw without a
    // real BLE transport.
    function transmitWindow(msg as Lang.Dictionary) as Void {
        Comm.transmit(msg, null, new EatingCommListener(self));
    }
}

class EatingCommListener extends Comm.ConnectionListener {
    hidden var _relay as EatingRelay;
    function initialize(relay as EatingRelay) {
        Comm.ConnectionListener.initialize();
        _relay = relay;
    }
    function onComplete() as Void {}
    // G-M3: was a no-op — a silently-dropped imu_window send was invisible. Now increments the
    // owning relay's observable drop counter (tests/EatingImuQuantizeTest.mc).
    function onError() as Void { _relay.recordDrop(); }
}
