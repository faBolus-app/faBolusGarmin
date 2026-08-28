using Toybox.Lang;

// BLE-H1 (Phase 21). Pure, Btle-free sequencer for the G7 CCCD subscription writes. CIQ GATT allows
// exactly ONE operation in flight at a time, so the three CCCD descriptor writes (_ctrl/_back/_comm)
// must be issued one-at-a-time, each only after the prior descriptor-write ack — NOT back-to-back.
// This mirrors the direct-pump OpQueue idea but is SELF-CONTAINED in direct-cgm (separate paused
// engine, separate jungle — no cross-engine coupling).
//
// Data-only: no Btle references, so G7CccdTest drives it directly. The ops themselves are opaque
// (the client stores a Dictionary describing the Btle descriptor + the CCCD value to write).
//
// Model: next() hands out the head op and marks it in flight; it returns null while an op is in
// flight OR the list is exhausted. ack() (fed by onDescriptorWrite success) clears the in-flight
// flag and advances the cursor. issuedCount() advances by exactly one per next() that hands out an
// op, so it can never exceed the number of acks + 1 (one in flight) — i.e. never three concurrent.
module DirectCgm {
    class CccdSequencer {
        private var _ops as Lang.Array;
        private var _cursor as Lang.Number = 0;     // index of the next op to issue
        private var _issued as Lang.Number = 0;      // count of ops handed out by next()
        private var _inFlight as Lang.Boolean = false;

        function initialize(ops as Lang.Array) {
            _ops = ops;
        }

        // The op to issue NOW, or null if an op is already in flight or the list is exhausted.
        // Hands out at most one op until the current one is acked (one-op-in-flight invariant).
        function next() {
            if (_inFlight) { return null; }
            if (_cursor >= _ops.size()) { return null; }
            var op = _ops[_cursor];
            _inFlight = true;
            _issued += 1;
            return op;
        }

        // onDescriptorWrite ack for the in-flight op: clear the in-flight flag and advance the cursor
        // so the NEXT next() hands out the following op.
        function ack() as Void {
            if (!_inFlight) { return; }
            _inFlight = false;
            _cursor += 1;
        }

        // Number of ops handed out by next() so far (in flight + completed).
        function issuedCount() as Lang.Number {
            return _issued;
        }

        // Whether an op is currently in flight (issued but not yet acked).
        function inFlight() as Lang.Boolean {
            return _inFlight;
        }

        // Whether every op has been acked (subscription complete). Exhausted with nothing in flight.
        function isReady() as Lang.Boolean {
            return !_inFlight && _cursor >= _ops.size();
        }

        // Total number of ops in the sequence.
        function size() as Lang.Number {
            return _ops.size();
        }
    }
}
