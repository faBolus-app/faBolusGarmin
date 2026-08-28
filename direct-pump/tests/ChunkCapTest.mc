using Toybox.Lang;
using Toybox.Test;

// BLE-C1 coverage (Phase 21). Connect IQ's Characteristic.requestWrite() rejects any value
// > 20 bytes with InvalidRequestException (no long-write, no MTU negotiation — see
// direct-pump/engine/protocol/Ble.mc PREFERRED_MTU note). Each Packet.build() prepends a
// 2-byte [packetsRemaining,transactionId] header, so every chunk must be <= 18 (2 + 18 = 20).
//
// These tests prove Packetize.packetize caps EVERY signed CONTROL write at <= 20 bytes and that
// the reassembled application frame (framed message + CRC-16) is byte-identical regardless of
// segmentation — i.e. the cap changes only BLE packet boundaries, never the message the pump
// reassembles. Run with a --unit-test build in the CIQ simulator.
//
// Signing constants mirror tests/ParityTest.mc / tools/gen_golden.sh so the signed frames match
// the proven oracle vectors byte-for-byte.
module PumpX2 {
module ChunkCapTest {
    const PAIRING_CODE = "6VeDeRAL5DCigGw2";
    const PUMP_TIME = 461589180;

    // CIQ single-write ceiling and the derived chunk ceiling (build() adds a 2-byte header).
    const MAX_WRITE = 20;

    function key() as Lang.ByteArray {
        return Bytes.fromAscii(PAIRING_CODE);
    }

    // Fresh instances of the five signed CONTROL requests, each with its ParityTest txId.
    // [message, txId]
    function signedCases() as Lang.Array {
        return [
            [new BolusPermissionRequest(), 0],
            [new CancelBolusRequest(10650), 3],
            [new BolusPermissionReleaseRequest(10650), 4],
            [new InitiateBolusRequest(1000, 42, 1, 0, 0, 0, 0, 0), 9],
            [new DismissNotificationRequest(10, 1, false), 5],
        ];
    }

    // Reassembles a packet array back into the full framed message + CRC.
    function reassemble(packets as Lang.Array<Packet>) as Lang.ByteArray or Null {
        var ra = new PacketReassembler();
        var frame = null;
        for (var i = 0; i < packets.size(); i++) {
            frame = ra.ingest(packets[i].build());
        }
        return frame;
    }

    // Every packet for each signed CONTROL request must build to <= 20 bytes on the default
    // (null -> determineMaxChunkSize) path. With the retired CONTROL_MAX_CHUNK_SIZE=40 this
    // FAILED (InitiateBolus first write = 42 B, BolusPermission = 31 B) — the RED proof.
    (:test)
    function controlWritesAreWithin20Bytes(logger as Test.Logger) as Lang.Boolean {
        var cs = signedCases();
        for (var i = 0; i < cs.size(); i++) {
            var msg = cs[i][0] as Message;
            var txId = cs[i][1] as Lang.Number;
            var packets = Packetize.packetize(msg, key(), txId, PUMP_TIME, true, null);
            for (var p = 0; p < packets.size(); p++) {
                var sz = packets[p].build().size();
                Test.assertMessage(
                    sz <= MAX_WRITE,
                    "case " + i + " packet " + p + " = " + sz + " bytes (> " + MAX_WRITE + ")");
            }
        }
        return true;
    }

    // The cap must be UNCONDITIONAL: an explicit oversized maxChunkSize=40 override is clamped so
    // no packet exceeds 20 bytes (not just the null-derived path).
    (:test)
    function oversizedOverrideIsClamped(logger as Test.Logger) as Lang.Boolean {
        var cs = signedCases();
        for (var i = 0; i < cs.size(); i++) {
            var msg = cs[i][0] as Message;
            var txId = cs[i][1] as Lang.Number;
            var packets = Packetize.packetize(msg, key(), txId, PUMP_TIME, true, 40);
            for (var p = 0; p < packets.size(); p++) {
                var sz = packets[p].build().size();
                Test.assertMessage(
                    sz <= MAX_WRITE,
                    "override case " + i + " packet " + p + " = " + sz + " bytes (> " + MAX_WRITE + ")");
            }
        }
        return true;
    }

    // WR-03: the cap is TWO-SIDED. A non-positive maxChunkSize override (0 or negative) must NOT
    // slip past the clamp and produce a single > 20-byte write (the old one-sided clamp let a 0/neg
    // override fall through to partition()'s "one giant chunk" branch). Assert every packet stays
    // <= 20 bytes for both a 0 and a negative override.
    (:test)
    function nonPositiveOverrideIsClamped(logger as Test.Logger) as Lang.Boolean {
        var overrides = [0, -1, -18];
        var cs = signedCases();
        for (var o = 0; o < overrides.size(); o++) {
            var ov = overrides[o] as Lang.Number;
            for (var i = 0; i < cs.size(); i++) {
                var msg = cs[i][0] as Message;
                var txId = cs[i][1] as Lang.Number;
                var packets = Packetize.packetize(msg, key(), txId, PUMP_TIME, true, ov);
                for (var p = 0; p < packets.size(); p++) {
                    var sz = packets[p].build().size();
                    Test.assertMessage(
                        sz <= MAX_WRITE,
                        "override " + ov + " case " + i + " packet " + p + " = " + sz + " bytes (> " + MAX_WRITE + ")");
                }
            }
        }
        return true;
    }

    // Reassembly invariance: the reassembled frame is chunk-size-INDEPENDENT. For each message the
    // capped (default) reassembly must equal (a) the reassembly of the clamped 40-override path and
    // (b) the reassembly of a genuinely different, finer segmentation (chunkSize=6). Since the cap
    // is unconditional a >18 override collapses to the same 18-byte segmentation, so the finer
    // chunking is what actually varies packet boundaries — proving the pump reassembles the
    // identical framed message + CRC no matter how the bytes were partitioned.
    (:test)
    function reassemblyIsChunkSizeInvariant(logger as Test.Logger) as Lang.Boolean {
        var cs = signedCases();
        for (var i = 0; i < cs.size(); i++) {
            var msg = cs[i][0] as Message;
            var txId = cs[i][1] as Lang.Number;

            var fCapped = reassemble(Packetize.packetize(msg, key(), txId, PUMP_TIME, true, null));
            var fOver   = reassemble(Packetize.packetize(msg, key(), txId, PUMP_TIME, true, 40));
            var fFine   = reassemble(Packetize.packetize(msg, key(), txId, PUMP_TIME, true, 6));

            Test.assertMessage(fCapped != null, "case " + i + " capped frame null");
            Test.assertMessage(fFine != null, "case " + i + " fine frame null");
            Test.assertEqualMessage(
                Hex.encode(fCapped), Hex.encode(fOver),
                "case " + i + " clamped-override frame differs");
            Test.assertEqualMessage(
                Hex.encode(fCapped), Hex.encode(fFine),
                "case " + i + " finer-segmentation frame differs");
        }
        return true;
    }
}

}
