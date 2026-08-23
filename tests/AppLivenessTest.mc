using Toybox.Lang;
using Toybox.Test;
using Toybox.Time;

// R2-03: RemoteComm.phoneReachable() is the raw BLE link (System.getDeviceSettings().phoneConnected) —
// NOT faBolus-app liveness. The paired iPhone can have faBolus killed, leaving the Deliver button enabled
// and sendBolusNow entering "delivering" into a void. The fix stamps `lastReplyEpoch` at the top of
// handle() on every inbound reply and gates canBolus() on appLive() (a reply within CONNECTION_STALE_SEC;
// 0 fails closed). pumpBolusAllowed() stays PURE (no liveness) so its tests remain valid. appLive()/the
// block label are pure AppState decisions, so we pin THOSE. canBolus() ANDs in phoneReachable() (not
// sim-controllable), so we lean on the deterministic facts — a false appLive() forces canBolus() false
// regardless of reachability (false && anything == false). Style mirrors tests/CanBolusTest.mc.
module AppLivenessTest {

    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Reset the liveness anchor + a bolus-eligible baseline so cases are order-independent.
    function baseline() as Void {
        AppState.status = null;
        AppState.readOnly = false;
        AppState.garminBolusEnabled = true;
        AppState.hostCanBolus = null;
        AppState.connection = "";
        AppState.lastReplyEpoch = 0;
    }

    // A fresh statusRead stamps the anchor ⇒ appLive() true.
    (:test)
    function freshHandleIsLive(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.handle(statusRead({ "message" => "Connected", "canBolus" => true,
                                     "garminBolusEnabled" => true }));
        Test.assertMessage(AppState.appLive(), "fresh reply ⇒ appLive true");
        return true;
    }

    // An aged reply (older than CONNECTION_STALE_SEC) ⇒ not live, and canBolus() fails closed regardless
    // of reachability, even though the pump/policy would otherwise permit it.
    (:test)
    function agedIsNotLiveAndBlocksBolus(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.garminBolusEnabled = true;
        AppState.readOnly = false;
        AppState.hostCanBolus = true;         // pump would allow
        AppState.connection = "Connected";
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        Test.assertMessage(!AppState.appLive(), "aged reply ⇒ not live");
        Test.assertMessage(!AppState.canBolus(), "not live ⇒ canBolus false (fail-closed)");
        return true;
    }

    // Cold launch (never replied, lastReplyEpoch == 0) ⇒ not live (fail-closed), canBolus false.
    (:test)
    function coldIsNotLive(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.lastReplyEpoch = 0;
        Test.assertMessage(!AppState.appLive(), "cold (0) ⇒ not live");
        Test.assertMessage(!AppState.canBolus(), "cold ⇒ canBolus false");
        return true;
    }

    // Reachable-but-stale ⇒ the block label is "Reconnecting…". Reachability isn't sim-controllable, so
    // assert deterministically for BOTH states (unreachable falls through to the phone reason first).
    (:test)
    function reconnectingLabelWhenReachableButStale(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.garminBolusEnabled = true;
        AppState.readOnly = false;
        AppState.hostCanBolus = true;
        AppState.connection = "Connected";
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 1);
        if (RemoteComm.phoneReachable()) {
            Test.assertEqualMessage(AppState.bolusBlockLabel(), "Reconnecting…",
                "reachable + stale ⇒ Reconnecting…");
        } else {
            Test.assertEqualMessage(AppState.bolusBlockLabel(), "Phone not connected",
                "unreachable ⇒ the phone reason wins first");
        }
        return true;
    }

    // A handle() refreshes liveness — a previously-stale anchor becomes live again after any reply.
    (:test)
    function handleRefreshesLiveness(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.lastReplyEpoch = Time.now().value() - (AppState.CONNECTION_STALE_SEC + 100);
        Test.assertMessage(!AppState.appLive(), "starts stale");
        AppState.handle(statusRead({ "message" => "Connected" }));
        Test.assertMessage(AppState.appLive(), "a statusRead refreshes liveness");
        return true;
    }

    // Liveness is stamped at the TOP of handle() before dispatch, so even a bolusStatus reply (no matching
    // pendingRequestId) proves the faBolus app is alive.
    (:test)
    function bolusStatusAlsoRefreshesLiveness(logger as Test.Logger) as Lang.Boolean {
        baseline();
        AppState.lastReplyEpoch = 0;
        AppState.handle({ "kind" => "bolusStatus", "requestId" => "no-match", "status" => "delivered" });
        Test.assertMessage(AppState.appLive(), "even a bolusStatus reply proves liveness");
        return true;
    }
}
