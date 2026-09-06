using Toybox.Lang;
using Toybox.Test;

// The phone-RESOLVED watch-intent gate. The watch no longer runs its own intensity policy — it maps the
// phone-resolved per-category intent map onto the wrist ladder. These pin:
//   • the effective-intent reduction: loudest recognized intent across the relayed categories;
//   • FAIL-SAFE (the required safety test): an absent/empty/malformed intent map resolves to "alert"
//     (the vibrating rung), never silence — an old phone that omits the field can never quiet the wrist;
//   • an explicit, recognized "off"/"quiet" for every category is honored;
//   • the wrist ladder maps off⇒nothing, quiet⇒visual-only, alert⇒vibrate, urgent⇒vibrate+tone;
//   • EVERY rung honors DND/vibrateOn (no breakthrough rung — the wrist never pierces DND);
//   • distinct per-severity haptic signatures (the feel is orthogonal to the on/off gate);
//   • fail-closed parse/restore of the phone-owned intent map (absent/garbage ⇒ last/fail-safe).
// The gate (AppState.effectiveWatchIntent / watchActionForIntent) is PURE — no Attention/DeviceSettings —
// so it is fully unit-testable. Style mirrors tests/AlertDismissCapTest.mc.
module AlertIntensityGateTest {

    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // ---- CX FAIL-SAFE (the required safety test): absent/empty/malformed intent map ⇒ "alert" ----
    (:test)
    function absentOrMalformedIntentFailsSafeToVibrate(logger as Test.Logger) as Lang.Boolean {
        // Absent field (a legacy host that never sent watchNotificationIntents) ⇒ "alert" (vibrate).
        Test.assertEqualMessage(AppState.effectiveWatchIntent(null), "alert", "absent map ⇒ fail safe to alert");
        // Empty map ⇒ "alert" (vibrate) — never silence.
        Test.assertEqualMessage(AppState.effectiveWatchIntent({}), "alert", "empty map ⇒ fail safe to alert");
        // A malformed/unrecognized token contributes at the "alert" rank, never below it.
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "bogus" }), "alert",
            "unrecognized token ⇒ fail safe to alert");
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "off", "b" => "bogus" }), "alert",
            "one malformed among explicit-off still fails safe to alert (never silenced by garbage)");
        // A non-string value cannot be a token — sanitizeWatchIntents drops it; an all-dropped map is empty
        // and fails safe to alert.
        Test.assertEqualMessage(
            AppState.effectiveWatchIntent(AppState.sanitizeWatchIntents({ "a" => 7 })), "alert",
            "non-string value dropped ⇒ empty ⇒ fail safe to alert");
        // And the fail-safe intent maps to a real vibrate on a device not in DND.
        var act = AppState.watchActionForIntent("alert", true, false, "critical");
        Test.assertMessage(act["vibrate"] && !act["tone"], "fail-safe alert ⇒ vibrate (no tone)");
        return true;
    }

    // ---- effective intent = LOUDEST recognized across the relayed categories --------------------
    (:test)
    function effectiveIntentIsLoudestAcrossCategories(logger as Test.Logger) as Lang.Boolean {
        // An explicit, recognized "off" for EVERY category is honored (user's own choice).
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "off", "b" => "off" }), "off",
            "all-off is honored (an explicit choice, not a fail-safe)");
        // All "quiet" ⇒ quiet (visual only).
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "quiet", "b" => "quiet" }), "quiet",
            "all-quiet ⇒ quiet");
        // Mixed ⇒ the loudest recognized rung wins (fail toward the wearer).
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "off", "b" => "quiet", "c" => "alert" }),
            "alert", "off<quiet<alert ⇒ loudest is alert");
        Test.assertEqualMessage(AppState.effectiveWatchIntent({ "a" => "alert", "b" => "urgent" }),
            "urgent", "urgent outranks alert");
        return true;
    }

    // ---- the wrist ladder: off/quiet/alert/urgent ⇒ nothing/visual/vibrate/vibrate+tone ---------
    (:test)
    function watchLadderMapsIntentToAnnunciation(logger as Test.Logger) as Lang.Boolean {
        // off ⇒ nothing.
        var off = AppState.watchActionForIntent("off", true, false, "critical");
        Test.assertMessage(!off["vibrate"] && !off["tone"] && !off["backlight"], "off ⇒ nothing");
        // quiet ⇒ visual only (no vibrate, no tone).
        var quiet = AppState.watchActionForIntent("quiet", true, false, "critical");
        Test.assertMessage(!quiet["vibrate"] && !quiet["tone"] && !quiet["backlight"], "quiet ⇒ visual only");
        // alert ⇒ vibrate, no tone.
        var alert = AppState.watchActionForIntent("alert", true, false, "high");
        Test.assertMessage(alert["vibrate"] && !alert["tone"], "alert ⇒ vibrate (no tone)");
        Test.assertEqualMessage(alert["vibeProfileKey"], "high", "vibe feel key carried through");
        // urgent ⇒ vibrate + tone (defensive rung).
        var urgent = AppState.watchActionForIntent("urgent", true, false, "critical");
        Test.assertMessage(urgent["vibrate"] && urgent["tone"] && urgent["backlight"], "urgent ⇒ vibrate+tone");
        return true;
    }

    // ---- parse the intent map off statusRead, persist it, and restore it on a cold launch -------
    (:test)
    function watchIntentsParseAndRoundTrip(logger as Test.Logger) as Lang.Boolean {
        AppState.watchNotificationIntents = {};
        // A valid map is adopted (string→string; unrecognized values are kept for the resolver to fail
        // safe) AND persisted; loadPrefs restores it after a simulated cold launch.
        AppState.handle(statusRead({ "watchNotificationIntents" =>
            { "deliveryStopped" => "alert", "pumpRoutine" => "off", "glucoseAndControlIQ" => "quiet" } }));
        Test.assertEqualMessage(AppState.watchNotificationIntents["deliveryStopped"], "alert", "valid map adopted");
        Test.assertEqualMessage(AppState.watchNotificationIntents["pumpRoutine"], "off", "explicit off kept");
        Test.assertEqualMessage(AppState.effectiveWatchIntent(AppState.watchNotificationIntents), "alert",
            "loudest across the adopted map is alert");

        AppState.watchNotificationIntents = {};   // simulate a cold launch (compile-time default)
        AppState.loadPrefs();
        Test.assertEqualMessage(AppState.watchNotificationIntents["deliveryStopped"], "alert",
            "restored map from Storage");
        Test.assertEqualMessage(AppState.watchNotificationIntents["glucoseAndControlIQ"], "quiet",
            "restored quiet entry from Storage");

        // A non-Dictionary payload is ignored (keeps the last map) — never a crash, never a reset to silence.
        AppState.handle(statusRead({ "watchNotificationIntents" => "bogus" }));
        Test.assertEqualMessage(AppState.watchNotificationIntents["deliveryStopped"], "alert",
            "non-dictionary payload ignored, keeps last map");
        return true;
    }

    // ---- DND honored on every rung (no breakthrough — the wrist never pierces DND) ---------------
    (:test)
    function everyRungHonorsDnd(logger as Test.Logger) as Lang.Boolean {
        // alert under DND ⇒ no vibrate.
        var a = AppState.watchActionForIntent("alert", true, true, "critical");
        Test.assertMessage(!a["vibrate"] && !a["tone"], "alert honors DND (no breakthrough rung)");
        // alert with vibrateOn=false ⇒ no vibrate.
        var b = AppState.watchActionForIntent("alert", false, false, "high");
        Test.assertMessage(!b["vibrate"], "alert honors vibrateOn=off");
        // even the defensive urgent rung honors DND (the wrist has no DND-pierce concept).
        var c = AppState.watchActionForIntent("urgent", true, true, "critical");
        Test.assertMessage(!c["vibrate"] && !c["tone"], "urgent honors DND too (no breakthrough)");
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

    // ---- unknown-severity feel classification stays highest-salience -----------------------------
    (:test)
    function unknownSeverityClassifiesToCriticalFeel(logger as Test.Logger) as Lang.Boolean {
        // An alert with no `severity` classifies to "critical" for the haptic FEEL (highest salience). This
        // never decides whether the wrist annunciates — that is the phone-resolved intent's job — it only
        // picks the vibe pattern once the intent has permitted a vibrate.
        var unknownTier = AppState.alertSeverityTier({ "id" => 1, "kind" => 2, "title" => "x" });  // no severity
        Test.assertEqualMessage(unknownTier, "critical", "unknown severity ⇒ classified critical (feel)");
        var act = AppState.watchActionForIntent("alert", true, false, unknownTier);
        Test.assertEqualMessage(act["vibeProfileKey"], "critical", "unknown-severity feel drives the triple-long pattern");
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

    // The CLOSED-app background surface consults the phone-resolved intent — an explicit "off"
    // suppresses the system notification (the phone is the sole alerting surface); every louder rung
    // surfaces the visual notification. FAIL-SAFE: an absent/malformed map resolved to "alert" upstream, so
    // a legacy host still surfaces the closed-app safety net.
    (:test)
    function backgroundSurfaceFollowsResolvedIntent(logger as Test.Logger) as Lang.Boolean {
        // Explicit "off" ⇒ nothing surfaces in the background.
        Test.assertMessage(!AppState.shouldSurfaceIntentInBackground("off"),
            "NEGATIVE: off ⇒ closed-app path surfaces nothing");
        // quiet/alert/urgent ⇒ surface the visual notification.
        Test.assertMessage(AppState.shouldSurfaceIntentInBackground("quiet"),
            "quiet ⇒ background surface intact (visual)");
        Test.assertMessage(AppState.shouldSurfaceIntentInBackground("alert"),
            "alert ⇒ background surface intact");
        Test.assertMessage(AppState.shouldSurfaceIntentInBackground("urgent"),
            "urgent ⇒ background surface intact");
        // FAIL-SAFE end to end: an absent map resolves to "alert" and therefore surfaces.
        Test.assertMessage(
            AppState.shouldSurfaceIntentInBackground(AppState.effectiveWatchIntent(null)),
            "absent map ⇒ fail safe ⇒ closed-app path still surfaces the safety net");
        return true;
    }
}
