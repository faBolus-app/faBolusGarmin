using Toybox.Lang;

// AUTHORIZATION-characteristic request messages. Port of PumpX2Kit auth wire messages.
// The legacy Central/Pump challenge pair (16-char pairing) and the JPAKE key-confirmation
// message used by the resume path (rounds 3-4). Cargo layouts verified byte-exact vs oracle.

// Legacy 16-char pairing round 1: appInstanceId (2 LE) + first 8 bytes of the central challenge.
module PumpX2 {
class CentralChallengeRequest extends Message {
    function initialize(appInstanceId as Lang.Number, centralChallenge as Lang.ByteArray) {
        Message.initialize();
        me.opCode = 0x10;
        me.characteristic = Ble.CHAR_AUTHORIZATION;
        me.msgType = MsgType.REQUEST;
        var c = Bytes.toUint16(appInstanceId);
        c.addAll(centralChallenge.slice(0, 8));
        me.cargo = c;
    }
}

// Legacy 16-char pairing round 2: appInstanceId (2 LE) + 20-byte HMAC-SHA1 challenge hash.
class PumpChallengeRequest extends Message {
    function initialize(appInstanceId as Lang.Number, pumpChallengeHash as Lang.ByteArray) {
        Message.initialize();
        me.opCode = 0x12;
        me.characteristic = Ble.CHAR_AUTHORIZATION;
        me.msgType = MsgType.REQUEST;
        var c = Bytes.toUint16(appInstanceId);
        c.addAll(pumpChallengeHash);
        me.cargo = c;
    }
}

// JPAKE session-key request (resume round 3). Opcode 0x26, 2-byte cargo (challengeParam LE).
class Jpake3SessionKeyRequest extends Message {
    function initialize(challengeParam as Lang.Number) {
        Message.initialize();
        me.opCode = 0x26;
        me.characteristic = Ble.CHAR_AUTHORIZATION;
        me.msgType = MsgType.REQUEST;
        me.cargo = Bytes.toUint16(challengeParam);
    }
}

// JPAKE key-confirmation request (round 4). Opcode 0x28, 50-byte cargo:
// appInstanceId (2 LE) + nonce (8) + reserved (8) + hashDigest (32). Verified vs oracle.
class Jpake4KeyConfirmationRequest extends Message {
    function initialize(
        appInstanceId as Lang.Number,
        nonce as Lang.ByteArray,
        reserved as Lang.ByteArray,
        hashDigest as Lang.ByteArray
    ) {
        Message.initialize();
        me.opCode = 0x28;
        me.characteristic = Ble.CHAR_AUTHORIZATION;
        me.msgType = MsgType.REQUEST;
        var c = Bytes.toUint16(appInstanceId);
        c.addAll(nonce);
        c.addAll(reserved);
        c.addAll(hashDigest);
        me.cargo = c;
    }
}

}
