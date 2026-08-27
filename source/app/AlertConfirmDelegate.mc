using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Confirmation shown when a new pump alert arrives (an actionable "notification"): choosing Yes
// clears that alert via the phone. Choosing No dismisses the prompt (the alert stays in the list).
class AlertConfirmDelegate extends Ui.ConfirmationDelegate {
    private var _id as Lang.Number;
    private var _kind as Lang.Number;

    function initialize(id as Lang.Number, kind as Lang.Number) {
        ConfirmationDelegate.initialize();
        _id = id; _kind = kind;
    }

    function onResponse(response) as Lang.Boolean {
        if (response == Ui.CONFIRM_YES) {
            // CX-G-08 (14-09, authenticated-ack-only + capability-gated 14-08 fallback — owner decision,
            // OWNER-DECISIONS.md Plan 14-09, supersedes the 14-08-era comment this replaces). Mint + RETAIN
            // the requestId ONCE (with a per-identity generation) into a persisted RETRY/PENDING entry AND
            // a persisted {id,kind,title} DISPLAY provisional (AppState.beginDismiss) — a genuinely NEW
            // wearer occurrence always mints fresh and replaces any prior entry for the SAME identity.
            // Either way the alert stays PROVISIONAL, never optimistically removed here: it is cleared
            // ONLY by a correlated `dismissAck` (ack-mode, supportsDismissAck==true) or by the phone's next
            // authoritative statusRead (the 14-08 fallback, capability absent/false — AppState.handle() →
            // reconcileDismissSent(), still fed by markDismissSent below). If offline (send returns
            // false), the alert is still active on the pump — leave it in the list and set the transient
            // offline flag so AlertsListView shows "not cleared" instead of a dishonest "No alerts".
            var title = AppState.alertTitleFor(_id, _kind);
            var reqId = AppState.beginDismiss(_id, _kind, title);
            var dispatched = RemoteComm.send(RemoteComm.dismissAlert(reqId, _id, _kind));
            if (dispatched) {
                AppState.markDismissSent(_id, _kind);   // 14-08 fallback bookkeeping (still needed absent/false)
            } else {
                AppState.alertDismissFailedOffline = true;
            }
            Ui.requestUpdate();
        }
        return true;
    }
}
