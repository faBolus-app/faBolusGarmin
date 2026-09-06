using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Confirmation shown when a new app-GENERATED (faBolus's own) alert arrives on the wrist — a dropped
// pump link, a failover-CGM low, an unresolved-dose disclosure. Unlike a pump alert there is nothing to
// clear on the pump: the phone owns the condition and its resolution and stays the authoritative alerting
// surface, so the wrist card is purely informational — either response just dismisses it.
class AppOwnAlertDelegate extends Ui.ConfirmationDelegate {
    function initialize() { ConfirmationDelegate.initialize(); }
    function onResponse(response) as Lang.Boolean { return true; }
}
