using Toybox.Lang;

// Builds the schema-v1 `statusRead` reply dict (the same shape the phone sends, consumed by
// AppState.handle) from values read directly off the pump by DirectTransport. Kept pure so it can
// be unit-tested without BLE. See ControlX2iOS/schema/command.schema.json for the contract.
module StatusFeed {
    const SCHEMA_VERSION = 1;

    // Maps the pump's signed trendRate (0.1 mg/dL/min units) to the app's direction token
    // (flat/up45/up/upup/down45/down/downdown), matching the 7-category arrows the pump displays.
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
