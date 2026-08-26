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
            // CX-G-08 (statusRead-reconcile — owner decision, OWNER-DECISIONS.md Plan 14-08): there is
            // NO authenticated dismiss-ack path today (no retained request id, no ack state machine in
            // AppState.handle()), so a DISPATCHED send (RemoteComm.send returning true) is only proof the
            // dismiss was SENT, never proof the pump actually cleared it. Optimistically removing the
            // alert here (the old behavior) could suppress an alert that never really cleared. Instead,
            // flag it PROVISIONAL — the alert stays visible/active until the phone's next authoritative
            // statusRead reconciles it away (AppState.handle() → reconcileDismissSent()). If offline (send
            // returns false), the alert is still active on the pump — leave it in the list and set the
            // transient offline flag so AlertsListView shows "not cleared" instead of a dishonest
            // "No alerts" (unchanged from before).
            var dispatched = RemoteComm.send(RemoteComm.dismissAlert(RemoteComm.newRequestId(), _id, _kind));
            if (dispatched) {
                AppState.markDismissSent(_id, _kind);   // provisional — NOT removed until statusRead proves it absent
            } else {
                AppState.alertDismissFailedOffline = true;
            }
            Ui.requestUpdate();
        }
        return true;
    }
}
