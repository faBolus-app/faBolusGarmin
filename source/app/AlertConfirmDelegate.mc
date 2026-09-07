using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Confirmation shown when a new pump alert arrives (an actionable "notification"): choosing Yes
// clears that alert via the phone. Choosing No dismisses the prompt (the alert stays in the list).
class AlertConfirmDelegate extends Ui.ConfirmationDelegate {
    private var _id as Lang.Number;
    private var _kind as Lang.Number;
    // Whether the alert being confirmed is a non-dismissable malfunction — the source discriminator carried
    // back on the dismiss so the phone resolves the exact one when an alarm and a malfunction collide.
    private var _isMalfunction as Lang.Boolean or Null;

    function initialize(id as Lang.Number, kind as Lang.Number, isMalfunction as Lang.Boolean or Null) {
        ConfirmationDelegate.initialize();
        _id = id; _kind = kind; _isMalfunction = isMalfunction;
    }

    function onResponse(response) as Lang.Boolean {
        if (response == Ui.CONFIRM_YES) {
            // Authenticated-ack-only, with a capability-gated statusRead-reconcile fallback (owner
            // decision). Mint + RETAIN the requestId ONCE (with a per-identity generation) into a
            // persisted RETRY/PENDING entry AND a persisted {id,kind,title} DISPLAY provisional
            // (AppState.beginDismiss) — a genuinely NEW wearer occurrence always mints fresh and
            // replaces any prior entry for the SAME identity.
            // Either way the alert stays PROVISIONAL, never optimistically removed here: it is cleared
            // ONLY by a correlated `dismissAck` (ack-mode, supportsDismissAck==true) or by the phone's next
            // authoritative statusRead (the statusRead-reconcile fallback, capability absent/false —
            // AppState.handle() → reconcileDismissSent(), still fed by markDismissSent below). If offline
            // (send returns false), the alert is still active on the pump — leave it in the list and set
            // the transient offline flag so AlertsListView shows "not cleared" instead of a dishonest
            // "No alerts".
            var title = AppState.alertTitleFor(_id, _kind);
            var reqId = AppState.beginDismiss(_id, _kind, title, _isMalfunction);
            var dispatched = RemoteComm.send(RemoteComm.dismissAlert(reqId, _id, _kind, _isMalfunction));
            if (dispatched) {
                AppState.markDismissSent(_id, _kind);   // reconcile-fallback bookkeeping (still needed absent/false)
            } else {
                AppState.alertDismissFailedOffline = true;
            }
            Ui.requestUpdate();
        }
        return true;
    }
}
