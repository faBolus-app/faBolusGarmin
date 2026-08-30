using Toybox.Lang;
using Toybox.Test;

// The Details "App:" row exists for ONE reason: to tell the owner which watch build is on the wrist while
// debugging. A row that renders "App: null ()", or clips, or silently stops distinguishing two builds, is
// worse than no row at all — it would answer "which build is this?" WRONGLY, which is far harder to catch
// than a missing answer. So the format and the build number are pinned here.
//
// What is deliberately NOT pinned: the literal value of NAME. It tracks faBolus's MARKETING_VERSION in
// lockstep (BRANCHES.md §1.3) and therefore changes on every app release; asserting "0.1.0" here would
// make a routine version bump fail the suite for no safety reason. The NAME↔MARKETING_VERSION equality is
// a CROSS-REPO fact and is checked where the other repo is actually available —
// scripts/check-version-sync.sh, which the unit binary cannot do (it has no filesystem access to the app
// repo). This file pins the SHAPE; that script pins the VALUE.
module AppVersionTest {

    // "App: <name> (<build>)" — the exact row DetailsView appends.
    (:test)
    function labelFormatIsPinned(logger as Test.Logger) as Lang.Boolean {
        var expected = "App: " + AppVersion.NAME + " (" + AppVersion.BUILD.toString() + ")";
        Test.assertEqualMessage(AppVersion.label(), expected, "the row is 'App: <name> (<build>)'");
        Test.assertMessage(AppVersion.label().find("App: ") == 0, "the row is prefixed 'App: '");
        Test.assertMessage(AppVersion.label().find("(") != null, "the build number is parenthesised");
        Test.assertMessage(AppVersion.label().find(")") != null, "...and closed");
        return true;
    }

    // A positive integer, and the field that actually distinguishes two watch builds of the same release.
    // 0 or a negative would render a meaningless "(0)"/"(-1)" and silently destroy that distinguishing
    // power — which is the whole purpose of the row.
    (:test)
    function buildNumberIsAPositiveInteger(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppVersion.BUILD instanceof Lang.Number, "BUILD is a Number, not a string");
        Test.assertMessage(AppVersion.BUILD >= 1, "BUILD is a positive integer (bumped per build)");
        return true;
    }

    // NAME must be a plain dotted numeric version. Monkey C has no regex, so this scans one-character
    // substrings against an allow-list — digits and dots only, at least one dot, never empty. Enough to
    // catch a NAME accidentally set to "", a placeholder, or a value carrying a stray suffix that would
    // break the sync check's exact compare. Deliberately uses substring()/find() rather than
    // toCharArray()/Lang.Char ordering: substring() is the idiom this codebase already uses (see
    // AppState.strCap) and needs no assumptions about whether Char supports relational operators.
    (:test)
    function versionNameIsPlainDottedNumeric(logger as Test.Logger) as Lang.Boolean {
        var name = AppVersion.NAME;
        Test.assertMessage(name.length() > 0, "NAME is not empty");
        var dots = 0;
        for (var i = 0; i < name.length(); i += 1) {
            var ch = name.substring(i, i + 1) as Lang.String;
            if (ch.equals(".")) {
                dots += 1;
            } else {
                Test.assertMessage("0123456789".find(ch) != null,
                    "NAME must contain only digits and dots — got '" + name + "'");
            }
        }
        Test.assertMessage(dots >= 1, "NAME is dotted (e.g. 0.1.0) — got '" + name + "'");
        return true;
    }

    // The row shares DetailsView's ~28-char FONT_XTINY budget with every therapy row. It is appended
    // last, so it cannot push a therapy value off screen, but it must still not clip itself.
    (:test)
    function labelFitsTheDetailsRowBudget(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppVersion.label().length() <= 28,
            "the App row fits the FONT_XTINY budget — " + AppVersion.label());
        return true;
    }
}
