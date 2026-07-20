using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Input for the direct-connect debug screen. A tap attempts direct-to-pump mode using the secret
// shared from the phone (keyShare) and registers for live status updates; swipes navigate.
class DirectDebugDelegate extends Ui.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onNextPage() as Lang.Boolean { return Nav.goNext("direct"); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev("direct"); }
    function onBack() as Lang.Boolean { return Nav.goPrev("direct"); }

    // venu3s: taps arrive as onSelect (no coords) or onTap(coords); handle both.
    function onSelect() as Lang.Boolean { return connect(); }
    function onTap(evt as Ui.ClickEvent) as Lang.Boolean { return connect(); }

    private function connect() as Lang.Boolean {
        if (RemoteComm.enableDirectFromStorage()) {
            RemoteComm.setDirectStatusListener(method(:onStatus));
            // Exercise an authenticated read to prove resume worked end to end.
            RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRequestId()));
        }
        Ui.requestUpdate();
        return true;
    }

    function onStatus() as Void {
        Ui.requestUpdate();
    }
}
