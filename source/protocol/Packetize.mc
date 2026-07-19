using Toybox.Lang;

// Thrown when a message that modifies insulin delivery is packetized without the caller having
// explicitly enabled insulin-affecting actions. Mirrors upstream's safety gate.
module PumpX2 {
class InsulinDeliveryNotEnabledException extends Lang.Exception {
    function initialize() {
        Exception.initialize();
    }

    function getErrorMessage() as Lang.String or Null {
        return "actions affecting insulin delivery not enabled";
    }
}

// Converts a Message into wire BLE packets: prepends opcode/txId/length framing, applies the
// optional 24-byte HMAC-SHA1 signature block for signed (insulin-affecting) messages, appends
// CRC-16, then chunks into MTU-sized packets.
//
// Byte-exact port of PumpX2Kit `Packetize` (upstream com.jwoglom.pumpx2...Packetize),
// verified against the cliparser oracle.
module Packetize {
    const DEFAULT_MAX_CHUNK_SIZE = 18; // observed for currentStatus
    const CONTROL_MAX_CHUNK_SIZE = 40; // works for control requests

    function determineMaxChunkSize(message as Message) as Lang.Number {
        if (message.characteristic == Ble.CHAR_CONTROL && message.msgType == MsgType.REQUEST) {
            return CONTROL_MAX_CHUNK_SIZE;
        }
        return DEFAULT_MAX_CHUNK_SIZE;
    }

    // Serializes `message` at `txId` into an Array<Packet>.
    //   authenticationKey  HMAC key for signed messages (ByteArray). Ignored for unsigned.
    //   pumpTimeSinceReset seconds since pump reset, embedded into the signed block (Number/Long).
    //   allowInsulin       safety gate; must be true to packetize a modifiesInsulinDelivery message.
    //   maxChunkSize       override, or null to derive from the message.
    function packetize(
        message as Message,
        authenticationKey as Lang.ByteArray,
        txId as Lang.Number,
        pumpTimeSinceReset as Lang.Number or Lang.Long,
        allowInsulin as Lang.Boolean,
        maxChunkSize as Lang.Number or Null
    ) as Lang.Array<Packet> {
        var cargo = message.cargo;
        var length = 3 + cargo.size();
        if (message.signed) {
            length += 24;
        }

        var packet = new [length]b;
        packet[0] = message.opCode & 0xFF;
        packet[1] = txId & 0xFF;
        packet[2] = (length - 3) & 0xFF;
        for (var k = 0; k < cargo.size(); k++) {
            packet[3 + k] = cargo[k] & 0xFF;
        }

        if (message.modifiesInsulinDelivery && !allowInsulin) {
            throw new InsulinDeliveryNotEnabledException();
        }

        if (message.signed) {
            var i = length - 20;
            var messageData = packet.slice(0, i); // copy of first i bytes
            // Embed pumpTimeSinceReset (4 bytes LE) at offset length-24 == i-4.
            var tsr = Bytes.toUint32(pumpTimeSinceReset);
            for (var k = 0; k < 4; k++) {
                messageData[(length - 24) + k] = tsr[k];
            }
            var hmac = HmacSha1.mac(authenticationKey, messageData); // 20 bytes
            for (var k = 0; k < i; k++) {
                packet[k] = messageData[k];
            }
            for (var k = 0; k < hmac.size(); k++) {
                packet[i + k] = hmac[k];
            }
        }

        // Append CRC-16 over the full framed packet.
        var packetWithCRC = packet.slice(0, null); // copy
        packetWithCRC.addAll(Crc16.calculate(packet));

        var chunkSize = maxChunkSize;
        if (chunkSize == null) {
            chunkSize = determineMaxChunkSize(message);
        }
        var chunked = partition(packetWithCRC, chunkSize);

        var packets = [] as Lang.Array<Packet>;
        var b = chunked.size() - 1;
        for (var c = 0; c < chunked.size(); c++) {
            packets.add(new Packet(b, txId, chunked[c]));
            b -= 1;
        }
        return packets;
    }

    // Splits `bytes` into consecutive slices of at most `size` bytes.
    function partition(bytes as Lang.ByteArray, size as Lang.Number) as Lang.Array<Lang.ByteArray> {
        if (size <= 0) {
            return [bytes] as Lang.Array<Lang.ByteArray>;
        }
        var out = [] as Lang.Array<Lang.ByteArray>;
        var n = bytes.size();
        var i = 0;
        while (i < n) {
            var end = i + size;
            if (end > n) {
                end = n;
            }
            out.add(bytes.slice(i, end));
            i += size;
        }
        return out;
    }
}

}
