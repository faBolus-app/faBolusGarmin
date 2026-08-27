using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// 19-03 (G-M1): AppState.handle() used to persist "staleSec" UNCONDITIONALLY on every statusRead reply,
// even when the reply OMITS glucoseStaleMinutes — clobbering the persisted staleness policy with the
// compile-time default (or whatever the in-memory field happened to hold) and incurring a flash write on
// every single poll regardless of whether the policy changed. This pins the fix: the write is now
// conditional on glucoseStaleMinutes being PRESENT (a parsed non-null minutes value) in the reply — an
// omitted key must leave the persisted policy untouched, exactly like every other absent-key guard in
// handle() (mirrors tests/ClockAnalogTest.mc's absentLeavesPersisted style). AppState is compiled into
// the test binary (test.jungle).
module StaleSecWriteHygieneTest {
    const KEY = "staleSec";

    // A minimal statusRead envelope carrying `extra`'s keys (each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // A reply OMITTING glucoseStaleMinutes must leave the persisted staleSec UNTOUCHED — a sentinel
    // (999) that differs from any real value proves the write didn't fire (rather than coincidentally
    // matching a default).
    (:test)
    function absentGlucoseStaleMinutesLeavesPersisted(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(KEY, 999);
        AppState.handle(statusRead({ "message" => "Connected" }));   // no glucoseStaleMinutes key
        Test.assertEqualMessage(Storage.getValue(KEY), 999, "absent glucoseStaleMinutes must not touch staleSec");
        return true;
    }

    // A reply INCLUDING a valid glucoseStaleMinutes still persists staleSec = minutes * 60 (the
    // present-key path is unchanged).
    (:test)
    function presentGlucoseStaleMinutesPersists(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(KEY, 999);
        AppState.handle(statusRead({ "glucoseStaleMinutes" => 10 }));
        Test.assertEqualMessage(Storage.getValue(KEY), 600, "present glucoseStaleMinutes=10 persists staleSec=600");
        return true;
    }

    // An out-of-range glucoseStaleMinutes (numRange rejects it, same as absent) must also leave the
    // persisted value untouched — mirrors the existing numRange guard's "reject ⇒ keep last" contract.
    (:test)
    function outOfRangeGlucoseStaleMinutesLeavesPersisted(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue(KEY, 999);
        AppState.handle(statusRead({ "glucoseStaleMinutes" => 0 }));   // numRange(1,720) rejects 0
        Test.assertEqualMessage(Storage.getValue(KEY), 999, "out-of-range glucoseStaleMinutes must not touch staleSec");
        return true;
    }
}
