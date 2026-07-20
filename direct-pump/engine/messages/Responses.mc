using Toybox.Lang;

// Inbound (pump -> app) response messages. Ports of PumpX2Kit `Responses.swift`. Each populates
// its fields from cargo in parse(). Cargo layouts/offsets are from the byte-exact Swift reference
// and validated by round-tripping oracle-encoded frames through ResponseParser (see ResponsesTest).

// Reads a signed 8-bit value at offset i (two's complement).
module PumpX2 {
function readInt8(raw as Lang.ByteArray, i as Lang.Number) as Lang.Number {
    var v = raw[i] & 0xFF;
    return (v >= 128) ? (v - 256) : v;
}

// IOB read (Control-IQ). Opcode 109. iobUnits() uses swan6hrIOB/1000 (matches the pump display).
class ControlIQIOBResponse extends Message {
    var mudaliarIOB as Lang.Long = 0l;
    var timeRemainingSeconds as Lang.Long = 0l;
    var mudaliarTotalIOB as Lang.Long = 0l;
    var swan6hrIOB as Lang.Long = 0l;
    var iobType as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0x6D; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        mudaliarIOB = Bytes.readUint32(raw, 0);
        timeRemainingSeconds = Bytes.readUint32(raw, 4);
        mudaliarTotalIOB = Bytes.readUint32(raw, 8);
        swan6hrIOB = Bytes.readUint32(raw, 12);
        iobType = raw[16] & 0xFF;
    }
    function iobUnits() as Lang.Float { return swan6hrIOB.toFloat() / 1000.0; }
}

// Insulin remaining. Opcode 37.
class InsulinStatusResponse extends Message {
    var currentInsulinAmount as Lang.Number = 0; // units remaining
    var isEstimate as Lang.Number = 0;
    var insulinLowAmount as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0x25; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        currentInsulinAmount = Bytes.readUint16(raw, 0);
        isEstimate = raw[2] & 0xFF;
        insulinLowAmount = raw[3] & 0xFF;
    }
}

// Battery. Opcode 145. batteryPercent() = currentBatteryIbc.
class CurrentBatteryV2Response extends Message {
    var currentBatteryAbc as Lang.Number = 0;
    var currentBatteryIbc as Lang.Number = 0; // battery percent
    var chargingStatus as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0x91; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        currentBatteryAbc = raw[0] & 0xFF;
        currentBatteryIbc = raw[1] & 0xFF;
        chargingStatus = raw[2] & 0xFF;
    }
    function batteryPercent() as Lang.Number { return currentBatteryIbc; }
}

// Current CGM reading + trend (GUI data, V2). Opcode 193. cgmReading mg/dL; trendRate signed Int8.
class CurrentEgvGuiDataV2Response extends Message {
    var bgReadingTimestampSeconds as Lang.Long = 0l;
    var cgmReading as Lang.Number = 0; // mg/dL
    var egvStatusId as Lang.Number = 0;
    var trendRate as Lang.Number = 0;  // signed, 0.1 mg/dL/min units
    function initialize() { Message.initialize(); opCode = 0xC1; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        bgReadingTimestampSeconds = Bytes.readUint32(raw, 0);
        cgmReading = Bytes.readUint16(raw, 4);
        egvStatusId = raw[6] & 0xFF;
        trendRate = readInt8(raw, 7);
    }
    function trendRateMgDlPerMin() as Lang.Float { return trendRate.toFloat() / 10.0; }
    // EGV status: 0=INVALID,1=VALID,2=LOW,3=HIGH,4=UNAVAILABLE.
    function hasValidReading() as Lang.Boolean {
        return (egvStatusId == 1 || egvStatusId == 2 || egvStatusId == 3) && cgmReading > 0 && cgmReading < 600;
    }
}

// Pump clock. Opcode 55. currentTime is the value to embed as pumpTimeSinceReset when signing.
class TimeSinceResetResponse extends Message {
    var currentTime as Lang.Long = 0l;
    var pumpTimeSinceReset as Lang.Long = 0l;
    function initialize() { Message.initialize(); opCode = 0x37; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        currentTime = Bytes.readUint32(raw, 0);
        pumpTimeSinceReset = Bytes.readUint32(raw, 4);
    }
    function signingTimestamp() as Lang.Long { return currentTime; }
}

// Basal rate. Opcode 41. Rates in milliunits/hour.
class CurrentBasalStatusResponse extends Message {
    var profileBasalRate as Lang.Long = 0l;
    var currentBasalRate as Lang.Long = 0l;
    var basalModifiedBitmask as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0x29; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        profileBasalRate = Bytes.readUint32(raw, 0);
        currentBasalRate = Bytes.readUint32(raw, 4);
        basalModifiedBitmask = raw[8] & 0xFF;
    }
    function currentBasalUnitsPerHour() as Lang.Float { return currentBasalRate.toFloat() / 1000.0; }
}

// In-progress bolus status. Opcode 45. statusId: 1=delivering, 2=requesting.
class CurrentBolusStatusResponse extends Message {
    var statusId as Lang.Number = 0;
    var bolusId as Lang.Number = 0;
    var requestedVolume as Lang.Long = 0l;
    function initialize() { Message.initialize(); opCode = 0x2D; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        statusId = raw[0] & 0xFF;
        bolusId = Bytes.readUint16(raw, 1);
        requestedVolume = Bytes.readUint32(raw, 9);
    }
    function isActive() as Lang.Boolean { return statusId == 1 || statusId == 2; }
}

// Last completed bolus. Opcode 165. Volumes in milliunits.
class LastBolusStatusV2Response extends Message {
    var status as Lang.Number = 0;
    var bolusId as Lang.Number = 0;
    var timestamp as Lang.Long = 0l;
    var deliveredVolume as Lang.Long = 0l;
    var requestedVolume as Lang.Long = 0l;
    function initialize() { Message.initialize(); opCode = 0xA5; msgType = MsgType.RESPONSE; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        status = raw[0] & 0xFF;
        bolusId = Bytes.readUint16(raw, 1);
        timestamp = Bytes.readUint32(raw, 5);
        deliveredVolume = Bytes.readUint32(raw, 9);
        requestedVolume = Bytes.readUint32(raw, 20);
    }
    function deliveredUnits() as Lang.Float { return deliveredVolume.toFloat() / 1000.0; }
}

// Bolus permission grant. Opcode 163, signed. granted() = status == 0.
class BolusPermissionResponse extends Message {
    var status as Lang.Number = 0;
    var bolusId as Lang.Number = 0;
    var nackReasonId as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0xA3; msgType = MsgType.RESPONSE; signed = true; characteristic = Ble.CHAR_CONTROL; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        status = raw[0] & 0xFF;
        bolusId = Bytes.readUint16(raw, 1);
        nackReasonId = raw[5] & 0xFF;
    }
    function granted() as Lang.Boolean { return status == 0; }
}

// Initiate-bolus ack. Opcode 159, signed. accepted() = status == 0.
class InitiateBolusResponse extends Message {
    var status as Lang.Number = 0;
    var bolusId as Lang.Number = 0;
    var statusTypeId as Lang.Number = 0;
    function initialize() { Message.initialize(); opCode = 0x9F; msgType = MsgType.RESPONSE; signed = true; characteristic = Ble.CHAR_CONTROL; }
    function parse(raw as Lang.ByteArray) as Void {
        cargo = raw;
        status = raw[0] & 0xFF;
        bolusId = Bytes.readUint16(raw, 1);
        statusTypeId = raw[5] & 0xFF;
    }
    function accepted() as Lang.Boolean { return status == 0; }
}

}
