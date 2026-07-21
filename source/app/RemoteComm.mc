using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;

// Phone↔remote command builder + transport. Mirrors the faBolus contract
// (faBolus/schema/command.schema.json, source of truth; Swift mirror in faBolusCore/RemoteCommand.swift).
// The schema keys this remote uses are pinned in ../../schema/remote-keys.txt and checked against the
// schema by scripts/check-schema-drift.sh in CI. Commands are sent to the iPhone host over the
// Connect IQ mobile SDK; the phone runs the confirm interlock and dispatches to the pump backend.
//
// (A direct-to-pump transport was prototyped behind a router here; it's paused and lives under
// direct-pump/. This is the shipping phone-relay version.)
module RemoteComm {
    const SCHEMA_VERSION = 1;

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

    // Clears a pump alert on the phone (which sends the signed dismiss to the pump).
    function dismissAlert(requestId as Lang.String, alertId as Lang.Number, alertKind as Lang.Number) as Lang.Dictionary {
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "dismissAlert",
            "requestId" => requestId,
            "alertId" => alertId,
            "alertKind" => alertKind
        };
    }

    // Advanced-control requests (B5): ask the phone to suspend/resume insulin. The phone re-confirms
    // on-device and only honors them when advanced control is enabled for a Mobi — the watch never
    // triggers delivery changes unilaterally.
    function suspendPump(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "suspendPump", "requestId" => requestId };
    }

    function resumePump(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "resumePump", "requestId" => requestId };
    }

    // True when the companion phone is reachable.
    function phoneReachable() as Lang.Boolean {
        return System.getDeviceSettings().phoneConnected;
    }

    // Sends a command dictionary to the paired phone app. No-ops safely offline; never crashes.
    function send(cmd as Lang.Dictionary) as Void {
        if (!phoneReachable()) { return; }
        try {
            Comm.transmit(cmd, null, new CommListener());
        } catch (e) {
            // swallow transport errors; the UI reflects reachability separately
        }
    }

    var _counter = 0;
    function newRequestId() as Lang.String {
        _counter += 1;
        return System.getTimer().toString() + "-" + _counter.toString();
    }
}

// Minimal ConnectionListener (transmit requires one). Delivery status comes back via the
// separate phone→watch bolusStatus message, so these are no-ops.
class CommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void {}
}
