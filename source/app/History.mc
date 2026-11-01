using Toybox.Application.Storage;
using Toybox.Lang;

// Glucose history for the chart: sent by the phone only when asked, and between those, each status's
// reading is appended. Oldest first, one point per measurement time.
module History {
    const MAX_POINTS = 288;
    // Ask again when the newest point is older than this, or there is none.
    const REFRESH_SEC = 600;

    var _at as Lang.Array = [];
    var _mgdl as Lang.Array = [];

    function reset() as Void {
        _at = [];
        _mgdl = [];
    }

    // Takes a history payload in place of what's held. False, changing nothing, when it doesn't read:
    // the times and readings must line up, and the times must rise.
    function accept(p as Lang.Dictionary) as Lang.Boolean {
        var at = Wire.arr(p, "at", 144);
        var mgdl = Wire.arr(p, "mgdl", 144);
        if (at == null || mgdl == null || at.size() != mgdl.size()) { return false; }
        var last = 0;
        for (var i = 0; i < at.size(); i += 1) {
            var t = at[i];
            var v = mgdl[i];
            if (!(t instanceof Lang.Number) || !(v instanceof Lang.Number) || t <= last || t < Wire.EPOCH_MIN
                || v < 0 || v > Wire.MAX_GLUCOSE) {
                return false;
            }
            last = t;
        }
        _at = at;
        _mgdl = mgdl;
        save();
        return true;
    }

    // Adds the status's reading when it's newer than the newest point.
    function append(at as Lang.Number, mgdl as Lang.Number) as Void {
        var n = _at.size();
        if (n > 0) {
            var newest = _at[n - 1];
            if (newest instanceof Lang.Number && at <= newest) { return; }
        }
        _at.add(at);
        _mgdl.add(mgdl);
        if (_at.size() > MAX_POINTS) {
            _at = _at.slice(_at.size() - MAX_POINTS, null);
            _mgdl = _mgdl.slice(_mgdl.size() - MAX_POINTS, null);
        }
        save();
    }

    function times() as Lang.Array { return _at; }
    function values() as Lang.Array { return _mgdl; }

    // History is worth asking for: none is held, or the newest point is old. The times are the phone's
    // clock, so they're moved onto this watch's first.
    function stale(now as Lang.Number) as Lang.Boolean {
        var n = _at.size();
        if (n == 0) { return true; }
        var newest = _at[n - 1];
        if (!(newest instanceof Lang.Number)) { return true; }
        return now - (newest + Status.clockOffset()) > REFRESH_SEC;
    }

    function save() as Void { Store.save(Store.HISTORY, { "at" => _at, "mgdl" => _mgdl }); }

    function load() as Void {
        var rec = Store.record(Store.HISTORY);
        if (rec == null) { return; }
        var at = rec["at"];
        var mgdl = rec["mgdl"];
        if (at instanceof Lang.Array && mgdl instanceof Lang.Array && at.size() == mgdl.size()) {
            _at = at;
            _mgdl = mgdl;
        } else {
            Storage.deleteValue(Store.HISTORY);
        }
    }
}
