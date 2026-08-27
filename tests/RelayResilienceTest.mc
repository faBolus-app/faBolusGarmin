using Toybox.Lang;
using Toybox.Test;

// 13-04 (CX-G-12 prerequisite + C5-01/CX-G-05 + C5-02): FaBolusApp.mc/HeartRateRelay.mc/EatingRelay.mc
// are now compiled into the test binary (see test.jungle), so these exercise the REAL shipping pollTick
// loop and relay transmit paths, not a stand-in.
//
// C5-01/CX-G-05: a throw from _hr.emitIfDue() (its Comm.transmit) used to happen BEFORE
// scheduleNextPoll() at FaBolusApp.pollTick — permanently halting the one-shot foreground poll loop,
// since scheduleNextPoll() (owned by FaBolusApp, NOT HeartRateRelay) is the loop's only re-arm path.
// Test 1 proves the guard lives at pollTick: scheduleNextPoll() runs even when the injected HR relay
// double throws.
//
// C5-02: EatingRelay has its OWN timer lifecycle (beginBurst/endBurst), independent of the pollTick
// loop, so pollTick's guarantee doesn't cover it — its own Comm.transmit (in onWindow) needs an
// independent guard. Test 2 proves a transmit throw doesn't strand/crash the relay (it stays running).
//
// Test 3 proves the fix doesn't double-schedule on the ordinary success path.
module RelayResilienceTest {

    // Local Exception subclass — mirrors direct-pump's throw idiom (see ResponseParseException,
    // JpakeAuthException) — used purely to simulate a relay transmit failure.
    class RelayTestException extends Lang.Exception {
        function initialize() { Exception.initialize(); }
    }

    // HR relay double whose emitIfDue() always throws — simulates a Comm.transmit failure without a
    // real BLE transport.
    class ThrowingHeartRateRelay extends HeartRateRelay {
        function initialize() { HeartRateRelay.initialize(); }
        function emitIfDue() as Void { throw new RelayTestException(); }
    }

    // EatingRelay double whose transmitWindow() always throws — same idea, isolated to the seam
    // EatingRelay.onWindow() calls (see EatingRelay.mc).
    class ThrowingEatingRelay extends EatingRelay {
        function initialize() { EatingRelay.initialize(); }
        function transmitWindow(msg as Lang.Dictionary) as Void { throw new RelayTestException(); }
    }

    // Test 1 (C5-01/CX-G-05): scheduleNextPoll() STILL runs when _hr.emitIfDue() throws inside
    // pollTick() — the one-shot foreground poll loop is not permanently halted.
    (:test)
    function pollTickSchedulesDespiteEmitIfDueThrow(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        app.setHrRelay(new ThrowingHeartRateRelay());
        Test.assertEqualMessage(app.scheduleCount(), 0, "no poll scheduled yet");
        Test.assertEqualMessage(app.pollGuardFailureCount(), 0, "no guard failure recorded yet");
        app.pollTick();   // would throw uncaught (failing this test) if the guard were missing
        Test.assertEqualMessage(app.scheduleCount(), 1,
            "scheduleNextPoll() ran exactly once despite emitIfDue() throwing");
        // 13-LW-01: the guard that used to silently swallow this throw now counts it.
        Test.assertEqualMessage(app.pollGuardFailureCount(), 1,
            "emitIfDue()'s throw is now observable, not silently swallowed");
        return true;
    }

    // Test 2 (C5-02): a transmit throw inside EatingRelay.onWindow() does not strand/crash the relay —
    // it stays running, i.e. its OWN (separate) timer lifecycle is not disturbed by the throw.
    (:test)
    function eatingRelayTransmitThrowDoesNotStrandItsTimer(logger as Test.Logger) as Lang.Boolean {
        var relay = new ThrowingEatingRelay();
        relay.start();
        Test.assertMessage(relay.isRunning(), "relay is running after start()");
        Test.assertEqualMessage(relay.onWindowGuardFailureCount(), 0, "no guard failure recorded yet");
        relay.onWindow([]);   // would throw uncaught (failing this test) if the guard were missing
        Test.assertMessage(relay.isRunning(),
            "relay still running after a transmit throw — its own timer was not stranded");
        // 13-LW-01: the guard that used to silently swallow this throw now counts it.
        Test.assertEqualMessage(relay.onWindowGuardFailureCount(), 1,
            "onWindow()'s transmit throw is now observable, not silently swallowed");
        relay.stop();
        return true;
    }

    // Test 3: a successful pollTick (no throw) still schedules the next poll exactly once — no
    // double-schedule on the ordinary success path.
    (:test)
    function pollTickSchedulesExactlyOnceOnSuccess(logger as Test.Logger) as Lang.Boolean {
        var app = new FaBolusApp();
        Test.assertEqualMessage(app.scheduleCount(), 0, "no poll scheduled yet");
        app.pollTick();
        Test.assertEqualMessage(app.scheduleCount(), 1, "scheduleNextPoll() ran exactly once");
        return true;
    }
}
