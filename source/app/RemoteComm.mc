using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

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
    // `sentAt` is the wall-clock send-time stamp (Unix seconds); the host refuses a delivery-authorizing
    // command that arrives too late (stale bolus = double-dose hazard). Time.now().value() is real
    // wall-clock — NOT System.getTimer() (monotonic device-uptime), which newRequestId() uses.
    //
    // C2 §2.3: `code` is the entered 4-digit bolus passcode, or null when no passcode was required. It is
    // added to the wire dict ("bolusPasscode") ONLY when non-null (same additive-field idiom as sentAt /
    // bgMgdl) — omitted entirely otherwise. The PHONE is the sole authority: it verifies the code and
    // denies the bolus if wrong/absent. The watch never verifies or persists it (see AppState.sendBolusNow).
    function bolusRequest(units as Lang.Float, requestId as Lang.String, code as Lang.String?) as Lang.Dictionary {
        var d = {
            "version" => SCHEMA_VERSION,
            "kind" => "bolusRequest",
            "requestId" => requestId,
            "units" => units,
            "sentAt" => Time.now().value()
        };
        if (code != null) { d["bolusPasscode"] = code; }
        return d;
    }

    // Builds a CARB bolus request: the phone (host) is the single calculator — it recomputes the dose
    // from carbsGrams and delivers. We include this watch's own estimate (remoteEstimateUnits) so the
    // phone can reject the bolus if the two diverge (stale-settings guard). bg omitted when stale/unknown.
    //
    // C2 §2.3: `code` is added ("bolusPasscode") only when non-null — see bolusRequest() above.
    //
    // AB4 (Addendum B Option B): `includeStale` is the EXPLICIT per-attempt intent that the wearer chose
    // to include a stale-but-real CGM reading in the correction (the three-way stale prompt's "include").
    // It is added to the wire dict ("includeStaleBG" => true) ONLY when true (same additive-field idiom as
    // bgMgdl / bolusPasscode) — omitted entirely otherwise, NEVER sent as false. The host fails closed on
    // its absence (carbs-only), so the flag is what lets the phone distinguish an acknowledged-stale dose
    // from a bg that merely happened to be stale. Only meaningful on the carb path (never units-mode).
    function bolusRequestCarbs(carbs as Lang.Number, bg as Lang.Number?, estimate as Lang.Float,
                               requestId as Lang.String, code as Lang.String?,
                               includeStale as Lang.Boolean) as Lang.Dictionary {
        var d = {
            "version" => SCHEMA_VERSION,
            "kind" => "bolusRequest",
            "requestId" => requestId,
            "carbsGrams" => carbs,
            "remoteEstimateUnits" => estimate,
            "sentAt" => Time.now().value()   // freshness stamp — see bolusRequest()
        };
        if (bg != null) { d["bgMgdl"] = bg; }
        if (code != null) { d["bolusPasscode"] = code; }
        if (includeStale) { d["includeStaleBG"] = true; }
        return d;
    }

    function cancelBolus(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "cancelBolus", "requestId" => requestId };
    }

    function statusRead(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "statusRead", "requestId" => requestId };
    }

    // statusRead that asks the phone to force a fresh CGM read before replying — sent when the bolus
    // screen opens so the estimate is off the newest value. (The phone also re-reads at delivery.)
    function statusReadFresh(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "statusRead", "requestId" => requestId, "forceGlucose" => true };
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

    // resumePump is insulin-INCREASING (delivery-authorizing), so it carries the freshness stamp too.
    // suspendPump above is insulin-REDUCING and deliberately NOT gated — no stamp.
    function resumePump(requestId as Lang.String) as Lang.Dictionary {
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "resumePump",
            "requestId" => requestId,
            "sentAt" => Time.now().value()
        };
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
