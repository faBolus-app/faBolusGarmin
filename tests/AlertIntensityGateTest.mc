using Toybox.Lang;
using Toybox.Test;

// The phone-synced, fail-closed WATCH alert gate. These pin:
//   • DEFAULT vibration-only for every severity (nothing audible, nothing DND-piercing unopted);
//   • fail-closed parse/restore of the phone-owned setting (absent/garbage ⇒ "vibrate");
//   • audible tone+backlight only for opted-in severities that pass the DND gate;
//   • distinct per-severity haptic signatures;
//   • vibrateOn/doNotDisturb awareness + the opt-in critical-DND override;
//   • the FULLY-SILENT guarantee (Silent + override-off ⇒ ZERO output for ANY tier incl. critical);
//   • the explicit-Silent-choice-wins rule (unknown⇒critical classification never resurrects Silent output).
// The gate (AppState.alertActionFor) is PURE — no Attention/DeviceSettings — so it is fully unit-testable.
// Style mirrors tests/AlertDismissCapTest.mc.
module AlertIntensityGateTest {

    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // Reset the three settings fields to their compile-time defaults for an isolated test.
    function resetDefaults() as Void {
        AppState.alertIntensityMode = "vibrate";
        AppState.alertAudibleMinSeverity = "critical";
        AppState.alertCriticalOverridesDnd = false;
    }

    // ---- DEFAULT: vibration-only for every tier -------------------------------------------------
    (:test)
    function defaultIsVibrationOnlyEveryTier(logger as Test.Logger) as Lang.Boolean {
        resetDefaults();
        var tiers = ["info", "high", "critical"];
        for (var i = 0; i < tiers.size(); i += 1) {
            var a = AppState.alertActionFor(tiers[i], "vibrate", "critical", false, true, false);
            Test.assertMessage(a["vibrate"], "default vibrates (" + tiers[i] + ")");
            Test.assertMessage(!a["tone"], "default no tone (" + tiers[i] + ")");
            Test.assertMessage(!a["backlight"], "default no backlight (" + tiers[i] + ")");
        }
        return true;
    }

    // ---- Fail-closed parse + persisted-then-restored round-trip ----------------------------------
    (:test)
    function parseFailsClosedAndRoundTrips(logger as Test.Logger) as Lang.Boolean {
        resetDefaults();
        // Absent ⇒ keep defaults.
        AppState.handle(statusRead({ "message" => "Connected" }));
        Test.assertEqualMessage(AppState.alertIntensityMode, "vibrate", "absent ⇒ default vibrate");
        Test.assertEqualMessage(AppState.alertAudibleMinSeverity, "critical", "absent ⇒ default floor");
        Test.assertMessage(!AppState.alertCriticalOverridesDnd, "absent ⇒ override off");

        // Malformed ⇒ ignored, keeps the safe default.
        AppState.handle(statusRead({ "alertIntensityMode" => "bogus", "alertCriticalOverridesDnd" => "yes" }));
        Test.assertEqualMessage(AppState.alertIntensityMode, "vibrate", "unrecognized mode ⇒ stays vibrate");
        Test.assertMessage(!AppState.alertCriticalOverridesDnd, "non-boolean override ignored");

        // Valid ⇒ adopted AND persisted; loadPrefs restores it after a simulated cold launch.
        AppState.handle(statusRead({ "alertIntensityMode" => "audible",
                                     "alertAudibleMinSeverity" => "high",
                                     "alertCriticalOverridesDnd" => true }));
        Test.assertEqualMessage(AppState.alertIntensityMode, "audible", "valid mode adopted");
        Test.assertEqualMessage(AppState.alertAudibleMinSeverity, "high", "valid floor adopted");
        Test.assertMessage(AppState.alertCriticalOverridesDnd, "valid override adopted");

        resetDefaults();   // simulate a cold launch (compile-time defaults)
        AppState.loadPrefs();
        Test.assertEqualMessage(AppState.alertIntensityMode, "audible", "restored mode from Storage");
        Test.assertEqualMessage(AppState.alertAudibleMinSeverity, "high", "restored floor from Storage");
        Test.assertMessage(AppState.alertCriticalOverridesDnd, "restored override from Storage");
        return true;
    }

    // ---- R4: DND honored by default (nothing pierces DND unopted) --------------------------------
    (:test)
    function dndHonoredByDefault(logger as Test.Logger) as Lang.Boolean {
        // Critical alert, DND on, override OFF ⇒ no vibrate.
        var a = AppState.alertActionFor("critical", "vibrate", "critical", false, false, true);
        Test.assertMessage(!a["vibrate"], "critical honors DND when override off");
        Test.assertMessage(!a["tone"], "no tone under DND");
        // Routine alert with vibrateOn=false ⇒ no vibrate.
        var b = AppState.alertActionFor("high", "vibrate", "critical", false, false, false);
        Test.assertMessage(!b["vibrate"], "routine honors vibrateOn=off");
        return true;
    }

    // ---- R1: audible tone+backlight only for opted-in severities passing the DND gate -----------
    (:test)
    function audibleOnlyForOptedInSeverity(logger as Test.Logger) as Lang.Boolean {
        // audible + tier >= floor + DND gate passes ⇒ tone+backlight+vibrate.
        var a = AppState.alertActionFor("critical", "audible", "critical", false, true, false);
        Test.assertMessage(a["tone"] && a["backlight"] && a["vibrate"], "audible critical ⇒ tone+backlight");
        // audible but tier < floor ⇒ stays vibration-only (routine quiet).
        var b = AppState.alertActionFor("high", "audible", "critical", false, true, false);
        Test.assertMessage(!b["tone"] && !b["backlight"], "below floor ⇒ no tone");
        Test.assertMessage(b["vibrate"], "below floor still vibrates");
        // audible but DND blocks a critical not opted to pierce ⇒ nothing at all.
        var c = AppState.alertActionFor("critical", "audible", "critical", false, true, true);
        Test.assertMessage(!c["tone"] && !c["backlight"] && !c["vibrate"], "DND blocks audible critical unopted");
        return true;
    }

    // ---- F3: distinct per-severity haptic signatures ---------------------------------------------
    (:test)
    function severityHapticsAreDistinct(logger as Test.Logger) as Lang.Boolean {
        var info = AppState.vibePatternFor("info");
        var high = AppState.vibePatternFor("high");
        var crit = AppState.vibePatternFor("critical");
        Test.assertEqualMessage(info.size(), 1, "info ⇒ single-short");
        Test.assertEqualMessage(high.size(), 2, "high ⇒ double");
        Test.assertEqualMessage(crit.size(), 3, "critical ⇒ triple-long");
        Test.assertMessage(info.size() != high.size() && high.size() != crit.size(), "all three distinct");
        return true;
    }

    // ---- R4: opt-in critical DND override --------------------------------------------------------
    (:test)
    function criticalOverridePiercesOnlyWhenOptedIn(logger as Test.Logger) as Lang.Boolean {
        var off = AppState.alertActionFor("critical", "vibrate", "critical", false, true, true);
        Test.assertMessage(!off["vibrate"], "override off ⇒ critical honors DND");
        var on = AppState.alertActionFor("critical", "vibrate", "critical", true, true, true);
        Test.assertMessage(on["vibrate"], "override on ⇒ critical pierces DND");
        return true;
    }

    // ---- FULLY-SILENT GUARANTEE (the required safety test) ----------------------------------------
    (:test)
    function fullySilentGuarantee(logger as Test.Logger) as Lang.Boolean {
        // Silent + override OFF ⇒ ZERO output for critical AND for an unknown-severity alert (which
        // alertSeverityTier resolves to "critical"). There must be NO code path that forces output here.
        var crit = AppState.alertActionFor("critical", "silent", "critical", false, true, false);
        Test.assertMessage(!crit["vibrate"] && !crit["tone"] && !crit["backlight"],
            "NEGATIVE: Silent+override-off ⇒ zero output for critical");
        var unknownTier = AppState.alertSeverityTier({ "id" => 1, "kind" => 2, "title" => "x" });  // no severity
        Test.assertEqualMessage(unknownTier, "critical", "unknown severity ⇒ classified critical");
        var unk = AppState.alertActionFor(unknownTier, "silent", "critical", false, true, false);
        Test.assertMessage(!unk["vibrate"] && !unk["tone"] && !unk["backlight"],
            "NEGATIVE: Silent+override-off ⇒ zero output for unknown-severity alert");
        return true;
    }

    // ---- Silent + opt-in ⇒ critical-only wrist vibration fallback (never a tone) -----------------
    (:test)
    function silentOptInGivesCriticalVibrateOnly(logger as Test.Logger) as Lang.Boolean {
        var crit = AppState.alertActionFor("critical", "silent", "critical", true, true, false);
        Test.assertMessage(crit["vibrate"], "Silent+override-on ⇒ critical vibrates");
        Test.assertMessage(!crit["tone"] && !crit["backlight"], "Silent never plays a tone");
        var routine = AppState.alertActionFor("high", "silent", "critical", true, true, false);
        Test.assertMessage(!routine["vibrate"] && !routine["tone"], "Silent+override-on ⇒ non-critical stays silent");
        return true;
    }

    // ---- severity classification + sanitizeAlerts preservation -----------------------------------
    (:test)
    function severityClassificationAndSanitize(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(AppState.alertSeverityTier({ "severity" => "info" }), "info", "valid tier kept");
        Test.assertEqualMessage(AppState.alertSeverityTier({ "severity" => "bogus" }), "critical", "garbage ⇒ critical");
        // sanitizeAlerts preserves a valid severity, drops a garbage one, leaves absent absent.
        var out = AppState.sanitizeAlerts([
            { "id" => 1, "kind" => 2, "title" => "a", "severity" => "high" },
            { "id" => 3, "kind" => 4, "title" => "b", "severity" => "bogus" },
            { "id" => 5, "kind" => 6, "title" => "c" }
        ]);
        Test.assertEqualMessage(out.size(), 3, "all three well-formed alerts kept");
        Test.assertEqualMessage(out[0]["severity"], "high", "valid severity preserved");
        Test.assertMessage(out[1]["severity"] == null, "garbage severity dropped");
        Test.assertMessage(out[2]["severity"] == null, "absent severity stays absent");
        return true;
    }

    // The batch escalation tier must scan the FULL new-alert list, so a critical arriving
    // BEYOND the 4-row display cap still drives escalation. mostSevereTier takes the max over the whole
    // list; notifyNewAlerts now passes `newAlerts` (not the capped `toPush`).
    (:test)
    function mostSevereTierScansPastDisplayCap(logger as Test.Logger) as Lang.Boolean {
        var batch = [
            { "id" => 1, "kind" => 0, "title" => "a", "severity" => "info" },
            { "id" => 2, "kind" => 0, "title" => "b", "severity" => "info" },
            { "id" => 3, "kind" => 0, "title" => "c", "severity" => "info" },
            { "id" => 4, "kind" => 0, "title" => "d", "severity" => "info" },
            { "id" => 5, "kind" => 0, "title" => "URGENT LOW", "severity" => "critical" }   // beyond the 4-cap
        ];
        Test.assertEqualMessage(AppState.mostSevereTier(batch), "critical",
            "a critical past the 4-row display cap still sets the batch tier to critical");
        return true;
    }

    // The CLOSED-app background surface honors Silent — Silent+override-off ⇒ NO
    // background notification for ANY tier (incl. critical); Silent+override-on ⇒ ONLY critical surfaces;
    // vibrate/audible ⇒ always surface (the background-surface safety net).
    (:test)
    function backgroundSurfaceHonorsSilent(logger as Test.Logger) as Lang.Boolean {
        // Silent + override OFF ⇒ nothing surfaces, even critical.
        Test.assertMessage(!AppState.shouldSurfaceInBackground("critical", "silent", false),
            "NEGATIVE: Silent+override-off ⇒ critical does NOT surface in background");
        Test.assertMessage(!AppState.shouldSurfaceInBackground("high", "silent", false),
            "NEGATIVE: Silent+override-off ⇒ high does not surface");
        // Silent + override ON ⇒ only critical surfaces.
        Test.assertMessage(AppState.shouldSurfaceInBackground("critical", "silent", true),
            "Silent+override-on ⇒ critical surfaces (opt-in wrist fallback)");
        Test.assertMessage(!AppState.shouldSurfaceInBackground("high", "silent", true),
            "Silent+override-on ⇒ only critical, not high");
        // Non-silent ⇒ always surface (safety net intact).
        Test.assertMessage(AppState.shouldSurfaceInBackground("info", "vibrate", false),
            "vibrate mode ⇒ background surface intact");
        Test.assertMessage(AppState.shouldSurfaceInBackground("critical", "audible", false),
            "audible mode ⇒ background surface intact");
        return true;
    }
}
