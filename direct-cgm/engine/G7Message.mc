using Toybox.Lang;

// Dexcom G7 / ONE+ real-time glucose message decoder (opcode 0x4e), ported to Monkey C from the
// vendored Swift G7SensorKit decoder (originally LoopKit/G7SensorKit, MIT). Passive: we only parse
// the broadcast the official app already authenticated — we never send auth. mg/dL.
module DirectCgm {
    class G7Message {
        // Parse a control-characteristic glucose message. Returns a dict, or null if not a valid
        // glucose message: { :glucose (Number|null), :ageSec, :reliable (Bool), :trendToken (String) }
        static function parseGlucose(data as Lang.ByteArray or Null) as Lang.Dictionary or Null {
            if (data == null || data.size() < 19) { return null; }
            if (data[0] != 0x4e || data[1] != 0x00) { return null; }

            var age = u16(data, 10);                 // seconds from reading to BLE comms
            var raw = u16(data, 12);
            var glucose = (raw != 0xffff) ? (raw & 0xfff) : null;
            var reliable = (data[14] == 6);          // AlgorithmState.ok

            var trendToken = "flat";
            if (data[15] != 0x7f) {
                var t = data[15];
                if (t > 127) { t -= 256; }           // signed int8
                trendToken = tokenFor(t / 10.0);     // tenths of mg/dL/min → rate
            }
            return { :glucose => glucose, :ageSec => age, :reliable => reliable, :trendToken => trendToken };
        }

        // 9-byte backfill (history) message → { :glucose, :sensorSec, :reliable }.
        static function parseBackfill(data as Lang.ByteArray or Null) as Lang.Dictionary or Null {
            if (data == null || data.size() != 9) { return null; }
            var sensorSec = data[0] | (data[1] << 8) | (data[2] << 16);
            var raw = u16(data, 4);
            var glucose = (raw != 0xffff) ? (raw & 0xfff) : null;
            var reliable = (data[6] == 6);
            return { :glucose => glucose, :sensorSec => sensorSec, :reliable => reliable };
        }

        static function u16(d as Lang.ByteArray, i as Lang.Number) as Lang.Number {
            return d[i] | (d[i + 1] << 8);
        }

        // Map a signed trend rate (mg/dL/min) to the RemoteCommand trend tokens AppState renders.
        static function tokenFor(rate as Lang.Float) as Lang.String {
            if (rate <= -3.0) { return "downdown"; }
            if (rate <= -2.0) { return "downdown"; }
            if (rate <= -1.0) { return "down"; }
            if (rate < 1.0)   { return "flat"; }
            if (rate < 2.0)   { return "up"; }
            if (rate < 3.0)   { return "upup"; }
            return "upup";
        }
    }
}
