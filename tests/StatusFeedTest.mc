using Toybox.Lang;
using Toybox.Test;

// Tests the pure status-dict builder used by DirectTransport (the BLE session itself needs
// hardware; this validates the translation into the phone-schema dict AppState consumes).
module PumpX2 {
    module StatusFeedTest {

        (:test)
        function trendTokenMapping(logger as Test.Logger) as Lang.Boolean {
            Test.assertEqualMessage(StatusFeed.trendToken(0), "flat", "0 -> flat");
            Test.assertEqualMessage(StatusFeed.trendToken(5), "flat", "0.5 -> flat");
            Test.assertEqualMessage(StatusFeed.trendToken(15), "up45", "1.5 -> up45");
            Test.assertEqualMessage(StatusFeed.trendToken(25), "up", "2.5 -> up");
            Test.assertEqualMessage(StatusFeed.trendToken(40), "upup", "4.0 -> upup");
            Test.assertEqualMessage(StatusFeed.trendToken(-15), "down45", "-1.5 -> down45");
            Test.assertEqualMessage(StatusFeed.trendToken(-25), "down", "-2.5 -> down");
            Test.assertEqualMessage(StatusFeed.trendToken(-40), "downdown", "-4.0 -> downdown");
            return true;
        }

        (:test)
        function buildCopiesKnownFields(logger as Test.Logger) as Lang.Boolean {
            var agg = {
                "bgMgdl" => 120, "trend" => "flat", "glucoseAgeSec" => 0,
                "units" => 1.2, "reservoirUnits" => 123.0, "batteryPercent" => 75,
                "lastBolusUnits" => 1.0,
                "ignored" => 999,   // not part of the schema -> must be dropped
            };
            var d = StatusFeed.build(agg);
            Test.assertEqualMessage(d["kind"], "statusRead", "kind");
            Test.assertEqualMessage(d["version"], 1, "version");
            Test.assertEqualMessage(d["bgMgdl"], 120, "bgMgdl");
            Test.assertEqualMessage(d["trend"], "flat", "trend");
            Test.assertEqualMessage(d["batteryPercent"], 75, "batteryPercent");
            Test.assertMessage(!d.hasKey("ignored"), "unknown field dropped");
            return true;
        }

        (:test)
        function bolusStatusShape(logger as Test.Logger) as Lang.Boolean {
            var d = StatusFeed.bolusStatus("req-1", "delivered", null);
            Test.assertEqualMessage(d["kind"], "bolusStatus", "kind");
            Test.assertEqualMessage(d["requestId"], "req-1", "requestId");
            Test.assertEqualMessage(d["status"], "delivered", "status");
            Test.assertMessage(!d.hasKey("message"), "null message omitted");
            return true;
        }
    }
}
