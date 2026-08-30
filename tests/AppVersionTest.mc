using Toybox.Lang;
using Toybox.Test;

// The Details "App:" row exists for ONE reason: to tell the owner which watch build is on the wrist while
// debugging. A row that renders "App: null", or clips, or silently stops distinguishing two builds, is
// worse than no row at all — it would answer "which build is this?" WRONGLY, which is far harder to catch
// than a missing answer. So the format and the shape of the build stamp are pinned here.
//
// What is deliberately NOT pinned: the literal VALUES. NAME tracks faBolus's MARKETING_VERSION in
// lockstep (BRANCHES.md §1.3) and changes on every app release; AppRevision.SHORT changes on every
// commit. Asserting either literal here would make routine work fail the suite for no safety reason.
// Those are facts about the world outside the unit binary, and are checked where that world is available
// — scripts/check-version-sync.sh (NAME against the app repo's xcconfig; the stamp against `git`), which
// the unit binary cannot do (it has no filesystem access and no git). This file pins the SHAPE; that
// script pins the VALUES.
module AppVersionTest {

    // "App: <name> · <revision>" plus a "+" when the build tree was dirty — the exact row DetailsView
    // appends. Composed independently here rather than by calling labelFor(), so a change to the format
    // has to be made in two places on purpose instead of one place by accident.
    (:test)
    function labelFormatIsPinned(logger as Test.Logger) as Lang.Boolean {
        var expected = "App: " + AppVersion.NAME + " · " + AppRevision.SHORT
                       + (AppRevision.DIRTY ? "+" : "");
        Test.assertEqualMessage(AppVersion.label(), expected, "the row is 'App: <name> · <revision>'");
        Test.assertMessage(AppVersion.label().find("App: ") == 0, "the row is prefixed 'App: '");
        Test.assertMessage(AppVersion.label().find(" · ") != null, "name and revision are separated");
        Test.assertMessage(AppVersion.label().find(AppRevision.SHORT) != null, "the revision is shown");
        return true;
    }

    // The build commit is the field that actually distinguishes two watch builds of the same release, so
    // its shape is load-bearing. It is either the seven leading hex characters of the commit, or the
    // literal "unknown" when the build happened outside a git checkout — never a guess. Fixed width is
    // what lets the row's width budget below be reasoned about at all: NAME is then the only term that
    // can grow. "unknown" shares that width and contains no hex-only character, so it can never be
    // mistaken for a real hash.
    (:test)
    function revisionIsSevenHexCharsOrHonestlyUnknown(logger as Test.Logger) as Lang.Boolean {
        var rev = AppRevision.SHORT;
        Test.assertMessage(rev instanceof Lang.String, "SHORT is a String");
        if (rev.equals("unknown")) {
            return true;
        }
        Test.assertMessage(rev.length() == 7,
            "SHORT is seven hex characters (or 'unknown') — got '" + rev + "'");
        for (var i = 0; i < rev.length(); i += 1) {
            var ch = rev.substring(i, i + 1) as Lang.String;
            Test.assertMessage("0123456789abcdef".find(ch) != null,
                "SHORT is lowercase hex — got '" + rev + "'");
        }
        return true;
    }

    // The dirty marker is the difference between "this is commit abc1234" and "this is commit abc1234
    // plus edits nobody can see" — a hash on its own would misdescribe the second. Pin that it is exactly
    // one trailing character and that a clean build carries none, so the marker cannot quietly vanish
    // (making a dirty build look reproducible) or quietly appear on every build (making it meaningless).
    (:test)
    function dirtyTreeAddsExactlyOneTrailingMarker(logger as Test.Logger) as Lang.Boolean {
        var clean = AppVersion.labelFor("0.0.0", "abcdef0", false);
        var dirty = AppVersion.labelFor("0.0.0", "abcdef0", true);
        Test.assertMessage(clean.find("+") == null, "a clean build carries no marker — " + clean);
        // Compared as whole strings rather than by indexing at clean.length(): the row contains a
        // multi-byte separator, and this pins "exactly one, trailing" without depending on whether
        // length() and substring() agree about characters versus bytes.
        Test.assertEqualMessage(dirty, clean + "+", "the marker is a single trailing '+'");
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
    //
    // Checked twice: today's actual row, and a worst case built through labelFor(). The worst case is the
    // one that matters, because it proves HEADROOM rather than luck — the revision is fixed width, so
    // NAME is the only term that can grow, and a version as wide as a three-digit triplet still fits
    // even with the dirty marker. Without this second assertion the budget would only be re-verified on
    // the release that happened to break it.
    (:test)
    function labelFitsTheDetailsRowBudget(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(AppVersion.label().length() <= 28,
            "the App row fits the FONT_XTINY budget — " + AppVersion.label());
        var widest = AppVersion.labelFor("100.200.300", "abcdef0", true);
        Test.assertMessage(widest.length() <= 28,
            "the widest plausible version still fits — " + widest);
        return true;
    }
}
