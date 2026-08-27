using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// 19-03 (G-M1): pins the ROUTINE request-id mint (statusRead / statusReadFresh / dismissAlert — every
// hot-path call site EXCEPT the bolus/resume dose-authorizing send). RemoteComm.newRequestId() (VA-17,
// see RequestIdTest.mc) does a Storage.get+set on EVERY mint; the routine callers fire every ~15s
// (pollTick), on every View.onShow, and on every wearer dismiss-confirm — turning VA-17's durable
// persistence into hot-path flash churn with no corresponding benefit, since only the DOSE-AUTHORIZING
// (bolus/resume) id is ever ledgered by the host for (peer,requestId) dedup. The routine mint below is
// an in-memory counter folded with the wall clock + boot timer for cross-process uniqueness — it MUST
// NEVER touch the persisted "reqSeq" sequence, which stays reserved for the DURABLE mint's reboot
// invariant. RemoteComm is compiled into the test binary (test.jungle). Style mirrors RequestIdTest.mc.
module RoutineRequestIdTest {

    // Two successive routine ids differ (the in-memory counter guarantees it within a process/second).
    (:test)
    function twoRoutineIdsDiffer(logger as Test.Logger) as Lang.Boolean {
        var a = RemoteComm.newRoutineRequestId();
        var b = RemoteComm.newRoutineRequestId();
        Test.assertMessage(!a.equals(b), "two successive routine ids must differ");
        return true;
    }

    // A routine mint performs NO Storage read/write: seed "reqSeq" to 5, mint TWO routine ids, assert
    // "reqSeq" is UNCHANGED (still 5) — the durable sequence is reserved for the durable (bolus/resume)
    // mint alone.
    (:test)
    function routineMintDoesNotTouchReqSeq(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue("reqSeq", 5);
        var a = RemoteComm.newRoutineRequestId();
        var b = RemoteComm.newRoutineRequestId();
        Test.assertMessage(!a.equals(b), "two successive routine ids must differ");
        Test.assertEqualMessage(Storage.getValue("reqSeq"), 5, "routine mint must not advance reqSeq");
        return true;
    }

    // A routine id and a durable id minted in the same second are distinct (folded wall-clock +
    // boot-timer + separate counters/format never collide).
    (:test)
    function routineAndDurableIdsDiffer(logger as Test.Logger) as Lang.Boolean {
        var routine = RemoteComm.newRoutineRequestId();
        var durable = RemoteComm.newRequestId();
        Test.assertMessage(!routine.equals(durable), "routine and durable ids must be distinct");
        return true;
    }
}
