using Toybox.Lang;
using Toybox.Test;

// The app-GENERATED (faBolus's own) watch-annunciation path. The watch annunciates the app-own subset
// (incl. the durable unresolved-dose record) CONSISTENTLY with the pump-mirror path, but resolved
// PER-CATEGORY: each relayed item carries its own namespaced key, so its watch intent is read individually
// from the phone-resolved map. These pin:
//   • the per-category resolver (appOwnWatchIntentFor) and its FAIL-SAFE: an absent map, an absent
//     key, or a malformed token ⇒ "alert" (the vibrating rung), never silence;
//   • an explicit, recognized "off"/"quiet" for a category is honored;
//   • the batch reduction (appOwnEffectiveIntent) = loudest across the new app-own set, empty ⇒ "off";
//   • parse of the appOwnAlerts relay off statusRead (Array adopted; empty clears; garbage keeps last);
//   • sanitizeAppOwnAlerts keeps only {key,title};
//   • the closed-app background surface follows the per-category intent and fails safe to surface.
// The resolver is PURE (no Attention/DeviceSettings) → fully unit-testable. Style mirrors
// tests/AlertIntensityGateTest.mc.
module AppOwnAlertGateTest {

    function statusRead(extra as Lang.Dictionary) as Lang.Dictionary {
        var d = { "kind" => "statusRead" };
        var keys = extra.keys();
        for (var i = 0; i < keys.size(); i += 1) { d[keys[i]] = extra[keys[i]]; }
        return d;
    }

    // ---- FAIL-SAFE: an app-own alert whose intent is absent/malformed ⇒ "alert" (vibrate) ------------
    (:test)
    function appOwnIntentFailsSafeToVibrate(logger as Test.Logger) as Lang.Boolean {
        // Absent map entirely (a legacy host / stale-empty prefs) ⇒ every app-own key fails safe to alert.
        AppState.watchNotificationIntents = {};
        Test.assertEqualMessage(AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate"), "alert",
            "absent map ⇒ app-own fail safe to alert");
        // A populated map missing THIS category's key ⇒ still fail safe to alert.
        AppState.watchNotificationIntents = { "appOwn:pumpDisconnect" => "quiet" };
        Test.assertEqualMessage(AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate"), "alert",
            "absent key ⇒ app-own fail safe to alert");
        // A malformed/unrecognized token ⇒ fail safe to alert.
        AppState.watchNotificationIntents = { "appOwn:bolusIndeterminate" => "bogus" };
        Test.assertEqualMessage(AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate"), "alert",
            "malformed token ⇒ app-own fail safe to alert");
        // Explicit recognized values are honored — including an intentional silence.
        AppState.watchNotificationIntents =
            { "appOwn:bolusIndeterminate" => "off", "appOwn:pumpDisconnect" => "quiet" };
        Test.assertEqualMessage(AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate"), "off",
            "explicit off is the user's own choice");
        Test.assertEqualMessage(AppState.appOwnWatchIntentFor("appOwn:pumpDisconnect"), "quiet",
            "explicit quiet honored verbatim");
        return true;
    }

    // ---- batch reduction: loudest across the new app-own set, resolved per-category ------------------
    (:test)
    function appOwnEffectiveIntentIsLoudestPerCategory(logger as Test.Logger) as Lang.Boolean {
        AppState.watchNotificationIntents = {
            "appOwn:bolusIndeterminate" => "alert",
            "appOwn:pumpDisconnect" => "off",
            "appOwn:cgmGap" => "quiet"
        };
        var list = [
            { "key" => "appOwn:pumpDisconnect", "title" => "Pump disconnected" },
            { "key" => "appOwn:cgmGap", "title" => "CGM gap" },
            { "key" => "appOwn:bolusIndeterminate", "title" => "Bolus outcome unknown" }
        ];
        Test.assertEqualMessage(AppState.appOwnEffectiveIntent(list), "alert",
            "loudest per-category intent across the new app-own set wins");
        // All-off across the set is honored (an explicit choice, not a fail-safe).
        AppState.watchNotificationIntents = { "appOwn:pumpDisconnect" => "off", "appOwn:cgmGap" => "off" };
        var allOff = [
            { "key" => "appOwn:pumpDisconnect", "title" => "x" },
            { "key" => "appOwn:cgmGap", "title" => "y" }
        ];
        Test.assertEqualMessage(AppState.appOwnEffectiveIntent(allOff), "off", "all-off honored");
        // One item with NO intent in the map still fails the batch safe to alert (never silenced by a gap).
        AppState.watchNotificationIntents = { "appOwn:pumpDisconnect" => "off" };
        var withGap = [
            { "key" => "appOwn:pumpDisconnect", "title" => "x" },
            { "key" => "appOwn:bolusIndeterminate", "title" => "unknown" }   // no key in map ⇒ alert
        ];
        Test.assertEqualMessage(AppState.appOwnEffectiveIntent(withGap), "alert",
            "an absent-intent app-own alert fails the batch safe to alert");
        // Empty set ⇒ "off" (nothing to annunciate).
        Test.assertEqualMessage(AppState.appOwnEffectiveIntent([]), "off", "empty ⇒ nothing");
        return true;
    }

    // ---- parse the appOwnAlerts relay off statusRead ------------------------------------------------
    (:test)
    function appOwnAlertsParseAndClear(logger as Test.Logger) as Lang.Boolean {
        AppState.appOwnAlerts = [];
        // A valid array is adopted; items keep only {key,title}.
        AppState.handle(statusRead({ "appOwnAlerts" =>
            [{ "key" => "appOwn:bolusIndeterminate", "title" => "Bolus outcome unknown" }] }));
        Test.assertEqualMessage(AppState.appOwnAlerts.size(), 1, "valid app-own relay adopted");
        Test.assertEqualMessage(AppState.appOwnAlerts[0]["key"], "appOwn:bolusIndeterminate", "key kept");
        Test.assertEqualMessage(AppState.appOwnAlerts[0]["title"], "Bolus outcome unknown", "title kept");
        // An empty array authoritatively CLEARS (an app-own condition that resolved on the phone drops off).
        AppState.handle(statusRead({ "appOwnAlerts" => [] }));
        Test.assertEqualMessage(AppState.appOwnAlerts.size(), 0, "empty array clears the app-own set");
        // A non-Array payload is ignored (keeps the last set) — a legacy host that predates the field.
        AppState.handle(statusRead({ "appOwnAlerts" =>
            [{ "key" => "appOwn:pumpDisconnect", "title" => "Pump disconnected" }] }));
        AppState.handle(statusRead({ "appOwnAlerts" => "bogus" }));
        Test.assertEqualMessage(AppState.appOwnAlerts.size(), 1, "non-array payload ignored, keeps last set");
        return true;
    }

    // ---- pump-mirror reduction must NOT fold in the app-own per-category keys -------------------------
    // effectiveWatchIntent drives the PUMP-mirror batch haptic. The same phone-resolved intent map also
    // carries the per-category app-own keys (namespaced "appOwn:*"), which are resolved individually
    // elsewhere. Folding them into the pump-mirror reduction lets an app-own "urgent" leak a tone onto a
    // pump alarm and un-silence a pump alert the wearer set to "off". The reduction must skip the app-own
    // keys — while still failing safe to "alert" when a map carries NO pump category (the consumers only
    // reach this path with a live pump alert, so an all-app-own map must never resolve to silence).
    (:test)
    function effectiveWatchIntentExcludesAppOwnKeys(logger as Test.Logger) as Lang.Boolean {
        // An app-own "urgent" must NOT un-silence a pump batch the wearer set to "off".
        Test.assertEqualMessage(AppState.effectiveWatchIntent(
            { "cgmLow" => "off", "appOwn:bolusIndeterminate" => "urgent" }), "off",
            "app-own urgent does not un-silence an off'd pump batch");
        // An app-own "urgent" must NOT raise an "alert" pump batch to "urgent" (no tone leak).
        Test.assertEqualMessage(AppState.effectiveWatchIntent(
            { "cgmLow" => "alert", "appOwn:bolusIndeterminate" => "urgent" }), "alert",
            "app-own urgent does not tone an alert pump batch");
        // A non-empty map with ONLY app-own keys (no pump category) fails safe to "alert", never silence.
        Test.assertEqualMessage(AppState.effectiveWatchIntent(
            { "appOwn:bolusIndeterminate" => "off", "appOwn:pumpDisconnect" => "quiet" }), "alert",
            "only-app-own map fails safe to alert");
        // A pump-only map is unchanged: loudest-across-categories still wins.
        Test.assertEqualMessage(AppState.effectiveWatchIntent(
            { "cgmLow" => "off", "cgmHigh" => "urgent" }), "urgent",
            "pump-only reduction unchanged (loudest wins)");
        // A pump-only all-off map is still honored as the wearer's explicit choice.
        Test.assertEqualMessage(AppState.effectiveWatchIntent(
            { "cgmLow" => "off", "cgmHigh" => "off" }), "off",
            "pump-only all-off honored");
        return true;
    }

    // ---- sanitizeAppOwnAlerts keeps only well-formed {key,title} items -------------------------------
    (:test)
    function sanitizeAppOwnAlertsDropsMalformed(logger as Test.Logger) as Lang.Boolean {
        var out = AppState.sanitizeAppOwnAlerts([
            { "key" => "appOwn:pumpDisconnect", "title" => "Pump disconnected" },
            { "title" => "no key" },                       // missing key ⇒ dropped
            { "key" => "appOwn:x" },                        // missing title ⇒ dropped
            { "key" => 7, "title" => "non-string key" },    // non-string key ⇒ dropped
            "not a dict"                                     // wrong type ⇒ dropped
        ]);
        Test.assertEqualMessage(out.size(), 1, "only the well-formed {key,title} item is kept");
        Test.assertEqualMessage(out[0]["key"], "appOwn:pumpDisconnect", "kept item's key");
        return true;
    }

    // ---- the persisted app-own key is length-bounded (truncates, never drops) ------------------------
    // A kept item's key is capped to 80 chars before it flows into the seen/bg-notified dedup sets, matching
    // how the title is already bounded — a malformed/oversized key can no longer bloat state, and no safety
    // item is dropped by the bound (it truncates, keeping the item annunciated).
    (:test)
    function sanitizeAppOwnAlertsBoundsKey(logger as Test.Logger) as Lang.Boolean {
        var longKey = "appOwn:";
        for (var i = 0; i < 120; i += 1) { longKey = longKey + "x"; }   // well over 80 chars
        var out = AppState.sanitizeAppOwnAlerts([
            { "key" => longKey, "title" => "Oversized key" },
            { "key" => "appOwn:bolusIndeterminate", "title" => "Short key" }
        ]);
        Test.assertEqualMessage(out.size(), 2, "both well-formed items are kept (bound truncates, never drops)");
        Test.assertEqualMessage(out[0]["key"].length(), 80, "oversized key is bounded to 80 chars");
        Test.assertEqualMessage(out[1]["key"], "appOwn:bolusIndeterminate", "a short key is stored unchanged");
        return true;
    }

    // ---- closed-app background surface follows the per-category intent, fails safe to surface --------
    (:test)
    function appOwnBackgroundSurfaceFailsSafeToSurface(logger as Test.Logger) as Lang.Boolean {
        // An app-own alert whose intent is absent from the map resolves to "alert" and therefore surfaces.
        AppState.watchNotificationIntents = {};
        var intent = AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate");
        Test.assertMessage(AppState.shouldSurfaceIntentInBackground(intent),
            "absent app-own intent ⇒ fail safe ⇒ closed-app path still surfaces the safety net");
        // An explicit "off" for that category keeps the closed-app path quiet.
        AppState.watchNotificationIntents = { "appOwn:bolusIndeterminate" => "off" };
        var off = AppState.appOwnWatchIntentFor("appOwn:bolusIndeterminate");
        Test.assertMessage(!AppState.shouldSurfaceIntentInBackground(off),
            "explicit off ⇒ closed-app path surfaces nothing for that app-own category");
        return true;
    }

    // ---- seen-set dedup: a genuinely-new app-own alert is new once, then not until it clears/re-fires -
    (:test)
    function appOwnSeenSetDedup(logger as Test.Logger) as Lang.Boolean {
        AppState.appOwnAlerts = [
            { "key" => "appOwn:pumpDisconnect", "title" => "Pump disconnected" }
        ];
        // Nothing seen yet ⇒ it is new.
        var newSince = AppState.newAppOwnSince([]);
        Test.assertEqualMessage(newSince.size(), 1, "an unseen app-own alert is new");
        // After it is marked seen (presented), it is no longer new.
        var seen = AppState.reconciledSeenAppOwn(["appOwn:pumpDisconnect"]);
        Test.assertEqualMessage(AppState.newAppOwnSince(seen).size(), 0, "a seen app-own alert is not new");
        // When it clears (drops out of the active set), the reconciled seen-set drops it too, so a re-fire
        // is treated as new again.
        AppState.appOwnAlerts = [];
        var afterClear = AppState.reconciledSeenAppOwn([]);
        Test.assertEqualMessage(afterClear.size(), 0, "a cleared app-own alert drops out of the seen-set");
        return true;
    }
}
