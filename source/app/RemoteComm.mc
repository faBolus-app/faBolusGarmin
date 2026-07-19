using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;

// Command builder + transport ROUTER. Same call surface the UI already uses (builders + send),
// but send() now routes to one of two transports:
//   - phone-relay (default): commands go to the iPhone host over the Connect IQ mobile SDK; the
//     phone runs the confirm interlock and dispatches via PumpX2Kit.
//   - direct-to-pump: commands are serviced locally over BLE via DirectTransport + the PumpX2
//     engine (used when the phone is away — enabled with a shared derived secret).
// Both deliver reply dicts back through emitInbound(...) in the same schema (v1), so AppState/UI
// are identical regardless of transport. See ControlX2iOS/schema/command.schema.json.
module RemoteComm {
    const SCHEMA_VERSION = 1;

    enum { MODE_PHONE, MODE_DIRECT }
    var mode as Lang.Number = MODE_PHONE;
    var _direct as DirectTransport or Null = null;
    // Set by the app; receives inbound reply dicts from whichever transport is active.
    var onInbound as Lang.Method or Null = null;

    // Builds a units-only bolus request dictionary matching the schema.
    function bolusRequest(units as Lang.Float, requestId as Lang.String) as Lang.Dictionary {
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "bolusRequest",
            "requestId" => requestId,
            "units" => units
        };
    }

    function cancelBolus(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "cancelBolus", "requestId" => requestId };
    }

    function statusRead(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "statusRead", "requestId" => requestId };
    }

    // Clears a pump alert (phone relays a signed dismiss; direct sends it itself).
    function dismissAlert(requestId as Lang.String, alertId as Lang.Number, alertKind as Lang.Number) as Lang.Dictionary {
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "dismissAlert",
            "requestId" => requestId,
            "alertId" => alertId,
            "alertKind" => alertKind
        };
    }

    // True when the companion phone is reachable.
    function phoneReachable() as Lang.Boolean {
        return System.getDeviceSettings().phoneConnected;
    }

    // Routes a command to the active transport. No-ops safely if unavailable; never crashes.
    function send(cmd as Lang.Dictionary) as Void {
        if (mode == MODE_DIRECT && _direct != null) {
            _direct.send(cmd);
            return;
        }
        if (!phoneReachable()) { return; }
        try {
            Comm.transmit(cmd, null, new CommListener());
        } catch (e) {
            // swallow transport errors; the UI reflects reachability separately
        }
    }

    // Delivers an inbound reply dict (from either transport) to the app's handler.
    function emitInbound(dict as Lang.Dictionary) as Void {
        if (onInbound != null) { onInbound.invoke(dict); }
    }

    // Switch to direct-to-pump mode, bringing up a BLE session with a shared derived secret.
    // (The lease/handoff policy that decides WHEN to call this is added with the phone-side
    // coordination; for now it's invoked explicitly, e.g. for hardware bring-up.)
    function enableDirect(derivedSecret as Lang.ByteArray) as Void {
        if (_direct == null) { _direct = new DirectTransport(); }
        _direct.activate(derivedSecret);
        mode = MODE_DIRECT;
    }

    // Revert to phone-relay mode (e.g. when the phone comes back in range).
    function usePhone() as Void {
        mode = MODE_PHONE;
    }

    var _counter = 0;
    function newRequestId() as Lang.String {
        _counter += 1;
        return System.getTimer().toString() + "-" + _counter.toString();
    }
}

// Minimal ConnectionListener (transmit requires one). Delivery status comes back via the
// separate inbound bolusStatus message, so these are no-ops.
class CommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void {}
}
