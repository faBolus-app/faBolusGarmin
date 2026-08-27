using Toybox.Lang;
using Toybox.Test;
using Toybox.Application.Storage;

// VA-17 (V-Audit): RemoteComm.newRequestId() must be unique across a reboot / a background↔foreground
// process split / a System.getTimer() rollover. The core fix is a PERSISTED monotonic sequence
// ("reqSeq" in Application.Storage): read the last value, advance it, and persist it BEFORE composing
// the id. These pin (a) two successive ids differ and (b) the reboot invariant — a persisted seed of 5
// yields the next counter segment 6 even though the in-process register resets on reboot. RemoteComm is
// compiled into the test binary (test.jungle). Style mirrors tests/SentAtTest.mc.
//
// 19-03 (G-M1): newRequestId() is now specifically the DURABLE mint — the ONLY caller left is the
// dose-authorizing bolus/resume send (AppState.sendBolusNow). Every other (routine) hot-path mint
// (statusRead/HR/dismissAlert) moved to RemoteComm.newRoutineRequestId(), which performs NO Storage
// read/write — see tests/RoutineRequestIdTest.mc. This file's invariants (reboot persistence, "reqSeq"
// advance) are unchanged and now pin the durable path exclusively.
module RequestIdTest {

    // Two successive ids differ (the monotonic counter guarantees it even within one process/second).
    (:test)
    function twoIdsDiffer(logger as Test.Logger) as Lang.Boolean {
        var a = RemoteComm.newRequestId();
        var b = RemoteComm.newRequestId();
        Test.assertMessage(!a.equals(b), "two successive request ids must differ");
        return true;
    }

    // Reboot invariant: seed the persisted sequence to 5 (simulating a value that survived a reboot
    // while the in-process module counter reset to 0) ⇒ the very next mint advances it to 6, both in the
    // persisted store and in the id's counter segment. The composite id is `<wallSec>-<counter>-<timer>`;
    // <wallSec>/<timer> contain no '-', so "-6-" can only be the counter delimiter.
    (:test)
    function storageSeedFiveGivesSix(logger as Test.Logger) as Lang.Boolean {
        Storage.setValue("reqSeq", 5);
        var id = RemoteComm.newRequestId();
        Test.assertEqualMessage(RemoteComm._counter, 6, "seed 5 ⇒ next counter is 6");
        Test.assertEqualMessage(Storage.getValue("reqSeq"), 6, "advanced sequence persisted as 6");
        Test.assertMessage(id.find("-6-") != null, "id's counter segment is 6");
        return true;
    }

    // A fresh/absent sequence (no prior reqSeq) starts the counter at 1 (0-if-absent, then +=1).
    (:test)
    function absentSeqStartsAtOne(logger as Test.Logger) as Lang.Boolean {
        Storage.deleteValue("reqSeq");
        var id = RemoteComm.newRequestId();
        Test.assertEqualMessage(RemoteComm._counter, 1, "absent seed ⇒ first counter is 1");
        Test.assertMessage(id.find("-1-") != null, "id's counter segment is 1");
        return true;
    }
}
