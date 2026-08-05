using Toybox.Lang;
using Toybox.Test;

// E5 (defect): the phone sends per-point source timestamps (`historyEpochs`) aligned 1:1 with
// `history` so the CGM plot can position each reading at its REAL time — a data gap renders as a
// gap, not evenly-spaced dots. These tests pin the AppState statusRead PARSE INVARIANT: after a
// statusRead, EITHER historyEpochs.size() == history.size() with 1:1 correspondence, OR
// historyEpochs is empty (fall back to assumed spacing) — never a silent off-by-one that would pin
// a reading to the wrong timestamp. Style mirrors the engine tests (tests/ResponsesTest.mc).
module HistoryEpochsTest {

    // A minimal statusRead envelope carrying `extra`'s keys (so each test states only what it varies).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // (a) Aligned, all-valid input → equal length + 1:1 value correspondence.
    (:test)
    function alignedEpochsKept(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({
            "history" => [100, 120, 140],
            "historyEpochs" => [1000, 1300, 1600]
        }));
        Test.assertEqualMessage(AppState.history.size(), 3, "history size");
        Test.assertEqualMessage(AppState.historyEpochs.size(), AppState.history.size(),
            "epochs aligned to history");
        Test.assertEqualMessage(AppState.history[0], 100, "h0");
        Test.assertEqualMessage(AppState.historyEpochs[0], 1000, "e0");
        Test.assertEqualMessage(AppState.history[2], 140, "h2");
        Test.assertEqualMessage(AppState.historyEpochs[2], 1600, "e2");
        return true;
    }

    // (b) Absent historyEpochs → epochs empty (fallback), history still populated.
    (:test)
    function absentEpochsFallsBack(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({ "history" => [90, 95, 100, 105] }));
        Test.assertEqualMessage(AppState.history.size(), 4, "history size");
        Test.assertEqualMessage(AppState.historyEpochs.size(), 0, "epochs empty (fallback)");
        return true;
    }

    // (c1) Mismatched length → epochs empty, history sanitized (never a partial/aligned guess).
    (:test)
    function mismatchedLengthFallsBack(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({
            "history" => [100, 110, 120],
            "historyEpochs" => [1000, 1300]   // shorter → misaligned, cannot trust
        }));
        Test.assertEqualMessage(AppState.history.size(), 3, "history size");
        Test.assertEqualMessage(AppState.historyEpochs.size(), 0, "epochs empty on length mismatch");
        return true;
    }

    // (c2) An invalid mg/dL in the MIDDLE with aligned epochs → the bad PAIR drops from BOTH arrays,
    // so they stay equal-length and 1:1 (no off-by-one pinning a reading to the wrong time).
    (:test)
    function invalidMiddleReadingDropsPair(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({
            "history" => [100, 9000, 140],       // 9000 out of [0,600] → dropped
            "historyEpochs" => [1000, 1300, 1600]
        }));
        Test.assertEqualMessage(AppState.history.size(), 2, "bad reading dropped");
        Test.assertEqualMessage(AppState.historyEpochs.size(), AppState.history.size(),
            "arrays still aligned after the drop");
        Test.assertEqualMessage(AppState.history[0], 100, "kept h0");
        Test.assertEqualMessage(AppState.historyEpochs[0], 1000, "kept e0");
        Test.assertEqualMessage(AppState.history[1], 140, "3rd reading slid to index 1");
        Test.assertEqualMessage(AppState.historyEpochs[1], 1600, "and its epoch came with it (aligned)");
        return true;
    }

    // (c3) A bad EPOCH (<= 0) alongside a valid reading also drops the whole pair from both arrays.
    (:test)
    function invalidEpochDropsPair(logger as Test.Logger) as Lang.Boolean {
        AppState.handle(statusRead({
            "history" => [100, 120, 140],
            "historyEpochs" => [1000, 0, 1600]   // 0 epoch → drop that pair
        }));
        Test.assertEqualMessage(AppState.history.size(), 2, "bad-epoch pair dropped");
        Test.assertEqualMessage(AppState.historyEpochs.size(), AppState.history.size(), "still aligned");
        Test.assertEqualMessage(AppState.history[1], 140, "kept 3rd reading");
        Test.assertEqualMessage(AppState.historyEpochs[1], 1600, "kept 3rd epoch");
        return true;
    }
}
