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
            // VA-14: only remove the alert locally if the dismiss was actually DISPATCHED to the phone.
            // If offline (send returns false), the alert is still active on the pump — leave it in the
            // list and set the transient offline flag so AlertsListView shows "not cleared" instead of a
            // dishonest "No alerts". The phone's next authoritative statusRead reconciles either way.
            var dispatched = RemoteComm.send(RemoteComm.dismissAlert(RemoteComm.newRequestId(), _id, _kind));
            if (dispatched) {
                AppState.removeAlert(_id, _kind);   // optimistic local removal
            } else {
                AppState.alertDismissFailedOffline = true;
            }
            Ui.requestUpdate();
        }
        return true;
    }
}
