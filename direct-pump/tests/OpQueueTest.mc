using Toybox.Lang;
using Toybox.Test;

// BLE-M1 coverage (Phase 21). Drives the PURE OpQueue state machine directly — no Btle stack — to
// prove the op-queue FAILS CLOSED on a write failure instead of the old permanent-wedge bug
// (PumpBleClient's catch cleared _opInFlight but left the failed op at the head and never re-drove
// processNext()). The same terminal transition asserted here is what the BLE-M2 watchdogs fire.
// Run with a --unit-test build in the CIQ simulator.
module PumpX2 {
module OpQueueTest {

    // Normal path: three ops advance head-by-head to an empty, idle, non-terminal queue.
    (:test)
    function advancesThroughQueueThenIdle(logger as Test.Logger) as Lang.Boolean {
        var q = new OpQueue();
        q.enqueue({:id => 1});
        q.enqueue({:id => 2});
        q.enqueue({:id => 3});
        Test.assertEqualMessage(q.size(), 3, "3 enqueued");
        Test.assertMessage(q.hasWork(), "has work");
        Test.assertEqualMessage((q.peek() as Lang.Dictionary)[:id], 1, "head is op 1");

        q.markInFlight();
        Test.assertMessage(!q.hasWork(), "no work while in flight");
        q.onOpComplete();
        Test.assertEqualMessage((q.peek() as Lang.Dictionary)[:id], 2, "head advanced to op 2");

        q.markInFlight();
        q.onOpComplete();
        Test.assertEqualMessage((q.peek() as Lang.Dictionary)[:id], 3, "head advanced to op 3");

        q.markInFlight();
        q.onOpComplete();
        Test.assertEqualMessage(q.size(), 0, "queue empty after 3 completes");
        Test.assertMessage(!q.hasWork(), "idle: no work");
        Test.assertMessage(!q.terminalError(), "idle: not terminal");
        return true;
    }

    // FAIL CLOSED (the M1 fix): a failure with an op in flight aborts the queue AND latches a
    // terminal-error state — NEGATIVE path: it must NOT leave a stalled non-empty queue.
    (:test)
    function failClosedAbortsAndLatchesTerminal(logger as Test.Logger) as Lang.Boolean {
        var q = new OpQueue();
        q.enqueue({:id => 1});
        q.enqueue({:id => 2});
        q.markInFlight();       // op 1 in flight
        q.onOpFailed();         // write threw / watchdog fired
        Test.assertEqualMessage(q.size(), 0, "queue aborted on failure (no residual head)");
        Test.assertMessage(q.terminalError(), "terminal error latched (not merely idle)");
        Test.assertMessage(!q.hasWork(), "no work in terminal state");
        return true;
    }

    // The terminal flag is sticky: enqueue() after a failure does NOT silently resume delivery;
    // only an explicit reset() clears it.
    (:test)
    function terminalIsStickyUntilReset(logger as Test.Logger) as Lang.Boolean {
        var q = new OpQueue();
        q.enqueue({:id => 1});
        q.markInFlight();
        q.onOpFailed();
        q.enqueue({:id => 2});  // must not resume
        Test.assertMessage(q.terminalError(), "terminal sticky after enqueue");
        Test.assertMessage(!q.hasWork(), "enqueue does not resume a terminal queue");

        q.reset();
        Test.assertMessage(!q.terminalError(), "reset clears terminal");
        q.enqueue({:id => 3});
        Test.assertMessage(q.hasWork(), "drivable after reset + enqueue");
        Test.assertEqualMessage((q.peek() as Lang.Dictionary)[:id], 3, "head is op 3 after reset");
        return true;
    }
}

}
