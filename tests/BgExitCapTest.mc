using Toybox.Lang;
using Toybox.Test;

// G-L1 (19-04): BgService's Background.exit(AppState.alerts) forwards the compact alerts list across
// the background-exit boundary — Toybox.Background.exit's own doc documents an
// ExitDataSizeLimitException at ~8 KB (50 alerts x <=80-char titles approaches it). AppState.
// alertsForBackgroundExit is the PURE, byte-budget-safe subset helper BgService.onPhoneMessage forwards
// instead of the raw list — preserves the phone's most-serious-first ordering, never mutates the
// source, and returns a small array unchanged. Style mirrors tests/AlertHelpersTest.mc.
module BgExitCapTest {

    function alertWithTitle(id as Lang.Number, kind as Lang.Number, title as Lang.String) as Lang.Dictionary {
        return { "id" => id, "kind" => kind, "title" => title };
    }

    // An 80-char title (sanitizeAlerts' own cap) repeated across a full 50-alert list is the worst
    // case this helper defends against.
    function longTitle() as Lang.String {
        var s = "";
        for (var i = 0; i < 80; i += 1) { s += "x"; }
        return s;
    }

    // A small (well under budget) alerts array passes through completely unchanged.
    (:test)
    function smallArrayIsReturnedUnchanged(logger as Test.Logger) as Lang.Boolean {
        var arr = [ alertWithTitle(1, 2, "Low glucose"), alertWithTitle(3, 4, "Pump disconnected") ];
        var out = AppState.alertsForBackgroundExit(arr);
        Test.assertEqualMessage(out.size(), arr.size(), "small array unchanged in size");
        Test.assertEqualMessage(out[0]["id"], 1, "first alert preserved");
        Test.assertEqualMessage(out[1]["id"], 3, "second alert preserved");
        return true;
    }

    // A worst-case oversize array (50 alerts x 80-char titles) is capped to a subset whose estimated
    // serialized size stays within the safety budget, preserving the phone's most-serious-first order
    // (the first N are kept, never a reshuffled/sampled subset).
    (:test)
    function oversizeArrayIsCappedPreservingOrder(logger as Test.Logger) as Lang.Boolean {
        var arr = [];
        for (var i = 0; i < 50; i += 1) { arr.add(alertWithTitle(i, 1, longTitle())); }
        var out = AppState.alertsForBackgroundExit(arr);
        Test.assertMessage(out.size() < arr.size(), "oversize array is capped to fewer entries");
        Test.assertMessage(out.size() > 0, "cap still forwards at least some alerts");
        // Order preserved: the kept alerts are an unbroken PREFIX of the original (most-serious-first).
        for (var i = 0; i < out.size(); i += 1) {
            Test.assertEqualMessage(out[i]["id"], arr[i]["id"], "kept alert " + i + " matches the prefix");
        }
        return true;
    }

    // Pure: the source array passed in is never mutated (the foreground surface must still see every
    // alert AppState.alerts holds).
    (:test)
    function sourceArrayIsNeverMutated(logger as Test.Logger) as Lang.Boolean {
        var arr = [];
        for (var i = 0; i < 50; i += 1) { arr.add(alertWithTitle(i, 1, longTitle())); }
        var sizeBefore = arr.size();
        AppState.alertsForBackgroundExit(arr);
        Test.assertEqualMessage(arr.size(), sizeBefore, "source array size unchanged after capping");
        var firstIndex = 0;
        Test.assertEqualMessage(arr[firstIndex]["id"], 0, "source array contents unchanged after capping");
        return true;
    }
}
