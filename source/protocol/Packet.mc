using Toybox.Lang;

// One raw BLE packet. A sequence of Packets over a characteristic makes up one Message.
// Port of PumpX2Kit `Packet`.
//
// Wire layout of build(): [packetsRemaining, transactionId, internalCargo...]. For the
// first/only packet, internalCargo is [opcode, txId, len, cargo..., (hmac), crcLo, crcHi].
class Packet {
    var packetsRemaining as Lang.Number;
    var transactionId as Lang.Number;
    var internalCargo as Lang.ByteArray;

    function initialize(packetsRemaining as Lang.Number, transactionId as Lang.Number, internalCargo as Lang.ByteArray) {
        me.packetsRemaining = packetsRemaining & 0xFF;
        me.transactionId = transactionId & 0xFF;
        me.internalCargo = internalCargo;
    }

    function build() as Lang.ByteArray {
        var out = [packetsRemaining, transactionId]b;
        out.addAll(internalCargo);
        return out;
    }
}

// Reassembles multi-packet BLE notifications into a single message frame.
// Each raw packet is [packetsRemaining, txId, internalCargo...]; packetsRemaining counts down
// to 0 on the final packet. The reassembled frame is the concatenation of every packet's
// internalCargo — i.e. [opcode, txId, len, cargo..., crc] — ready for parsing.
// Port of PumpX2Kit `PacketReassembler`.
class PacketReassembler {
    private var _acc as Lang.ByteArray;
    private var _expectedTxId as Lang.Number or Null;

    function initialize() {
        _acc = []b;
        _expectedTxId = null;
    }

    // Ingests one raw notification packet. Returns the full frame when the final packet
    // (packetsRemaining == 0) arrives, otherwise null. Resets on malformed input (too short,
    // or a txId mismatch mid-stream).
    function ingest(raw as Lang.ByteArray) as Lang.ByteArray or Null {
        if (raw.size() < 2) {
            reset();
            return null;
        }
        var packetsRemaining = raw[0] & 0xFF;
        var txId = raw[1] & 0xFF;

        if (_expectedTxId != null && _expectedTxId != txId) {
            reset();
        }
        _expectedTxId = txId;
        _acc.addAll(raw.slice(2, null));

        if (packetsRemaining == 0) {
            var frame = _acc;
            reset();
            return frame;
        }
        return null;
    }

    function reset() as Void {
        _acc = []b;
        _expectedTxId = null;
    }
}
