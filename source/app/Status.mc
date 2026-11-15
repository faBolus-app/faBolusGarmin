using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

// The phone's latest status: every live value with the time it was measured, by the phone's clock.
//
// A value's age is the older of two estimates, so neither clock can make a value look fresher than it is:
// the phone's view of it when the status was sent (sentAt - at) plus the time since the status arrived,
// which holds whatever the difference between the two clocks; and the watch's clock less `at`, which holds
// however long Connect IQ kept the message before handing it over (it holds one while the app is closed and
// hands it over when the app registers). The second assumes the clocks agree, as they do when the watch
// takes its time from the phone; a watch set fast shows values older by that much, the safe direction. A
// value missing from the status, or one that didn't read, is absent here, never zero.
module Status {
    (:background, :glance)
    var _p as Lang.Dictionary? = null;
    // When this watch received it (epoch seconds, the watch's clock).
    (:background, :glance)
    var _r as Lang.Number = 0;
    // When it arrived by this watch's uptime (System.getTimer(), ms); null when that isn't known (saved before
    // the watch last restarted). The wall clock can be stepped back; uptime can't.
    (:background, :glance)
    var _rMs as Lang.Number? = null;
    // The watch-minus-phone clock difference each recent status showed, its time in transit included.
    (:background)
    var _offsets as Lang.Array<Lang.Number> = [] as Lang.Array<Lang.Number>;
    (:background)
    const MAX_OFFSETS = 8;

    (:background)
    const LINKS = ["disconnected", "scanning", "connecting", "authenticating", "connected"];
    (:background)
    const TRENDS = ["flat", "up", "upup", "up45", "down", "downdown", "down45"];
    // Why the pump says its reading shouldn't correct a dose (faBolus GlucoseCautionToken).
    (:background)
    const CAUTIONS = ["low", "high", "sensor", "checkbg", "autofilloff", "notread"];
    (:background)
    const SEVERITIES = ["info", "warning", "critical"];
    (:background)
    const INTENTS = ["quiet", "alert"];
    (:background)
    const ACTIVITIES = ["normal", "sleep", "exercise"];
    (:background)
    const MAX_ALERTS = 32;

    // How far behind the watch's clock a message's sentAt may be and still count as sent just now: time in
    // transit, and the clocks' small disagreement. Further behind, it was held on its way here. Every
    // allowance for the difference between the clocks is capped at this.
    (:background, :glance)
    const CLOCK_SEC = 30;

    // Takes a status payload. Returns false, changing nothing, when it lacks what every status has, or
    // when it was sent before the one held and was held on its way here (a late or reordered copy), however
    // late it arrives; a value inside it that doesn't read is left out and the rest is kept. One sent before
    // the one held but current by the watch's clock is taken when the one held was sent more than CLOCK_SEC
    // ahead of the watch's clock: the phone's clock was ahead and has been put right. Decided from the status
    // held, which the background service loads from storage, so it holds in each of its fresh processes.
    (:background)
    function accept(p as Lang.Dictionary, receivedAt as Lang.Number) as Lang.Boolean {
        var clean = cleaned(p);
        if (clean == null) { return false; }
        var sent = clean["sentAt"] as Lang.Number;
        if (_p != null && sent < sentAt()
            && (receivedAt - sent > CLOCK_SEC || sentAt() - receivedAt <= CLOCK_SEC)) {
            return false;
        }
        _p = clean;
        _r = receivedAt;
        _rMs = System.getTimer();
        _offsets.add(receivedAt - sent);
        if (_offsets.size() > MAX_OFFSETS) { _offsets = _offsets.slice(1, null); }
        return true;
    }

    // When a message with this sentAt, received now, counts as hearing from the phone: when the phone sent it,
    // allowing CLOCK_SEC for transit and the clocks' disagreement, and never later than now. A message
    // Connect IQ held is then as old as it is, and doesn't make the phone count as answering. Null with no
    // sentAt (a config, a dismiss result): when it was sent can't be told.
    function heardTime(sent as Lang.Number?, now as Lang.Number) as Lang.Number? {
        if (sent == null) { return null; }
        var at = sent + CLOCK_SEC;
        return (at < now) ? at : now;
    }

    (:background)
    function cleaned(p as Lang.Dictionary) as Lang.Dictionary? {
        var sentAt = Wire.int(p, "sentAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
        var revision = Wire.str(p, "configRevision", Wire.MAX_ID);
        var link = Wire.token(p, "pumpLink", LINKS);
        var bolus = Wire.obj(p, "bolus");
        var alerts = Wire.arr(p, "alerts", MAX_ALERTS);
        if (sentAt == null || revision == null || link == null || bolus == null || alerts == null) { return null; }
        var canBolus = Wire.bool(bolus, "canBolus");
        if (canBolus == null) { return null; }

        var out = { "sentAt" => sentAt, "configRevision" => revision, "pumpLink" => link } as Lang.Dictionary;
        var g = Wire.obj(p, "glucose");
        if (g != null) {
            var mgdl = Wire.int(g, "mgdl", 0, Wire.MAX_GLUCOSE);
            var at = timeOf(g);
            var backup = Wire.bool(g, "backup");
            if (mgdl != null && at != null && backup != null) {
                var clean = { "mgdl" => mgdl, "at" => at, "backup" => backup } as Lang.Dictionary;
                var trend = Wire.token(g, "trend", TRENDS);
                if (trend != null) { clean["trend"] = trend; }
                // A caution this watch doesn't know still keeps the reading out of a dose.
                var caution = Wire.token(g, "caution", CAUTIONS);
                if (caution != null) { clean["caution"] = caution; } else if (g.hasKey("caution")) { clean["caution"] = "other"; }
                out["glucose"] = clean;
            }
        }
        copyAmount(p, out, "iob", "mU");
        copyAmount(p, out, "reservoir", "mU");
        copyAmount(p, out, "lastBolus", "mU");
        copyAmount(p, out, "maxBasal", "mUPerHour");
        var b = Wire.obj(p, "battery");
        if (b != null) {
            var pct = Wire.int(b, "percent", 0, 100);
            var at = timeOf(b);
            if (pct != null && at != null) {
                var clean = { "percent" => pct, "at" => at } as Lang.Dictionary;
                var charging = Wire.bool(b, "charging");
                if (charging != null) { clean["charging"] = charging; }
                out["battery"] = clean;
            }
        }
        var basal = Wire.obj(p, "basal");
        if (basal != null) {
            var suspended = Wire.bool(basal, "suspended");
            var rate = Wire.int(basal, "mUPerHour", 0, Wire.MAX_MU);
            var at = timeOf(basal);
            if (suspended != null && at != null && (suspended || rate != null)) {
                var clean = { "suspended" => suspended, "at" => at } as Lang.Dictionary;
                if (!suspended) {
                    clean["mUPerHour"] = rate;
                    // Basal-IQ's stop isn't the pump's suspension: a bolus still goes.
                    if (Wire.bool(basal, "basalIQ") == true) {
                        clean["basalIQ"] = true;
                    } else if (Wire.bool(basal, "tempRate") == true) {
                        clean["tempRate"] = true;
                        var pct = Wire.int(basal, "tempPercent", 0, 250);
                        if (pct != null) { clean["tempPercent"] = pct; }
                    }
                }
                out["basal"] = clean;
            }
        }
        var session = Wire.obj(p, "cgmSession");
        if (session != null) {
            var at = timeOf(session);
            if (at != null) {
                var clean = { "at" => at } as Lang.Dictionary;
                var started = Wire.int(session, "startedAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
                if (started != null) { clean["startedAt"] = started; }
                var calibrated = Wire.int(session, "lastCalibrationAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
                if (calibrated != null) { clean["lastCalibrationAt"] = calibrated; }
                out["cgmSession"] = clean;
            }
        }
        var c = Wire.obj(p, "calculator");
        if (c != null) {
            var ratio = Wire.int(c, "carbRatioMg", 0, 1000000);
            var isf = Wire.int(c, "isf", 0, 1000);
            var target = Wire.int(c, "target", 0, 1000);
            var max = Wire.int(c, "maxBolusMU", 0, Wire.MAX_MU);
            var at = timeOf(c);
            if (ratio != null && isf != null && target != null && max != null && at != null) {
                var calc = { "carbRatioMg" => ratio, "isf" => isf, "target" => target, "maxBolusMU" => max, "at" => at };
                // Carbs off on the pump: the food entry is insulin units. Anything but true is carbs on.
                var off = Wire.bool(c, "carbsOff");
                if (off != null && off) { calc["carbsOff"] = true; }
                out["calculator"] = calc;
            }
        }
        var ciq = Wire.obj(p, "controlIQ");
        if (ciq != null) {
            var enabled = Wire.bool(ciq, "enabled");
            var activity = Wire.token(ciq, "activity", ACTIVITIES);
            var at = timeOf(ciq);
            if (enabled != null && activity != null && at != null) {
                out["controlIQ"] = { "enabled" => enabled, "activity" => activity, "at" => at };
            }
        }

        // An event, not a reading: its time is all it carries.
        var auto = Wire.obj(p, "lastAutoCorrection");
        if (auto != null) {
            var at = timeOf(auto);
            if (at != null) { out["lastAutoCorrection"] = { "at" => at }; }
        }

        var gate = { "canBolus" => canBolus } as Lang.Dictionary;
        // A reason this build doesn't know is kept, and shown generically.
        var reason = Wire.str(bolus, "blockReason", 32);
        if (!canBolus) { gate["blockReason"] = (reason != null) ? reason : "unknown"; }
        var a = Wire.obj(bolus, "active");
        if (a != null) {
            var requested = Wire.int(a, "requestedMU", 0, Wire.MAX_MU);
            var started = Wire.int(a, "startedAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
            if (requested != null && started != null) {
                var clean = { "requestedMU" => requested, "startedAt" => started } as Lang.Dictionary;
                var delivered = Wire.int(a, "deliveredMU", 0, Wire.MAX_MU);
                if (delivered != null) { clean["deliveredMU"] = delivered; }
                gate["active"] = clean;
            }
        }
        var limit = Wire.int(bolus, "remoteLimitMU", 0, Wire.MAX_MU);
        if (limit != null) { gate["remoteLimitMU"] = limit; }
        out["bolus"] = gate;

        var items = [] as Lang.Array;
        for (var i = 0; i < alerts.size(); i += 1) {
            var item = alerts[i];
            if (item instanceof Lang.Dictionary) {
                var clean = cleanAlert(item);
                if (clean != null) { items.add(clean); }
            }
        }
        out["alerts"] = items;
        return out;
    }

    (:background)
    function cleanAlert(a as Lang.Dictionary) as Lang.Dictionary? {
        var id = Wire.str(a, "id", Wire.MAX_ID);
        var title = Wire.str(a, "title", 64);
        var body = Wire.str(a, "body", 256);
        var severity = Wire.token(a, "severity", SEVERITIES);
        var intent = Wire.token(a, "intent", INTENTS);
        var dismissable = Wire.bool(a, "dismissable");
        if (id == null || id.length() == 0 || title == null || body == null || severity == null || intent == null
            || dismissable == null) {
            return null;
        }
        return { "id" => id, "title" => title, "body" => body, "severity" => severity, "intent" => intent,
                 "dismissable" => dismissable };
    }

    (:background)
    function timeOf(d as Lang.Dictionary) as Lang.Number? {
        return Wire.int(d, "at", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
    }

    (:background)
    function copyAmount(p as Lang.Dictionary, out as Lang.Dictionary, key as Lang.String, field as Lang.String) as Void {
        var d = Wire.obj(p, key);
        if (d == null) { return; }
        var v = Wire.int(d, field, 0, Wire.MAX_MU);
        var at = timeOf(d);
        if (v != null && at != null) { out[key] = { field => v, "at" => at }; }
    }

    // MARK: Storage. The app saves to STATUS, the background service to BG_STATUS; loading takes the newer.

    // Saved with when it arrived by both clocks, so a process that loads it ages it by uptime too.
    (:background)
    function save(key as Lang.String) as Void {
        var p = _p;
        if (p == null) { return; }
        var rec = { "p" => p, "r" => _r } as Lang.Dictionary;
        var ms = _rMs;
        if (ms != null) { rec["t"] = ms; }
        Store.save(key, rec);
    }

    // Takes the stored copy the phone sent last, as near as the watch can tell, unless the one held was sent
    // later: a held message arrives late but was sent early, so when it arrived doesn't say which is newer.
    (:background, :glance)
    function load() as Void {
        var a = Store.record(Store.STATUS);
        var b = Store.record(Store.BG_STATUS);
        var rec = (b != null && (a == null || recordSentBy(b) > recordSentBy(a))) ? b : a;
        if (rec == null) { return; }
        var p = rec["p"];
        var r = rec["r"];
        if (!(p instanceof Lang.Dictionary) || !(r instanceof Lang.Number)) { return; }
        var v = p["sentAt"];
        if (!(v instanceof Lang.Number)) { return; }
        if (_p != null && (r == _r || sentBy(v, r) < sentBy(sentAt(), _r))) { return; }
        _p = p;
        _r = r;
        // The uptime it arrived at counts while uptime hasn't restarted since (it starts at zero when the
        // watch boots); otherwise only the wall clock can say how long ago that was.
        var t = rec["t"];
        _rMs = (t instanceof Lang.Number && System.getTimer() >= t) ? t : null;
    }

    // When the phone sent a message, by the watch's clock as near as it can tell: its sentAt, or when it
    // arrived if that's earlier (the phone's clock ahead). A held message's is long before it arrived.
    (:background, :glance)
    function sentBy(sent as Lang.Number, receivedAt as Lang.Number) as Lang.Number {
        return (sent < receivedAt) ? sent : receivedAt;
    }

    (:background, :glance)
    function recordSentBy(rec as Lang.Dictionary) as Lang.Number {
        var p = rec["p"];
        var r = rec["r"];
        var v = (p instanceof Lang.Dictionary) ? p["sentAt"] : null;
        if (!(r instanceof Lang.Number) || !(v instanceof Lang.Number)) { return 0; }
        return sentBy(v, r);
    }

    // For tests: forget the status.
    function clear() as Void {
        _p = null;
        _r = 0;
        _rMs = null;
        _offsets = [] as Lang.Array<Lang.Number>;
    }

    // MARK: Reading it.

    (:background, :glance)
    function present() as Lang.Boolean { return _p != null; }

    (:background, :glance)
    function receivedAt() as Lang.Number { return _r; }

    (:background, :glance)
    function sentAt() as Lang.Number {
        var p = _p;
        if (p == null) { return 0; }
        var v = p["sentAt"];
        return (v instanceof Lang.Number) ? v : 0;
    }

    (:background, :glance)
    function revision() as Lang.String? {
        var p = _p;
        if (p == null) { return null; }
        var v = p["configRevision"];
        return (v instanceof Lang.String) ? v : null;
    }

    function pumpLink() as Lang.String {
        var p = _p;
        if (p == null) { return "disconnected"; }
        var v = p["pumpLink"];
        return (v instanceof Lang.String) ? v : "disconnected";
    }

    (:background, :glance)
    function part(key as Lang.String) as Lang.Dictionary? {
        var p = _p;
        if (p == null) { return null; }
        var v = p[key];
        return (v instanceof Lang.Dictionary) ? v : null;
    }

    // Carbs are off on the pump: the calculator's food entry is insulin units, and no carbs go.
    function carbsOff() as Lang.Boolean {
        var d = part("calculator");
        if (d == null) { return false; }
        var v = d["carbsOff"];
        return (v instanceof Lang.Boolean) ? v as Lang.Boolean : false;
    }

    (:background, :glance)
    function field(key as Lang.String, name as Lang.String) as Lang.Number? {
        var d = part(key);
        if (d == null) { return null; }
        var v = d[name];
        return (v instanceof Lang.Number) ? v : null;
    }

    // Seconds since this status arrived. By the wall clock, or by uptime when that says longer, so a wall
    // clock stepped back can't stop values aging. Null when neither can say: the wall clock is behind the
    // arrival and uptime isn't known, so any age would be a guess, and the values are treated as stale.
    (:background, :glance)
    function elapsed(now as Lang.Number) as Lang.Number? {
        return elapsedFrom(now - _r, _rMs, System.getTimer());
    }

    (:background, :glance)
    function elapsedFrom(wall as Lang.Number, receivedMs as Lang.Number?, nowMs as Lang.Number) as Lang.Number? {
        // A wrapped timer reads negative and is ignored.
        var m = (receivedMs != null) ? (nowMs - receivedMs) / 1000 : -1;
        if (wall < 0 && m < 0) { return null; }
        return (wall > m) ? wall : m;
    }

    // The phone's clock now, as near as this watch can tell: this watch's, less the smallest difference
    // between the two that recent statuses showed. Time in transit only adds to a difference, so the
    // smallest is the closest, and the estimate isn't ahead of the phone. A bolus request is stamped with
    // it, because the phone judges the request's age, and whether a delivery since supersedes it, on its own
    // clock.
    // The offset isn't capped here: a held status makes the stamp older, and the phone then refuses the
    // request as too old rather than take it as newer than it is.
    function phoneNow(now as Lang.Number) as Lang.Number {
        var best = (_p == null) ? 0 : _r - sentAt();
        for (var i = 0; i < _offsets.size(); i += 1) {
            if (i == 0 || _offsets[i] < best) { best = _offsets[i]; }
        }
        return now - best;
    }

    // Seconds to add to a time by the phone's clock to put it on this watch's: the phone's sentAt is this
    // watch's receivedAt, less the moment in transit. A held status shows a difference as long as it was
    // held, so no more than CLOCK_SEC is taken: past that, the clocks are taken to agree, and a held
    // reading is placed when it was measured rather than as if current. Zero with no status.
    function clockOffset() as Lang.Number {
        if (_p == null) { return 0; }
        var d = _r - sentAt();
        return (d > CLOCK_SEC) ? CLOCK_SEC : d;
    }

    // How old the value under `key` is now, in seconds; null when there is no such value, or its age can't be
    // told.
    (:background, :glance)
    function ageOf(key as Lang.String, now as Lang.Number) as Lang.Number? {
        return ageSince(field(key, "at"), now);
    }

    // The value under `key`.`name` while it's younger than `maxAge` seconds, else null.
    (:background, :glance)
    function freshField(key as Lang.String, name as Lang.String, maxAge as Lang.Number, now as Lang.Number) as Lang.Number? {
        var age = ageOf(key, now);
        if (age == null || age > maxAge) { return null; }
        return field(key, name);
    }

    (:background, :glance)
    function glucose() as Lang.Number? { return field("glucose", "mgdl"); }

    // Why the pump says its reading shouldn't correct a dose, or null when it may: a dose is then carbs only,
    // with no question, as on the phone.
    function glucoseCaution() as Lang.String? {
        var g = part("glucose");
        if (g == null) { return null; }
        var c = g["caution"];
        return (c instanceof Lang.String) ? c : null;
    }

    (:background, :glance)
    function trend() as Lang.String? {
        var g = part("glucose");
        if (g == null) { return null; }
        var t = g["trend"];
        return (t instanceof Lang.String) ? t : null;
    }

    function glucoseFromBackup() as Lang.Boolean {
        var g = part("glucose");
        return g != null && Wire.bool(g, "backup") == true;
    }

    (:background)
    function bolusGate() as Lang.Dictionary? { return part("bolus"); }

    // The phone says a remote may start a bolus now. False with no status.
    function canBolus() as Lang.Boolean {
        var b = bolusGate();
        return b != null && Wire.bool(b, "canBolus") == true;
    }

    function blockReason() as Lang.String? {
        var b = bolusGate();
        if (b == null) { return "noStatus"; }
        var r = b["blockReason"];
        return (r instanceof Lang.String) ? r : null;
    }

    // The bolus the pump is delivering, whichever surface started it.
    function activeBolus() as Lang.Dictionary? {
        var b = bolusGate();
        if (b == null) { return null; }
        var a = b["active"];
        return (a instanceof Lang.Dictionary) ? a : null;
    }

    function remoteLimit() as Lang.Number? {
        var b = bolusGate();
        if (b == null) { return null; }
        var v = b["remoteLimitMU"];
        return (v instanceof Lang.Number) ? v : null;
    }

    (:background)
    function alerts() as Lang.Array {
        var p = _p;
        if (p == null) { return []; }
        var a = p["alerts"];
        return (a instanceof Lang.Array) ? a : [];
    }

    function basalSuspended() as Lang.Boolean {
        var b = part("basal");
        return b != null && Wire.bool(b, "suspended") == true;
    }

    // Basal-IQ has stopped basal for a predicted low; a bolus still goes.
    function basalIQSuspended() as Lang.Boolean {
        var b = part("basal");
        return b != null && Wire.bool(b, "basalIQ") == true;
    }

    // A temp rate set on the pump runs.
    function tempRate() as Lang.Boolean {
        var b = part("basal");
        return b != null && Wire.bool(b, "tempRate") == true;
    }

    // Seconds from `at` (a phone epoch time in this status) to now: the older of its age when the status was
    // sent plus the time since, and the watch's clock less `at`. Never negative; null with no `at`, or when
    // the time since the status arrived can't be told.
    (:background, :glance)
    function ageSince(at as Lang.Number?, now as Lang.Number) as Lang.Number? {
        var since = elapsed(now);
        if (at == null || since == null) { return null; }
        var atPhone = sentAt() - at;
        var relative = (atPhone > 0 ? atPhone : 0) + since;
        var absolute = now - at;
        return (absolute > relative) ? absolute : relative;
    }

    // How long ago the phone sent this status, by the same two estimates; null with none.
    function statusAge(now as Lang.Number) as Lang.Number? {
        return (_p == null) ? null : ageSince(sentAt(), now);
    }

    function charging() as Lang.Boolean {
        var b = part("battery");
        return b != null && Wire.bool(b, "charging") == true;
    }

    function controlIQEnabled() as Lang.Boolean {
        var c = part("controlIQ");
        return c != null && Wire.bool(c, "enabled") == true;
    }

    (:background, :glance)
    function now() as Lang.Number { return Time.now().value(); }
}
