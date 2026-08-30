using Toybox.Lang;

// THE single runtime source of truth for this watch app's version, surfaced as a Details row so the owner
// can tell WHICH BUILD IS ON THE WRIST while debugging. That is the entire point of it: before this,
// faBolusGarmin carried no version anywhere, so two watch builds were indistinguishable at a glance and a
// device report could not be tied to a specific binary.
//
// SCHEME — mirror faBolus's MARKETING_VERSION, plus the build commit:
//   • NAME  tracks faBolus's `Config.xcconfig` MARKETING_VERSION EXACTLY, deliberately. faBolusGarmin
//     ships in lockstep with the app (BRANCHES.md §1.3), so a Garmin-only product version would be a
//     second, competing answer to "which release is this?". NAME is not independent and must not drift:
//     scripts/check-version-sync.sh fails when it does not equal MARKETING_VERSION.
//   • The build COMMIT is what actually distinguishes two watch builds of the same release, and it is
//     DERIVED rather than remembered — AppRevision (source/generated/AppRevision.mc) is rewritten from
//     `git` by scripts/stamp-revision.sh immediately before every compile. This deliberately replaced a
//     hand-edited build counter, because a counter is only as good as the discipline behind it: the day
//     somebody forgets to bump it, two different binaries both claim the same build and the row starts
//     answering "which build is this?" WRONGLY — worse than carrying no version at all, and far harder to
//     notice than a missing row. Nothing to remember now, and nothing that can go stale: the stamp is
//     regenerated per build, is git-ignored so it can never be committed at a frozen value, and its
//     absence is a COMPILE error rather than a silently unstamped binary.
//   • A trailing "+" means the build tree carried uncommitted changes, so the hash alone would
//     misdescribe it. AppRevision.SHORT reads "unknown" outside a git checkout, which is honest about
//     not knowing instead of guessing.
//
// Connect IQ manifests carry no version attribute (the store versions its Official/Beta listings
// independently, which is why CHANGELOG.md tracks tags rather than SemVer), so these constants — not the
// manifest — are the only place a version exists in the app. Format is pinned by tests/AppVersionTest.mc
// so the Details row can never silently become "App: null".
module AppVersion {

    // Keep EQUAL to faBolus Config.xcconfig MARKETING_VERSION (guarded by scripts/check-version-sync.sh).
    const NAME = "0.1.0";

    // The Details row label, e.g. "App: 0.1.0 · 6f60fa9" — 20 chars at the current version, 21 with the
    // dirty marker, comfortably inside the ~28-char FONT_XTINY row budget DetailsView documents. Pure →
    // unit-testable.
    //
    // If this line fails to compile with "Undefined symbol ':AppRevision'", the generated stamp is simply
    // missing: run `./scripts/stamp-revision.sh` (every build script here already does it for you).
    function label() as Lang.String {
        return labelFor(NAME, AppRevision.SHORT, AppRevision.DIRTY);
    }

    // Split out from label() so the row's width can be tested against a worst-case version string rather
    // than only against whatever NAME happens to be today: the generated half is fixed-width, so NAME is
    // the only term that can grow, and even a three-digit-triplet version leaves the budget intact.
    function labelFor(name as Lang.String, revision as Lang.String,
                      dirty as Lang.Boolean) as Lang.String {
        return "App: " + name + " · " + revision + (dirty ? "+" : "");
    }
}
