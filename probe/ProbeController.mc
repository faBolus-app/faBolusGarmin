using Toybox.Lang;
using Toybox.WatchUi;

// Milestone 0 handoff-resume probe. Drives a *fresh* watch BLE bond to the pump and then attempts
// JPAKE resume (rounds 3-4 only) using a derivedSecret shared from the phone — WITHOUT a new
// 6-digit code. Reports exactly how far it gets, so we learn whether a shared-key sequential
// handoff is possible on this pump. Experimental.
//
// BEFORE BUILDING: paste the phone's derivedSecret hex into DERIVED_SECRET_HEX below (see the
// handoff-test instructions for how to read it off the iPhone app).
//
// Outcome shown on screen:
//   "HANDOFF PASS"  bonded (fresh bond) + resumed with the shared secret + an authenticated read
//                   succeeded  => shared-key sequential handoff is viable.
//   "RESUME FAILED" bonded + subscribed, but the pump rejected the resume handshake => the pump
//                   requires the original central / a full re-pair (no shared-key handoff).
//   stuck before "resuming" (scanning/pairing/bonded) or the pump shows a pairing code => the
//                   pump forced a fresh bond/full pairing => no seamless handoff.
class ProbeController {
    // <-- PASTE the phone's derivedSecret hex here before building (e.g. "aabbcc...", 64 hex chars).
    const DERIVED_SECRET_HEX = "";

    public var status as Lang.String = "idle";
    public var detail as Lang.String = "";

    private var _client as PumpX2.PumpBleClient;
    private var _resume as PumpX2.ResumeCoordinator or Null;
    private var _authed as Lang.Boolean = false;

    function initialize() {
        _client = new PumpX2.PumpBleClient();
        _client.onStateChange = method(:onState);
        _client.onErrorCb = method(:onError);
        _client.onReady = method(:onReady);
        _client.onFrame = method(:onFrame);
    }

    function start() as Void {
        if (DERIVED_SECRET_HEX.length() < 2) {
            status = "set DERIVED_SECRET_HEX";
            refresh();
            return;
        }
        status = "opening";
        _client.open();
        refresh();
    }

    // Lifecycle progress: registering profile / scanning / pairing / connected; bonding; subscribing.
    function onState(text as Lang.String) as Void {
        status = text;
        refresh();
    }

    function onError(text as Lang.String) as Void {
        status = "ERROR";
        detail = text;
        refresh();
    }

    // Bonded + subscribed: begin the resume handshake (rounds 3-4) on AUTHORIZATION.
    function onReady() as Void {
        status = "resuming (rounds 3-4)";
        _resume = new PumpX2.ResumeCoordinator(PumpX2.Hex.decode(DERIVED_SECRET_HEX), 0, null);
        _client.send(_resume.start(), []b, 0, false);
        refresh();
    }

    function onFrame(charEnum as Lang.Number, frame as Lang.ByteArray) as Void {
        if (charEnum == PumpX2.Ble.CHAR_AUTHORIZATION) {
            handleAuth(frame);
            return;
        }
        // An authenticated read replied -> resume truly worked end to end.
        try {
            var m = PumpX2.ResponseParser.parse(frame);
            status = "HANDOFF PASS";
            detail = "authed read op=" + (m.opCode & 0xFF).format("%02X");
        } catch (e) {
            status = "read parse failed";
            detail = "len=" + frame.size().format("%d");
        }
        refresh();
    }

    private function handleAuth(frame as Lang.ByteArray) as Void {
        if (_resume == null) { return; }
        try {
            var next = _resume.handle(frame);
            if (next != null) {
                _client.send(next, []b, 0, false);
            } else if (_resume.step == PumpX2.ResumeCoordinator.STEP_PAIRED) {
                _authed = true;
                status = "RESUME OK - reading";
                // Confirm with an authenticated read (TimeSinceReset).
                _client.send(new PumpX2.TimeSinceResetRequest(), []b, 0, false);
            }
        } catch (e instanceof PumpX2.JpakeAuthException) {
            status = "RESUME FAILED";
            detail = "handshake rejected";
        }
        refresh();
    }

    private function refresh() as Void {
        WatchUi.requestUpdate();
    }
}
