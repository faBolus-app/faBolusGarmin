using Toybox.Lang;
using Toybox.Test;

// Once an authoritative TERMINAL bolus outcome (delivered/cancelled/failed/
// unknown) is recorded, a LATE duplicate NON-terminal echo (delivering/cancelling) arriving with the SAME
// requestId must NOT regress it — a delayed/retransmitted bolusStatus echo used to overwrite the real
// result unconditionally. A later TERMINAL may still replace a terminal (delivered → cancelled-partial).
// isTerminalStatus + the guard in handle()'s bolusStatus branch are pure AppState logic (the BgService /
// HoldView that drive handle() reach Ui and are not deterministically drivable headlessly — they ARE
// test-compiled; test.jungle takes source/app wholesale, see its header), so we pin those directly.
// Style mirrors tests/OutcomeWatchdogTest.mc. AppState is compiled into the test binary.
module TerminalStatusGuardTest {

    function baseline() as Void {
        AppState.status = null;
        AppState.message = null;
        AppState.pendingRequestId = "rid-1";
        AppState.sawPhoneBolusing = false;
    }

    function echo(st as Lang.String) as Lang.Dictionary {
        return { "kind" => "bolusStatus", "requestId" => "rid-1", "status" => st };
    }

    // isTerminalStatus classifies the outcome set correctly (delivered/cancelled/failed/unknown terminal;
    // delivering/cancelling non-terminal; null not terminal).
    (:test)
    function terminalClassification(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppState.isTerminalStatus("delivered"), "delivered is terminal");
        Test.assertMessage(AppState.isTerminalStatus("cancelled"), "cancelled is terminal");
        Test.assertMessage(AppState.isTerminalStatus("failed"), "failed is terminal");
        Test.assertMessage(AppState.isTerminalStatus("unknown"), "unknown is a degraded-terminal");
        Test.assertMessage(!AppState.isTerminalStatus("delivering"), "delivering is non-terminal");
        Test.assertMessage(!AppState.isTerminalStatus("cancelling"), "cancelling is non-terminal");
        Test.assertMessage(!AppState.isTerminalStatus(null), "null is not terminal");
        return true;
    }

    // A late "delivering" echo (same requestId) after "delivered" must NOT regress the terminal outcome.
    (:test)
    function lateDeliveringDoesNotRegressDelivered(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(echo("delivering"));
        Test.assertEqualMessage(AppState.status, "delivering", "adopts the first non-terminal token");
        AppState.handle(echo("delivered"));
        Test.assertEqualMessage(AppState.status, "delivered", "advances to the terminal outcome");
        AppState.handle(echo("delivering"));   // late duplicate, same requestId
        Test.assertEqualMessage(AppState.status, "delivered", "a late delivering must NOT regress delivered");
        return true;
    }

    // A late "cancelling" after "cancelled" must not regress; a genuine later TERMINAL may replace a terminal.
    (:test)
    function laterTerminalMayReplaceTerminal(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivered";
        AppState.handle(echo("cancelling"));   // late non-terminal
        Test.assertEqualMessage(AppState.status, "delivered", "late cancelling does not regress delivered");
        AppState.handle(echo("cancelled"));    // a genuine later terminal (e.g. cancelled-partial)
        Test.assertEqualMessage(AppState.status, "cancelled", "a later TERMINAL may replace a terminal");
        return true;
    }

    // 'unknown' (the outcome watchdog's honest timeout) is terminal too — a late delivering must not undo it.
    (:test)
    function lateDeliveringDoesNotUndoUnknown(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "unknown";
        AppState.handle(echo("delivering"));
        Test.assertEqualMessage(AppState.status, "unknown", "a late delivering must NOT undo an unknown terminal");
        return true;
    }

    // A bolusStatus echo whose requestId does not match pendingRequestId never touches status.
    (:test)
    function mismatchedRequestIdIgnored(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.status = "delivered";
        AppState.handle({ "kind" => "bolusStatus", "requestId" => "OTHER", "status" => "delivering" });
        Test.assertEqualMessage(AppState.status, "delivered", "a non-matching requestId never touches status");
        return true;
    }
}
