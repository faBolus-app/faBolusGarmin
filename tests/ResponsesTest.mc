using Toybox.Lang;
using Toybox.Test;

// Validates response parsing by reassembling oracle-encoded response frames (see the frames
// generated in tools/gen_golden.sh notes) and asserting the parsed field values. Exercises the
// PacketReassembler on real multi-packet frames + ResponseParser CRC/length/dispatch + each
// response's offset math.
module PumpX2 {
module ResponsesTest {

    // Reassembles an array of packet-hex strings into a single frame.
    function reassemble(packetsHex as Lang.Array<Lang.String>) as Lang.ByteArray or Null {
        var ra = new PacketReassembler();
        var frame = null;
        for (var i = 0; i < packetsHex.size(); i++) {
            frame = ra.ingest(Hex.decode(packetsHex[i]));
        }
        return frame;
    }

    (:test)
    function timeSinceResetResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(["000b370b08bc4a831b084a831b9d14"])) as TimeSinceResetResponse;
        Test.assertEqualMessage(m.currentTime, 461589180l, "currentTime");
        Test.assertEqualMessage(m.pumpTimeSinceReset, 461589000l, "pumpTimeSinceReset");
        return true;
    }

    (:test)
    function controlIqIobResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(
            ["010b6d0b11dc050000100e0000d0070000d20400", "000b00013882"])) as ControlIQIOBResponse;
        Test.assertEqualMessage(m.swan6hrIOB, 1234l, "swan6hrIOB");
        Test.assertMessage((m.iobUnits() - 1.234).abs() < 0.0005, "iobUnits ~= 1.234");
        return true;
    }

    (:test)
    function currentBatteryV2ResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(["000b910b0b5a4b01000000000000000022e8"])) as CurrentBatteryV2Response;
        Test.assertEqualMessage(m.batteryPercent(), 75, "batteryPercent");
        Test.assertEqualMessage(m.currentBatteryAbc, 90, "abc");
        Test.assertEqualMessage(m.chargingStatus, 1, "charging");
        return true;
    }

    (:test)
    function insulinStatusResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(["000b250b047b000014e4a2"])) as InsulinStatusResponse;
        Test.assertEqualMessage(m.currentInsulinAmount, 123, "insulin remaining");
        Test.assertEqualMessage(m.insulinLowAmount, 20, "low amount");
        return true;
    }

    (:test)
    function currentBasalStatusResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(["000b290b09ee020000ee0200000074af"])) as CurrentBasalStatusResponse;
        Test.assertEqualMessage(m.currentBasalRate, 750l, "currentBasalRate");
        Test.assertMessage((m.currentBasalUnitsPerHour() - 0.75).abs() < 0.0005, "0.75 u/hr");
        return true;
    }

    (:test)
    function currentEgvGuiDataV2ResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(["000bc10b08bc4a831b780001054dc1"])) as CurrentEgvGuiDataV2Response;
        Test.assertEqualMessage(m.cgmReading, 120, "cgmReading");
        Test.assertEqualMessage(m.egvStatusId, 1, "egvStatusId");
        Test.assertEqualMessage(m.trendRate, 5, "trendRate");
        Test.assertMessage(m.hasValidReading(), "valid reading");
        return true;
    }

    (:test)
    function currentBolusStatusResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(
            ["010b2d0b0f012a000000e8030000881300000001", "000bdc4b"])) as CurrentBolusStatusResponse;
        Test.assertEqualMessage(m.statusId, 1, "statusId");
        Test.assertEqualMessage(m.bolusId, 42, "bolusId");
        Test.assertEqualMessage(m.requestedVolume, 5000l, "requestedVolume");
        Test.assertMessage(m.isActive(), "isActive");
        return true;
    }

    (:test)
    function lastBolusStatusV2ResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(
            ["010ba50b18012a000000bc4a831be80300000000", "000b0100000000e80300004de3"])) as LastBolusStatusV2Response;
        Test.assertEqualMessage(m.status, 1, "status");
        Test.assertEqualMessage(m.bolusId, 42, "bolusId");
        Test.assertEqualMessage(m.deliveredVolume, 1000l, "deliveredVolume");
        Test.assertEqualMessage(m.requestedVolume, 1000l, "requestedVolume");
        Test.assertMessage((m.deliveredUnits() - 1.0).abs() < 0.0005, "1.0 u delivered");
        return true;
    }

    // Signed responses: the 24-byte HMAC trailer is stripped before field parsing.
    (:test)
    function bolusPermissionResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(
            ["0100a3001e009a29000000bc4a831be648b71392", "00006041bc64eb42bce885a3e52b9ebc041048"])) as BolusPermissionResponse;
        Test.assertMessage(m.granted(), "granted");
        Test.assertEqualMessage(m.bolusId, 10650, "bolusId");
        Test.assertEqualMessage(m.status, 0, "status");
        return true;
    }

    (:test)
    function initiateBolusResponseParses(logger as Test.Logger) as Lang.Boolean {
        var m = ResponseParser.parse(reassemble(
            ["01009f001e002a00000001bc4a831b6bc7b85d6d", "00008ac479a8d0effdf9e74c60a0ae2b6564c8"])) as InitiateBolusResponse;
        Test.assertMessage(m.accepted(), "accepted");
        Test.assertEqualMessage(m.bolusId, 42, "bolusId");
        Test.assertEqualMessage(m.statusTypeId, 1, "statusTypeId");
        return true;
    }

    // A corrupted CRC must be rejected.
    (:test)
    function corruptCrcRejected(logger as Test.Logger) as Lang.Boolean {
        var frame = reassemble(["000b370b08bc4a831b084a831b9d14"]);
        frame[frame.size() - 1] = (frame[frame.size() - 1] ^ 0xFF) & 0xFF; // flip CRC hi byte
        var threw = false;
        try {
            ResponseParser.parse(frame);
        } catch (e instanceof ResponseParseException) {
            threw = true;
        }
        Test.assertMessage(threw, "expected ResponseParseException on bad CRC");
        return true;
    }
}

}
