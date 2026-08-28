using Toybox.Lang;

// Pure, Btle-free op-queue state machine for the serialized single-in-flight BLE write model
// (CIQ GATT allows one operation in flight at a time — see PumpBleClient's serialized queue).
// Extracted so the FAIL-CLOSED transition (BLE-M1) is unit-testable WITHOUT a live BLE stack:
// a write exception — or a watchdog expiry (BLE-M2) — calls onOpFailed(), which aborts the whole
// queue AND latches a sticky terminal-error state. This replaces the old bug where a failed write
// cleared _opInFlight, LEFT the failed op at the head, and never re-drove processNext() — a
// permanent wedge (stalled non-empty queue with nothing re-driving it), i.e. NOT fail-safe.
//
// Data-only: no Btle references, so OpQueueTest drives it directly. The ops themselves are opaque
// (the client stores a Dictionary describing the Btle characteristic/descriptor write).
module PumpX2 {
class OpQueue {
    private var _ops as Lang.Array;
    private var _inFlight as Lang.Boolean = false;
    private var _terminal as Lang.Boolean = false;

    function initialize() {
        _ops = [];
    }

    // Append an op (opaque to the queue).
    function enqueue(op) as Void {
        _ops.add(op);
    }

    // True iff there is a pending op that may be driven NOW: not terminal, nothing in flight, and
    // at least one queued op. In the terminal state this stays false even after enqueue(), so a
    // failed queue never silently resumes delivery.
    function hasWork() as Lang.Boolean {
        return !_terminal && !_inFlight && _ops.size() > 0;
    }

    // The head op without removing it, or null if empty.
    function peek() {
        if (_ops.size() == 0) { return null; }
        return _ops[0];
    }

    // Mark the head op as in flight (a Btle request has been issued for it).
    function markInFlight() as Void {
        _inFlight = true;
    }

    // The in-flight op completed successfully: drop the head and clear the in-flight flag so the
    // next op may be driven.
    function onOpComplete() as Void {
        if (_ops.size() > 0) { _ops = _ops.slice(1, null); }
        _inFlight = false;
    }

    // FAIL CLOSED (BLE-M1 / BLE-M2): a write threw or a watchdog fired. Abort the WHOLE queue and
    // latch a sticky terminal-error state — no residual head, hasWork() stays false, and enqueue()
    // cannot resume delivery until reset() is called explicitly.
    function onOpFailed() as Void {
        _ops = [];
        _inFlight = false;
        _terminal = true;
    }

    // Whether the queue is in the latched terminal-error state.
    function terminalError() as Lang.Boolean {
        return _terminal;
    }

    // Number of queued ops (head + pending).
    function size() as Lang.Number {
        return _ops.size();
    }

    // Explicit recovery: clear all state back to a fresh, drivable queue.
    function reset() as Void {
        _ops = [];
        _inFlight = false;
        _terminal = false;
    }
}

}
