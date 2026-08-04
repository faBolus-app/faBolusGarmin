using Toybox.Lang;

// Builds the schema-v1 `statusRead` reply dict (the same shape the phone sends, consumed by
// AppState.handle) from values read directly off the pump by DirectTransport. Kept pure so it can
// be unit-tested without BLE. See faBolus/schema/command.schema.json for the contract.
module StatusFeed {
    const SCHEMA_VERSION = 1;

    // DO NOT REVIVE THIS. Superseded by C8 / defect E8: faBolus must never *derive* a trend arrow.
    //
    // This is a hand-duplicated copy of a derivation that has since been removed from the phone path,
    // and it carries the same three defects: no "rate unavailable" sentinel guard (the pump's 0x7f
    // decodes here as +12.7 mg/dL/min and returns "upup" — the reported "double-up when the pump shows
    // no arrow"), no way to express *no arrow* at all, and asymmetric bands (-3.0 gives "down" while
    // +3.0 gives "upup").
    //
    // The pump reports its own arrow: HomeScreenMirrorResponse (opcode 57) carries cgmTrendIconId,
    // including an explicit NO_ARROW(0). When this tree is rewired (see DIRECT_PUMP_STATUS.md — it is
    // compiled by no jungle today), read that response and delete this function rather than port it.
    // Kept, not deleted, only because the WIP register forbids discarding parked work.
    //
    // Maps the pump's signed trendRate (0.1 mg/dL/min units) to a direction token.
    function trendToken(trendRate as Lang.Number) as Lang.String {
        var r = trendRate / 10.0;
        if (r < -3.0) { return "downdown"; }
        if (r < -2.0) { return "down"; }
        if (r < -1.0) { return "down45"; }
        if (r <= 1.0) { return "flat"; }
        if (r < 2.0) { return "up45"; }
        if (r < 3.0) { return "up"; }
        return "upup";
    }

    // Copies the known status fields present in `agg` into a fresh statusRead dict.
    function build(agg as Lang.Dictionary) as Lang.Dictionary {
        var d = { "version" => SCHEMA_VERSION, "kind" => "statusRead" };
        var keys = [
            "bgMgdl", "trend", "glucoseAgeSec", "units", "reservoirUnits",
            "batteryPercent", "lastBolusUnits", "message",
        ];
        for (var i = 0; i < keys.size(); i++) {
            if (agg.hasKey(keys[i])) { d[keys[i]] = agg[keys[i]]; }
        }
        return d;
    }

    // Builds a bolusStatus reply dict for a given request id.
    function bolusStatus(requestId as Lang.String, status as Lang.String, message as Lang.String or Null) as Lang.Dictionary {
        var d = { "version" => SCHEMA_VERSION, "kind" => "bolusStatus", "requestId" => requestId, "status" => status };
        if (message != null) { d["message"] = message; }
        return d;
    }
}
