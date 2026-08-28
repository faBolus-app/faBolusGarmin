using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Transient, NON-acknowledgment feedback via WatchUi.showToast (API 3.4.0, venu3s) — a
// lighter surface than a full view push for status-only messages. Capability-guarded (`Ui has :showToast`)
// with a graceful no-op fallback on older firmware, where the call site's existing AppState.message already
// carries any persistent error. A toast NEVER replaces an acknowledgment-required surface — a dose confirm
// or an alert-clear keeps its full Ui.Confirmation. Display feedback only: no toast path touches the
// dose/confirm interlock (C5).
module Toast {
    const CANCEL_SENT = "Cancel sent";
    const CANCEL_FAILED = "Not sent — try again";

    // Pure, unit-testable: the transient toast string for a cancel-dispatch outcome. Honest wording — the
    // cancel path has no auto-retry, so a failed dispatch prompts a manual retry (matching the persistent
    // AppState.message "Cancel failed — try again." the call site also sets).
    function cancelFeedback(dispatched as Lang.Boolean) as Lang.String {
        return dispatched ? CANCEL_SENT : CANCEL_FAILED;
    }

    // Show transient feedback via WatchUi.showToast when supported; else a no-op (graceful degrade — the
    // caller's AppState.message surface still conveys any persistent state). Never a crash on older firmware.
    function show(msg as Lang.String) as Void {
        if (Ui has :showToast) {
            Ui.showToast(msg, null);
        }
    }
}
