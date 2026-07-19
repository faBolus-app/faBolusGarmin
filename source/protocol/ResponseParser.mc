using Toybox.Lang;

// Raised when a response frame fails CRC/length validation or has an unknown opcode.
class ResponseParseException extends Lang.Exception {
    var reason as Lang.String;
    function initialize(reason as Lang.String) {
        Exception.initialize();
        me.reason = reason;
    }
    function getErrorMessage() as Lang.String or Null { return "ResponseParser: " + reason; }
}

// Parses a reassembled inbound frame into a typed response Message (fields populated).
// Frame layout: [opcode, txId, length, cargo(length bytes), crc0, crc1]. Validates CRC-16 and
// cargo length, strips the 24-byte HMAC trailer from signed responses, then dispatches by opcode.
// Port of PumpX2Kit `ResponseParser`.
//
// Note: dispatch is by opcode alone (as upstream). JPAKE responses on the AUTHORIZATION
// characteristic share some opcodes with CURRENT_STATUS responses and are NOT handled here — the
// BLE layer routes AUTHORIZATION frames to the resume coordinator instead.
module ResponseParser {

    // Constructs the response Message for an opcode, or null if unknown.
    function makeResponse(opCode as Lang.Number) as Message or Null {
        switch (opCode) {
            case 0x6D: return new ControlIQIOBResponse();
            case 0x25: return new InsulinStatusResponse();
            case 0x91: return new CurrentBatteryV2Response();
            case 0xC1: return new CurrentEgvGuiDataV2Response();
            case 0x37: return new TimeSinceResetResponse();
            case 0x29: return new CurrentBasalStatusResponse();
            case 0x2D: return new CurrentBolusStatusResponse();
            case 0xA5: return new LastBolusStatusV2Response();
            case 0xA3: return new BolusPermissionResponse();
            case 0x9F: return new InitiateBolusResponse();
        }
        return null;
    }

    // True for signed responses (24-byte HMAC trailer appended after the cargo).
    function isSigned(opCode as Lang.Number) as Lang.Boolean {
        return opCode == 0xA3 || opCode == 0x9F;
    }

    // Validates CRC + length and returns the parsed response Message. Throws on failure.
    function parse(frame as Lang.ByteArray) as Message {
        if (frame.size() < 5) {
            throw new ResponseParseException("frame too short");
        }
        var bodyLen = frame.size() - 2;
        var body = frame.slice(0, bodyLen);
        var crc = frame.slice(bodyLen, null);
        var expectedCrc = Crc16.calculate(body);
        if (!(crc[0] == expectedCrc[0] && crc[1] == expectedCrc[1])) {
            throw new ResponseParseException("CRC mismatch");
        }

        var opCode = frame[0] & 0xFF;
        var length = frame[2] & 0xFF;
        if (3 + length > body.size()) {
            throw new ResponseParseException("cargo length mismatch for opcode " + opCode.format("%d"));
        }

        var cargoLen = length;
        if (isSigned(opCode)) {
            cargoLen = length - 24;
            if (cargoLen < 0) { cargoLen = 0; }
        }
        var cargo = body.slice(3, 3 + cargoLen);

        var msg = makeResponse(opCode);
        if (msg == null) {
            throw new ResponseParseException("unknown opcode " + opCode.format("%d"));
        }
        msg.parse(cargo);
        return msg;
    }
}
