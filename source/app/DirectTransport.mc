using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Timer;

// Direct-to-pump transport: the same command dicts the phone-relay uses (statusRead / bolusRequest
// / cancelBolus / dismissAlert), serviced locally over BLE via the PumpX2 engine instead of relayed
// to the iPhone. Replies are delivered back through RemoteComm.emitInbound(...) in the identical
// schema, so AppState/UI are unchanged.
//
// Auth uses the on-watch JPAKE resume path with a derivedSecret shared from the phone (see the
// handoff plan). Signing uses authKey + a freshly read pumpTimeSinceReset.
//
// NOTE: the BLE session (bond/subscribe/notify) can only be validated on venu3s hardware; this is
// compile-verified. The pure dict-building lives in StatusFeed (unit-tested).
class DirectTransport {
    // Bolus micro-state so we can chain time -> permission -> initiate -> poll off async responses.
    enum { B_NONE, B_TIME, B_PERMISSION, B_INITIATE, B_POLL }

    private var _client as PumpX2.PumpBleClient;
    private var _resume as PumpX2.ResumeCoordinator or Null;
    private var _derivedSecret as Lang.ByteArray = []b;
    private var _authKey as Lang.ByteArray = []b;
    private var _pumpTime as Lang.Long = 0l;
    private var _authed as Lang.Boolean = false;

    // status-read aggregation
    private var _agg as Lang.Dictionary = {};
    private var _pendingReads as Lang.Number = 0;
    private var _statusQueued as Lang.Boolean = false;

    // bolus flow
    private var _bStage as Lang.Number = B_NONE;
    private var _bReqId as Lang.String or Null = null;
    private var _bUnits as Lang.Float = 0.0;
    private var _bId as Lang.Number = 0;

    // bolus-completion polling
    private var _pollTimer as Timer.Timer or Null = null;
    private var _pollCount as Lang.Number = 0;
    private var _sawActive as Lang.Boolean = false;

    // pending signed alert-dismiss (sent after a fresh pump-time read)
    private var _pendingDismiss as Lang.Dictionary or Null = null;

    function initialize() {
        _client = new PumpX2.PumpBleClient();
        _client.onReady = method(:onReady);
        _client.onFrame = method(:onFrame);
        _client.onStateChange = method(:onState);
        _client.onErrorCb = method(:onError);
    }

    // Bring up the direct session with a derived secret from a prior (phone-side) full pairing.
    function activate(derivedSecret as Lang.ByteArray) as Void {
        _derivedSecret = derivedSecret;
        _authed = false;
        _client.open();
    }

    function isReady() as Lang.Boolean { return _authed; }

    // ---- command dispatch (mirrors the phone-relay command kinds) ----

    function send(cmd as Lang.Dictionary) as Void {
        var kind = cmd["kind"] as Lang.String or Null;
        if (kind == null) { return; }
        if (kind.equals("statusRead")) {
            _statusQueued = true;
            if (_authed) { readBatch(); }
        } else if (kind.equals("bolusRequest")) {
            beginBolus(cmd);
        } else if (kind.equals("cancelBolus")) {
            cancelBolus();
        } else if (kind.equals("dismissAlert")) {
            dismissAlert(cmd);
        }
    }

    // ---- BLE client callbacks ----

    function onReady() as Void {
        _resume = new PumpX2.ResumeCoordinator(_derivedSecret, 0, null);
        _client.send(_resume.start(), []b, 0, false);
    }

    function onFrame(charEnum as Lang.Number, frame as Lang.ByteArray) as Void {
        if (charEnum == PumpX2.Ble.CHAR_AUTHORIZATION) {
            handleAuthFrame(frame);
            return;
        }
        var msg;
        try {
            msg = PumpX2.ResponseParser.parse(frame);
        } catch (e) {
            return; // unknown/failed frame; ignore
        }
        routeResponse(msg);
    }

    function onState(text as Lang.String) as Void {
        System.println("[direct] " + text);
    }

    function onError(text as Lang.String) as Void {
        System.println("[direct][error] " + text);
    }

    // ---- auth (resume) ----

    private function handleAuthFrame(frame as Lang.ByteArray) as Void {
        if (_resume == null) { return; }
        try {
            var next = _resume.handle(frame);
            if (next != null) {
                _client.send(next, []b, 0, false);
            } else if (_resume.step == PumpX2.ResumeCoordinator.STEP_PAIRED) {
                _authKey = _resume.authKey;
                _authed = true;
                if (_statusQueued) { readBatch(); }
            }
        } catch (e) {
            _authed = false; // resume failed
        }
    }

    // ---- status reads ----

    private function readBatch() as Void {
        _agg = {};
        _pendingReads = 6;
        _client.send(new PumpX2.CurrentEgvGuiDataV2Request(), []b, 0, false);
        _client.send(new PumpX2.ControlIQIOBRequest(), []b, 0, false);
        _client.send(new PumpX2.InsulinStatusRequest(), []b, 0, false);
        _client.send(new PumpX2.CurrentBatteryV2Request(), []b, 0, false);
        _client.send(new PumpX2.LastBolusStatusV2Request(), []b, 0, false);
        _client.send(new PumpX2.TimeSinceResetRequest(), []b, 0, false);
    }

    private function markRead() as Void {
        if (_pendingReads > 0) { _pendingReads -= 1; }
        if (_pendingReads == 0 && _statusQueued) {
            _statusQueued = false;
            RemoteComm.emitInbound(StatusFeed.build(_agg));
        }
    }

    private function routeResponse(msg as PumpX2.Message) as Void {
        var op = msg.opCode & 0xFF;
        if (op == 0xC1) {
            var egv = msg as PumpX2.CurrentEgvGuiDataV2Response;
            if (egv.hasValidReading()) {
                _agg["bgMgdl"] = egv.cgmReading;
                _agg["trend"] = StatusFeed.trendToken(egv.trendRate);
                _agg["glucoseAgeSec"] = 0; // read just now; TODO map pump epoch precisely
            }
            markRead();
        } else if (op == 0x6D) {
            _agg["units"] = (msg as PumpX2.ControlIQIOBResponse).iobUnits();
            markRead();
        } else if (op == 0x25) {
            _agg["reservoirUnits"] = (msg as PumpX2.InsulinStatusResponse).currentInsulinAmount.toFloat();
            markRead();
        } else if (op == 0x91) {
            _agg["batteryPercent"] = (msg as PumpX2.CurrentBatteryV2Response).batteryPercent();
            markRead();
        } else if (op == 0xA5) {
            _agg["lastBolusUnits"] = (msg as PumpX2.LastBolusStatusV2Response).deliveredUnits();
            markRead();
        } else if (op == 0x37) {
            _pumpTime = (msg as PumpX2.TimeSinceResetResponse).currentTime;
            if (_bStage == B_TIME) {
                _bStage = B_PERMISSION;
                _client.send(new PumpX2.BolusPermissionRequest(), _authKey, _pumpTime, true);
            } else if (_pendingDismiss != null) {
                var d = _pendingDismiss;
                _pendingDismiss = null;
                var nid = d["alertId"] as Lang.Number;
                var ntype = d["alertKind"] as Lang.Number;
                _client.send(new PumpX2.DismissNotificationRequest(nid, ntype, false), _authKey, _pumpTime, true);
            } else {
                markRead();
            }
        } else if (op == 0x2D) {
            onBolusStatus(msg as PumpX2.CurrentBolusStatusResponse);
        } else if (op == 0xA3) {
            onPermission(msg as PumpX2.BolusPermissionResponse);
        } else if (op == 0x9F) {
            onInitiate(msg as PumpX2.InitiateBolusResponse);
        }
    }

    // ---- bolus flow (time -> permission -> initiate) ----

    private function beginBolus(cmd as Lang.Dictionary) as Void {
        if (!_authed) {
            emitBolus((cmd["requestId"] as Lang.String), "failed", "not connected");
            return;
        }
        _bReqId = cmd["requestId"] as Lang.String;
        _bUnits = (cmd["units"] as Lang.Float);
        _bStage = B_TIME;
        // Read a fresh pump time immediately before signing (the HMAC covers it).
        _client.send(new PumpX2.TimeSinceResetRequest(), []b, 0, false);
    }

    private function onPermission(resp as PumpX2.BolusPermissionResponse) as Void {
        if (_bStage != B_PERMISSION) { return; }
        if (!resp.granted()) {
            _bStage = B_NONE;
            emitBolus(_bReqId, "failed", "permission denied");
            return;
        }
        _bId = resp.bolusId;
        _bStage = B_INITIATE;
        var milliunits = Math.round(_bUnits * 1000.0).toNumber();
        _client.send(
            new PumpX2.InitiateBolusRequest(milliunits, _bId, 1, 0, 0, 0, 0, 0),
            _authKey, _pumpTime, true);
    }

    private function onInitiate(resp as PumpX2.InitiateBolusResponse) as Void {
        if (_bStage != B_INITIATE) { return; }
        if (!resp.accepted()) {
            _bStage = B_NONE;
            emitBolus(_bReqId, "failed", "not accepted");
            return;
        }
        // Accepted: report delivering, then poll CurrentBolusStatus until it's no longer active.
        emitBolus(_bReqId, "delivering", null);
        _bStage = B_POLL;
        _pollCount = 0;
        _sawActive = false;
        startPoll();
    }

    // ---- bolus-completion polling ----

    private function startPoll() as Void {
        stopPollTimer();
        _pollTimer = new Timer.Timer();
        _pollTimer.start(method(:pollBolus), 1500, true);   // poll every 1.5s
    }

    // Timer callback: request the current bolus status (unsigned read).
    function pollBolus() as Void {
        if (_bStage != B_POLL) { stopPollTimer(); return; }
        _pollCount += 1;
        if (_pollCount > 40) {   // ~60s guard against a hung poll
            var done = _sawActive;
            stopPoll();
            emitBolus(_bReqId, done ? "delivered" : "failed", done ? null : "status timeout");
            return;
        }
        _client.send(new PumpX2.CurrentBolusStatusRequest(), []b, 0, false);
    }

    private function onBolusStatus(resp as PumpX2.CurrentBolusStatusResponse) as Void {
        if (_bStage != B_POLL) { return; }
        if (resp.bolusId == _bId && resp.isActive()) {
            _sawActive = true;   // still delivering; wait for the next tick
            return;
        }
        // No longer active. Treat as complete once we've seen it deliver (or after a couple polls,
        // to cover a bolus that finished before the first poll landed).
        if (_sawActive || _pollCount >= 3) {
            stopPoll();
            emitBolus(_bReqId, "delivered", null);
        }
    }

    private function stopPoll() as Void {
        stopPollTimer();
        _bStage = B_NONE;
    }

    private function stopPollTimer() as Void {
        if (_pollTimer != null) { _pollTimer.stop(); _pollTimer = null; }
    }

    private function cancelBolus() as Void {
        if (!_authed) { return; }
        // Uses the most recent pump time (read seconds earlier for this bolus); cancel is
        // time-sensitive so we don't re-read first.
        _client.send(new PumpX2.CancelBolusRequest(_bId), _authKey, _pumpTime, true);
        stopPoll();
        emitBolus(_bReqId, "failed", "canceled");
    }

    // ---- alerts ----

    // Signed dismiss of a pump alert. Reads a fresh pump time first (the HMAC covers it), then
    // sends DismissNotificationRequest from the routeResponse(TimeSinceReset) handler.
    private function dismissAlert(cmd as Lang.Dictionary) as Void {
        if (!_authed) { return; }
        _pendingDismiss = cmd;
        _client.send(new PumpX2.TimeSinceResetRequest(), []b, 0, false);
    }

    private function emitBolus(reqId as Lang.String or Null, status as Lang.String, message as Lang.String or Null) as Void {
        if (reqId == null) { return; }
        RemoteComm.emitInbound(StatusFeed.bolusStatus(reqId, status, message));
    }
}
