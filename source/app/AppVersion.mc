using Toybox.Lang;

// THE single runtime source of truth for this watch app's version, surfaced as a Details row so the owner
// can tell WHICH BUILD IS ON THE WRIST while debugging. That is the entire point of it: before this,
// faBolusGarmin carried no version anywhere, so two watch builds were indistinguishable at a glance and a
// device report could not be tied to a specific binary.
//
// SCHEME — mirror faBolus's MARKETING_VERSION, plus a Garmin-local build number:
//   • NAME  tracks faBolus's `Config.xcconfig` MARKETING_VERSION EXACTLY, deliberately. faBolusGarmin
//     ships in lockstep with the app (BRANCHES.md §1.3), so a Garmin-only product version would be a
//     second, competing answer to "which release is this?". NAME is not independent and must not drift:
//     scripts/check-version-sync.sh fails the build when it does not equal MARKETING_VERSION.
//   • BUILD is Garmin-LOCAL and is what actually distinguishes two watch builds of the same release.
//     Increment it on every build/store upload worth telling apart. Because NAME is pinned to the app,
//     BUILD is the only field with the power to identify a wrist binary — do not skip bumping it.
//
// Connect IQ manifests carry no version attribute (the store versions its Official/Beta listings
// independently, which is why CHANGELOG.md tracks tags rather than SemVer), so this constant — not the
// manifest — is the only place a version exists in the app. Format is pinned by
// tests/AppVersionTest.mc so the Details row can never silently become "App: null ()".
module AppVersion {

    // Keep EQUAL to faBolus Config.xcconfig MARKETING_VERSION (guarded by scripts/check-version-sync.sh).
    const NAME = "0.1.0";

    // Garmin-local build counter. Bump on every build worth distinguishing; never reset.
    const BUILD = 1;

    // The Details row label, e.g. "App: 0.1.0 (1)" — 14 chars at the current version, comfortably inside
    // the ~28-char FONT_XTINY row budget DetailsView documents. Pure → unit-testable.
    function label() as Lang.String {
        return "App: " + NAME + " (" + BUILD.toString() + ")";
    }
}
