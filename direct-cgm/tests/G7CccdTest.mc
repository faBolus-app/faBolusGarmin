using Toybox.Lang;
using Toybox.Test;

// BLE-H1 + BLE-H2 coverage (Phase 21). Pure Toybox.Test for the paused direct-CGM (Dexcom G7) BLE
// client. Drives the Btle-free CccdSequencer directly (BLE-H1: one-op-in-flight serialization) and
// asserts the per-characteristic cccdValueFor mapping byte-for-byte (BLE-H2: indicate vs notify).
// CIQ BLE itself cannot be exercised in the simulator; the authoritative RUN is an owner sim step
// (monkeydo -t). Run with a --unit-test build.
module DirectCgm {
module G7CccdTest {

    // BLE-H1: the sequencer issues exactly ONE CCCD write at a time — the next is handed out only
    // after the prior descriptor-write ack, never three concurrent — and reports ready on exhaustion.
    (:test)
    function serializesOneOpInFlightThenReady(logger as Test.Logger) as Lang.Boolean {
        var ops = [{:id => 1}, {:id => 2}, {:id => 3}];
        var seq = new CccdSequencer(ops);

        Test.assertEqualMessage(seq.size(), 3, "3 ops");
        Test.assertEqualMessage(seq.issuedCount(), 0, "nothing issued yet");
        Test.assertMessage(!seq.isReady(), "not ready before any write");

        // Head op issued; exactly one in flight.
        var op1 = seq.next();
        Test.assertEqualMessage((op1 as Lang.Dictionary)[:id], 1, "first op is op 1");
        Test.assertEqualMessage(seq.issuedCount(), 1, "issued advances to 1");
        Test.assertMessage(seq.inFlight(), "op 1 in flight");

        // No second op is issued while op 1 is in flight (never concurrent).
        Test.assertMessage(seq.next() == null, "no second op while in flight");
        Test.assertEqualMessage(seq.issuedCount(), 1, "still only 1 issued (never concurrent)");

        // Ack op 1 -> op 2 issued.
        seq.ack();
        Test.assertMessage(!seq.inFlight(), "not in flight after ack");
        var op2 = seq.next();
        Test.assertEqualMessage((op2 as Lang.Dictionary)[:id], 2, "second op is op 2");
        Test.assertEqualMessage(seq.issuedCount(), 2, "issued advances to 2");

        // Ack op 2 -> op 3 issued.
        seq.ack();
        var op3 = seq.next();
        Test.assertEqualMessage((op3 as Lang.Dictionary)[:id], 3, "third op is op 3");
        Test.assertEqualMessage(seq.issuedCount(), 3, "issued advances to 3");

        // Ack op 3 -> exhausted + ready, no further writes.
        seq.ack();
        Test.assertMessage(seq.isReady(), "ready after last ack");
        Test.assertMessage(seq.next() == null, "no op issued after exhaustion");
        Test.assertEqualMessage(seq.issuedCount(), 3, "issued stays at 3 (no extra writes)");
        return true;
    }

    // BLE-H2: the CCCD value matches the characteristic property — indicate [0x02,0x00] for
    // CHAR_CTRL (glucose parsed from _ctrl) and notify [0x01,0x00] for CHAR_COMM / CHAR_BACK.
    (:test)
    function cccdValueMatchesCharacteristicProperty(logger as Test.Logger) as Lang.Boolean {
        var ctrl = G7BleClient.cccdValueFor(DirectCgm.KIND_CTRL);
        Test.assertEqualMessage(ctrl.size(), 2, "ctrl cccd is 2 bytes");
        Test.assertEqualMessage(ctrl[0], 0x02, "CHAR_CTRL byte0 = 0x02 (indicate)");
        Test.assertEqualMessage(ctrl[1], 0x00, "CHAR_CTRL byte1 = 0x00");

        var comm = G7BleClient.cccdValueFor(DirectCgm.KIND_COMM);
        Test.assertEqualMessage(comm[0], 0x01, "CHAR_COMM byte0 = 0x01 (notify)");
        Test.assertEqualMessage(comm[1], 0x00, "CHAR_COMM byte1 = 0x00");

        var back = G7BleClient.cccdValueFor(DirectCgm.KIND_BACK);
        Test.assertEqualMessage(back[0], 0x01, "CHAR_BACK byte0 = 0x01 (notify)");
        Test.assertEqualMessage(back[1], 0x00, "CHAR_BACK byte1 = 0x00");
        return true;
    }
}

}
