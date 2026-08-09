using Toybox.Lang;
using Toybox.Test;

// B2 (S1 + O3): the pump's automatic-correction DISCLOSURE, derived LOCALLY on the watch from the
// controller identity/runtime-on-off the phone pushes (controllerVariant / controlIQEnabled) plus the
// glucose + trend already on the same statusRead. A Monkey C hand-port of faBolusCore
// ControllerDescriptor + AutoCorrectionDisclosure — these tests pin the SAME facts the Swift
// AutoCorrectionDisclosureTests do: the mechanism gate (both strings vanish for a no-controller pump and
// when Control-IQ is off at runtime), the S1 high/rising trigger boundaries (180 always, 150 when the
// pump's own arrow is rising), the exact verbatim contract copy, and the single-slot S1-over-O3 priority.
// DISPLAY-ONLY: every function returns a string to show (or "") — nothing here gates a bolus. Style
// mirrors tests/CanBolusTest.mc / tests/RangeColorTest.mc. AppState is compiled into the test binary
// (test.jungle); the view (BolusView) is not, which is why the derivation lives in AppState.
module ControllerDisclosureTest {

    // The two verbatim strings the cross-surface contract fixes (must match faBolusCore byte-for-byte).
    const O3_CIQ    = "Control-IQ automatic correction is active.";
    const O3_CIQPRO = "Control-IQ+ automatic correction is active.";
    const S1_CIQ    = "Bolusing now pauses Control-IQ's automatic correction for about 60 min.";
    const S1_CIQPRO = "Bolusing now pauses Control-IQ+'s automatic correction for about 60 min.";

    // A minimal statusRead envelope carrying `extra`'s keys (mirrors CanBolusTest.statusRead).
    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // MARK: no controller — both strings are always empty, whatever the glucose/trend.
    (:test)
    function noControllerNeverDiscloses(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.controllerAmbientText("none", true), "", "none → no ambient");
        Test.assertEqualMessage(AppState.controllerLockoutText("none", true, 300, "upup"), "",
            "none → no lockout even at high+rising");
        return true;
    }

    // MARK: a capable controller turned OFF at runtime — both empty.
    (:test)
    function controllerDisabledAtRuntimeNeverDiscloses(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.controllerAmbientText("controlIQ", false), "",
            "CIQ off → no ambient");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", false, 250, "up"), "",
            "CIQ off → no lockout");
        Test.assertEqualMessage(AppState.controllerAmbientText("controlIQPro", false), "",
            "CIQ+ off → no ambient");
        return true;
    }

    // MARK: O3 ambient copy — glucose-independent, exact per variant.
    (:test)
    function ambientCopyIsVerbatimPerVariant(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.controllerAmbientText("controlIQ", true), O3_CIQ, "O3 CIQ verbatim");
        Test.assertEqualMessage(AppState.controllerAmbientText("controlIQPro", true), O3_CIQPRO,
            "O3 CIQ+ verbatim");
        return true;
    }

    // MARK: S1 trigger boundaries (mirror AutoCorrectionDisclosureTests).
    (:test)
    function highFlatGlucoseDisclosesLockout(logger as Test.Logger) as Lang.Boolean {
        // 185 flat: at/above the always-disclose threshold, trend irrelevant.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 185, "flat"), S1_CIQ,
            "185 flat → S1");
        // 180 boundary flat → discloses (>=).
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 180, "flat"), S1_CIQ,
            "180 flat → S1 (closed lower edge of always-disclose)");
        // 179 flat → below 180 and not rising → no S1.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 179, "flat"), "",
            "179 flat → no S1");
        return true;
    }

    (:test)
    function risingElevatedGlucoseBoundaries(logger as Test.Logger) as Lang.Boolean {
        // 150 rising (boundary): at/above the rising threshold AND the pump's arrow is rising → S1.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 150, "up45"), S1_CIQ,
            "150 rising → S1 (closed lower edge of rising-disclose)");
        // 160 rising: below 180 but rising-and-elevated → S1.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 160, "up45"), S1_CIQ,
            "160 rising → S1");
        // 160 flat: elevated but not rising and below 180 → no S1.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 160, "flat"), "",
            "160 flat → no S1");
        // 149 rising: below the rising threshold → no S1.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 149, "up45"), "",
            "149 rising → no S1");
        return true;
    }

    (:test)
    function risingArrowSetMatchesThePumpsOwnArrows(logger as Test.Logger) as Lang.Boolean {
        // The rising set is the pump's own ↑/⇈/↗ arrows (up / upup / up45) — all trigger at 150.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, "up"), S1_CIQ,
            "up counts as rising");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, "upup"), S1_CIQ,
            "upup counts as rising");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, "up45"), S1_CIQ,
            "up45 counts as rising");
        // Falling / flat / empty at the same elevated value must NOT disclose (only rising does).
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, "down"), "",
            "down is not rising");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, "flat"), "",
            "flat is not rising");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 155, ""), "",
            "no/unknown arrow is not rising");
        return true;
    }

    (:test)
    function absentGlucoseSuppressesLockoutButAmbientStillShows(logger as Test.Logger) as Lang.Boolean {
        // O3 is glucose-independent; S1 needs a reading.
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, null, "up45"), "",
            "no reading → no S1");
        Test.assertEqualMessage(AppState.controllerAmbientText("controlIQ", true), O3_CIQ,
            "no reading → O3 still shows");
        return true;
    }

    // MARK: S1 copy verbatim per variant (incl. the controlIQPro-at-210 deliverable the orchestrator checks).
    (:test)
    function lockoutCopyIsVerbatimPerVariant(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQ", true, 200, "flat"), S1_CIQ,
            "S1 CIQ verbatim");
        Test.assertEqualMessage(AppState.controllerLockoutText("controlIQPro", true, 210, "flat"), S1_CIQPRO,
            "S1 CIQ+ verbatim at 210");
        return true;
    }

    // MARK: single-slot priority — controllerDisclosureLine() prefers S1, falls back to O3, else "".
    (:test)
    function disclosureLinePrefersS1ThenO3(logger as Test.Logger) as Lang.Boolean {
        // controlIQPro on, glucose 210 (S1 fires) → the line is S1 and flagged as a caution.
        AppState.handle(statusRead({ "controllerVariant" => "controlIQPro", "controlIQEnabled" => true,
                                     "bgMgdl" => 210, "trend" => "flat" }));
        Test.assertEqualMessage(AppState.controllerDisclosureLine(), S1_CIQPRO, "S1 wins when it fires");
        Test.assertMessage(AppState.controllerDisclosureIsCaution(), "S1 is a caution");

        // Same pump, in-range + flat (S1 does not fire) → the ambient O3 line, not a caution.
        AppState.handle(statusRead({ "bgMgdl" => 120, "trend" => "flat" }));
        Test.assertEqualMessage(AppState.controllerDisclosureLine(), O3_CIQPRO, "O3 when S1 quiet");
        Test.assertMessage(!AppState.controllerDisclosureIsCaution(), "O3 is not a caution");
        return true;
    }

    // MARK: statusRead PARSE — frozen-token variant + strict-boolean guards.
    (:test)
    function parsesVariantAndEnabledWithGuards(logger as Test.Logger) as Lang.Boolean {
        // Valid frozen tokens are adopted.
        AppState.handle(statusRead({ "controllerVariant" => "controlIQ", "controlIQEnabled" => true }));
        Test.assertEqualMessage(AppState.controllerVariant, "controlIQ", "parsed controlIQ");
        Test.assertMessage(AppState.controlIQEnabled, "parsed controlIQEnabled=true");

        // An UNKNOWN/garbage variant is ignored — the last good value stands (frozen-token guard).
        AppState.handle(statusRead({ "controllerVariant" => "controlIQPlus" }));
        Test.assertEqualMessage(AppState.controllerVariant, "controlIQ",
            "unknown variant ignored (keeps last)");

        // A non-boolean controlIQEnabled is ignored — the last value stands (strict boolean guard).
        AppState.handle(statusRead({ "controlIQEnabled" => "yes" }));
        Test.assertMessage(AppState.controlIQEnabled, "non-boolean ignored (keeps last true)");

        // "none" is a valid token and turns the disclosure off.
        AppState.handle(statusRead({ "controllerVariant" => "none" }));
        Test.assertEqualMessage(AppState.controllerVariant, "none", "parsed none");
        Test.assertEqualMessage(AppState.controllerDisclosureLine(), "", "none → nothing renders");
        return true;
    }
}
