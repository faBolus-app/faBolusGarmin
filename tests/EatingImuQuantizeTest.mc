using Toybox.Lang;
using Toybox.Test;

// Pins EatingRelay's compact int16 v2 `imu_window` envelope — the quantize/dequantize
// round-trip resolution, the v2 envelope's shape/size vs. the old 900-Float v1 payload, and the
// previously-no-op EatingCommListener.onError drop counter. The exact per-channel scale + envelope
// keys (v/type/fs/n/ch/scale/t0/data) mirror the phone-side GarminImuWindowDecode.decodeV2
// EXACTLY (the phone already ships that wire contract).
module EatingImuQuantizeTest {

    // A small synthetic window (n=2 samples, ch=6: ax,ay,az,gx,gy,gz), sample-major — same layout
    // EatingSense hands onWindow (see EatingRelay.mc onWindow). Values span a realistic dynamic range
    // for each channel family (accel vs. gyro), staying within EatingRelay.CHANNEL_SCALES' full-scale.
    function sampleWindow() as Lang.Array {
        return [
            1.5, -2.0, 0.75, 300.0, -450.0, 120.0,     // sample 0: ax,ay,az,gx,gy,gz
            -3.9, 4.0, -1.25, -900.0, 999.0, -0.5,     // sample 1
        ];
    }

    // RED->GREEN: the quantize/dequantize pair round-trips each channel within HALF its fixed
    // per-channel scale (the maximum possible rounding error of Math.round(v/scale)) — bounded to
    // ~16-bit resolution, never a garbled/blown-up value.
    (:test)
    function quantizeDequantizeRoundTripsWithinScaleResolution(logger as Test.Logger) as Lang.Boolean {
        var n = 2;
        var ch = 6;
        var window = sampleWindow();
        var bytes = EatingImuEnvelope.quantizeWindow(window, n, ch);
        var back = EatingImuEnvelope.dequantizeWindow(bytes, n, ch);
        Test.assertEqualMessage(back.size(), window.size(), "dequantized sample count == original");
        for (var i = 0; i < window.size(); i += 1) {
            var scale = EatingImuEnvelope.CHANNEL_SCALES[i % ch];
            var err = (back[i] - window[i]).abs();
            Test.assertMessage(err <= (scale / 2.0 + 0.0001),
                "round-trip error within half a quantization step at index " + i);
        }
        return true;
    }

    // The v2 envelope carries version 2, the unchanged WINDOW(150)/6-channel sample count, and a
    // compact int16 payload whose byte size (n*ch*2) is materially smaller than the old v1 Float
    // array's wire cost (n*ch*4, ~3.6 KB for the real WINDOW(150)x6 — see PLAN.md's own accounting).
    (:test)
    function v2EnvelopeCarriesVersionAndIsSmallerThanV1(logger as Test.Logger) as Lang.Boolean {
        var window = [];
        // Real-size WINDOW(150)*6 window of zeros — a shape/size test, values don't matter here.
        for (var i = 0; i < 150 * 6; i += 1) { window.add(0.0); }
        var env = EatingImuEnvelope.buildEnvelope(window, 25, 150, 12345);
        Test.assertEqualMessage(env["v"], 2, "envelope version is 2");
        Test.assertEqualMessage(env["type"], "imu_window", "envelope type unchanged");
        Test.assertEqualMessage(env["n"], 150, "sample count n unchanged (150)");
        Test.assertEqualMessage(env["ch"], 6, "channel count ch == 6");
        var data = env["data"] as Lang.ByteArray;
        Test.assertEqualMessage(data.size(), 150 * 6 * 2, "v2 data is n*ch*2 packed int16 bytes");
        Test.assertMessage(data.size() < 150 * 6 * 4,
            "v2 payload smaller than the ~3.6 KB v1 payload (900 Floats @ 4 bytes)");
        return true;
    }

    // EatingCommListener.onError used to be a no-op — a silently-dropped send was invisible. It now
    // increments an observable per-relay drop counter (mirrors FaBolusApp.scheduleCount()'s seam style).
    (:test)
    function onErrorIncrementsObservableDropCounter(logger as Test.Logger) as Lang.Boolean {
        var relay = new EatingRelay();
        Test.assertEqualMessage(relay.dropCount(), 0, "starts at 0");
        var listener = new EatingCommListener(relay);
        listener.onError();
        Test.assertEqualMessage(relay.dropCount(), 1, "increments once per onError()");
        listener.onError();
        Test.assertEqualMessage(relay.dropCount(), 2, "increments again on a second onError()");
        return true;
    }
}
