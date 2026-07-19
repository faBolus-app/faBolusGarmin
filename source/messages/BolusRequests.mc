using Toybox.Lang;

// CONTROL-characteristic signed bolus messages. Port of PumpX2Kit `Requests/Control/`.
// All are signed (24-byte HMAC-SHA1 trailer applied by Packetize). Only InitiateBolusRequest
// modifies insulin delivery. Opcodes and cargo layouts verified byte-exact vs oracle.

// Requests permission to begin a bolus. Opcode 0xA2, empty cargo, signed.
module PumpX2 {
class BolusPermissionRequest extends Message {
    function initialize() {
        Message.initialize();
        me.opCode = 0xA2;
        me.characteristic = Ble.CHAR_CONTROL;
        me.msgType = MsgType.REQUEST;
        me.signed = true;
    }
}

// Cancels an in-progress bolus. Opcode 0xA0, cargo = bolusId (2 LE) + [0,0], signed.
class CancelBolusRequest extends Message {
    function initialize(bolusId as Lang.Number) {
        Message.initialize();
        me.opCode = 0xA0;
        me.characteristic = Ble.CHAR_CONTROL;
        me.msgType = MsgType.REQUEST;
        me.signed = true;
        var c = Bytes.toUint16(bolusId);
        c.addAll([0, 0]b);
        me.cargo = c;
    }
}

// Releases a previously granted bolus permission. Opcode 0xF0, cargo = bolusID (2 LE) + [0,0], signed.
class BolusPermissionReleaseRequest extends Message {
    function initialize(bolusID as Lang.Number) {
        Message.initialize();
        me.opCode = 0xF0;
        me.characteristic = Ble.CHAR_CONTROL;
        me.msgType = MsgType.REQUEST;
        me.signed = true;
        var c = Bytes.toUint16(bolusID);
        c.addAll([0, 0]b);
        me.cargo = c;
    }
}

// Initiates a bolus. Opcode 0x9E, signed, modifies insulin delivery. 37-byte cargo (all volumes
// in milliunits, little-endian):
//   totalVolume(u32) bolusID(u16) [0,0] bolusTypeBitmask(u8) foodVolume(u32) correctionVolume(u32)
//   bolusCarbs(u16) bolusBG(u16) bolusIOB(u32) extendedVolume(u32) extendedSeconds(u32) extended3(u32)
class InitiateBolusRequest extends Message {
    function initialize(
        totalVolume as Lang.Number or Lang.Long,
        bolusID as Lang.Number,
        bolusTypeBitmask as Lang.Number,
        foodVolume as Lang.Number or Lang.Long,
        correctionVolume as Lang.Number or Lang.Long,
        bolusCarbs as Lang.Number,
        bolusBG as Lang.Number,
        bolusIOB as Lang.Number or Lang.Long
    ) {
        Message.initialize();
        me.opCode = 0x9E;
        me.characteristic = Ble.CHAR_CONTROL;
        me.msgType = MsgType.REQUEST;
        me.signed = true;
        me.modifiesInsulinDelivery = true;

        var c = Bytes.toUint32(totalVolume);      // 4
        c.addAll(Bytes.toUint16(bolusID));        // 2
        c.addAll([0, 0]b);                        // 2 reserved
        c.add(bolusTypeBitmask & 0xFF);           // 1
        c.addAll(Bytes.toUint32(foodVolume));     // 4
        c.addAll(Bytes.toUint32(correctionVolume));// 4
        c.addAll(Bytes.toUint16(bolusCarbs));     // 2
        c.addAll(Bytes.toUint16(bolusBG));        // 2
        c.addAll(Bytes.toUint32(bolusIOB));       // 4
        c.addAll(Bytes.toUint32(0));              // 4 extendedVolume
        c.addAll(Bytes.toUint32(0));              // 4 extendedSeconds
        c.addAll(Bytes.toUint32(0));              // 4 extended3
        me.cargo = c;
    }
}

}
