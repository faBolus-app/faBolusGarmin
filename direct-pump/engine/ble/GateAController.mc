using Toybox.Lang;
using Toybox.WatchUi;

// Drives the Gate A smoke test: open the BLE client (scan -> bond -> subscribe), and on ready
// send an ApiVersionRequest to elicit one CURRENT_STATUS notification, proving the full
// bond+subscribe+notify path on the venu3s with the bench pump. Exposes human-readable status
// for GateAView. Bench PoC only.
class GateAController {
    public var status as Lang.String = "idle";
    public var detail as Lang.String = "";

    private var _client as PumpX2.PumpBleClient;

    function initialize() {
        _client = new PumpX2.PumpBleClient();
        _client.onStateChange = method(:onState);
        _client.onErrorCb = method(:onError);
        _client.onReady = method(:onReady);
        _client.onFrame = method(:onFrame);
    }

    function start() as Void {
        status = "opening";
        detail = "";
        _client.open();
        refresh();
    }

    function onState(text as Lang.String) as Void {
        status = text;
        refresh();
    }

    function onError(text as Lang.String) as Void {
        status = "ERROR";
        detail = text;
        refresh();
    }

    function onReady() as Void {
        status = "ready: reading ApiVersion";
        // Unsigned read; no auth key / pump time needed.
        _client.send(new PumpX2.ApiVersionRequest(), []b, 0, false);
        refresh();
    }

    function onFrame(charEnum as Lang.Number, frame as Lang.ByteArray) as Void {
        var op = (frame[0] & 0xFF).format("%02X");
        if (charEnum == PumpX2.Ble.CHAR_AUTHORIZATION) {
            status = "auth frame op=" + op;
            detail = "len=" + frame.size().format("%d");
        } else {
            try {
                var m = PumpX2.ResponseParser.parse(frame);
                status = "GATE A PASS";
                detail = "parsed response op=" + (m.opCode & 0xFF).format("%02X");
            } catch (e) {
                status = "frame op=" + op;
                detail = "unparsed len=" + frame.size().format("%d");
            }
        }
        refresh();
    }

    private function refresh() as Void {
        WatchUi.requestUpdate();
    }
}
