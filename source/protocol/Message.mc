using Toybox.Lang;

// Message type (request opcodes are even, responses odd = request+1). Port of MessageType.
module MsgType {
    enum {
        REQUEST,
        RESPONSE,
    }
}

// Base class for all pump messages. Port of the PumpX2Kit `Message` protocol + `MessageProps`.
//
// `cargo` is the payload without the opcode/txId/length framing or CRC (those are added by
// Packetize). The per-type metadata (opCode, signed, characteristic, ...) is set by each
// subclass in its initialize(). Subclasses build `cargo` in initialize() from their fields, and
// (later) implement parse() for responses.
class Message {
    var cargo as Lang.ByteArray;

    // Static-ish metadata, set by subclasses.
    var opCode as Lang.Number = 0;
    var signed as Lang.Boolean = false;
    var stream as Lang.Boolean = false;
    var msgType as Lang.Number = MsgType.REQUEST;
    var characteristic as Lang.Number = Ble.CHAR_CURRENT_STATUS;
    var modifiesInsulinDelivery as Lang.Boolean = false;

    function initialize() {
        cargo = []b;
    }

    // Parses raw wire cargo bytes into fields. Default no-op; responses override.
    function parse(raw as Lang.ByteArray) as Void {
    }
}

// Tracks the next transaction id (0-255, wrapping) shared across a session.
// Port of PumpX2Kit `TransactionId`.
class TransactionId {
    private var _value as Lang.Number;

    function initialize(start as Lang.Number) {
        _value = start & 0xFF;
    }

    // Returns the current id, then increments (wrapping at 256).
    function nextThenIncrement() as Lang.Number {
        var v = _value;
        _value = (_value + 1) & 0xFF;
        return v;
    }

    function current() as Lang.Number {
        return _value;
    }
}
