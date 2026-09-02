using Toybox.Lang;
using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Time;
using Toybox.System;
using Toybox.Application.Storage;

// Shared app state for the faBolus Garmin remote. Glance data comes from the phone
// (statusRead reply); carbs→units is computed locally from the pump's calculator settings so
// the hold-to-deliver screen can show the exact units.
module AppState {
    // Clinical glucose display bands (mg/dL), mirroring faBolusCore.GlucoseThresholds — the Battelino
    // 2019 international Time-in-Range consensus (70…180 in-range, 181…250 high, > 250 very-high).
    // Kept numerically identical across every surface; the closed-convention edges (180 in-range, 250
    // high) match the phone's coloring and its TIR stat. RangeColorTest pins those edges.
    (:background)
    const GLUCOSE_LOW = 70;
    (:background)
    const GLUCOSE_HIGH = 180;
    (:background)
    const GLUCOSE_VERY_HIGH = 250;

    // The Garmin hand-port of faBolusCore.GlucoseUnit — the ONLY place this factor may appear on the
    // Garmin side, mirroring the Swift canonical (Packages/faBolusCore/Sources/faBolusCore/GlucoseUnit.swift,
    // mgdlPerMmol = 18.0182). Pinned by GlucoseUnitTest.mc against the same expected strings the Swift
    // GlucoseUnitTests assert.
    (:background, :glance)
    const MGDL_PER_MMOL = 18.0182;
    // Display-unit wire token ("mgdl"|"mmol"), mirrored from the phone's statusRead reply
    // (RemoteCommand.glucoseDisplayUnit). This NEVER changes GLUCOSE_*/rangeColor()/the
    // canonical glucose/isf/targetBg Numbers themselves — it only selects which label
    // formatMgdl()/glucoseUnitLabel()/isfUnitLabel() render. Default "mgdl" is the fail-closed value:
    // an absent field (legacy host) or an unrecognized token is never adopted (see handle()
    // below), so a fresh install / older phone build always renders mg/dL.
    (:background)
    var glucoseUnit as Lang.String = "mgdl";

    // HUD data (from phone)
    (:background)
    var glucose as Lang.Number? = null;   // mg/dL
    (:background)
    var trend as Lang.String = "";
    (:background)
    var iob as Lang.Float = 0.0;          // units
    (:background)
    var carbRatio as Lang.Float = 0.0;    // g/u
    (:background)
    var isf as Lang.Number = 0;           // mg/dL per unit
    (:background)
    var targetBg as Lang.Number = 0;      // mg/dL
    (:background)
    var maxUnits as Lang.Float = 25.0;
    // Current basal delivery rate (units/hr), mirrored from the phone's `basalRate` — NOT persisted
    // (mirrors `iob`'s own not-persisted, refreshed-every-sync pattern), so a cold launch shows 0.0
    // until the first statusRead lands rather than a stale rate. Paired with `maxBasalUnitsPerHour`
    // below to compute the "% of your configured max basal rate" text row LOCALLY — the % itself is
    // never received pre-rendered.
    (:background)
    var basalRate as Lang.Float = 0.0;
    // Extra pump status (from phone) for the details screen.
    (:background)
    var reservoir as Lang.Float = -1.0;   // units remaining (-1 = unknown)
    (:background)
    var battery as Lang.Number = -1;      // percent (-1 = unknown)
    // The pump's charging state, mirrored from the phone's `RemoteCommand.batteryCharging` (op-145
    // `chargingStatus == 1` — see faBolus's docs/UNVERIFIED-GUESSES.md, the live on-wire semantics are
    // UNCONFIRMED). Fail-closed default false and re-evaluated UNCONDITIONALLY on every statusRead
    // (NOT the keep-last-value pattern most other flags here use): absent/invalid/non-true resolves to
    // false so a dropped key or a legacy phone can never leave a stale "charging" claim on screen.
    // Never inferred from a rising percent.
    (:background)
    var batteryCharging as Lang.Boolean = false;
    (:background)
    var lastBolus as Lang.Float = -1.0;   // units of the last bolus (-1 = unknown)
    (:background)
    var connection as Lang.String = "";   // e.g. "Connected"
    (:background)
    var readingEpoch as Lang.Number = 0;  // unix sec the current BG was taken (0 = unknown)
    // Staleness policy, synced from the phone (statusRead). staleSec: age after which the reading is
    // stale (greyed + not used for carb→unit). hideDelaySec: extra age before hiding ("--"); null =
    // never hide (always greyed), 0 = hide as soon as stale. Defaults mirror the phone (6 min / never).
    (:background)
    var staleSec as Lang.Number = 360;
    (:background)
    var hideDelaySec as Lang.Number or Null = null;
    (:background)
    var history as Lang.Array = [];       // recent mg/dL (Numbers), oldest → newest, for the plot
    // Per-point Unix-sec source timestamps, aligned 1:1 with `history` (same size, oldest →
    // newest). Empty ⇒ the phone sent no (or misaligned) epochs and the plot falls back to assumed
    // ~5-min index spacing. INVARIANT after parsing: historyEpochs.size() == history.size() (1:1) OR
    // historyEpochs is empty — never a partial/off-by-one array (see the lockstep parse in handle()).
    (:background)
    var historyEpochs as Lang.Array = [];
    (:background)
    var alerts as Lang.Array = [];        // active pump alerts: dicts {id, kind, title}
    // Transient — set true by AlertConfirmDelegate when a "clear alert" dismiss couldn't be
    // dispatched (phone unreachable) so the alert was NOT removed locally; AlertsListView renders a
    // "Phone not connected — not cleared" notice. Cleared at the top of the next handle() (any phone
    // reply reconciles the alerts list authoritatively). Never persisted — purely a UI hint.
    (:background)
    var alertDismissFailedOffline as Lang.Boolean = false;
    (:background)
    var plotHours as Lang.Number = 3;     // history-plot window: 3 → 6 → 12 → 24 → 3
    // The Garmin Y-axis plot floor/ceiling, mg/dL. Garmin is in the SMALL-SCREEN group — the
    // statusRead parse below resolves the small-screen override first, falling back to the shared/
    // phone-scoped bounds when no override is set (never the reverse). Defaults mirror
    // faBolusCore.GlucosePlotScale.defaultFloor/defaultCeiling exactly, preserving today's hardcoded
    // view until the first statusRead arrives.
    (:background)
    var plotFloor as Lang.Number = 40;
    (:background)
    var plotCeiling as Lang.Number = 300;

    // Configurable layout (from phone settings, persisted so it survives restarts / offline launch).
    // The swipe order of the screens and which one opens first. Ids: glance/alerts/history/details.
    (:background)
    var screenOrder as Lang.Array = ["glance", "alerts", "history", "details"];
    (:background)
    var defaultScreen as Lang.String = "glance";
    // "glucose" = a current-glucose screen with no bolus button (users can add it to the order instead
    // of, or alongside, the bolus "glance").
    (:background)
    const ALL_SCREENS = ["glance", "glucose", "clock", "bolusonly", "alerts", "history", "details"];

    // Read-only mode pushed from the phone ("remotesReadOnly"): hide the bolus button everywhere.
    (:background)
    var readOnly as Lang.Boolean = false;

    // Capability channel ("supportsRemoteAlertDismiss"): whether the pump firmware honors a REMOTE
    // alert dismissal. t:slim X2 silently rejects it (dismiss only snoozes locally); Mobi clears it on
    // the pump. Drives the confirm verb (alertActionWord). Safe default false => "Snooze" (honest — the
    // dismiss won't clear on the pump); the statusRead that carries an alert also carries this flag.
    (:background)
    var supportsRemoteAlertDismiss as Lang.Boolean = false;

    // DYNAMIC pump-tied capability: true only when the phone
    // build supports the authenticated dismissAck path AND the connected pump honors a remote dismiss.
    // UNLIKE supportsRemoteAlertDismiss above (declared false, NEVER persisted/restored), this one IS
    // persisted (Storage.setValue on parse, mirroring garminBolusEnabled) and restored in loadPrefs —
    // so a relaunch resumes in ack-mode instead of defaulting false and letting the FIRST post-relaunch
    // filtered statusRead fall through to the statusRead-reconcile fallback (`reconcileDismissSent`)
    // with no authenticated ack (the exact fail-open). Parsed in handle() BEFORE the alerts-replace
    // (below) for the same reason.
    (:background)
    var supportsDismissAck as Lang.Boolean = false;

    // DYNAMIC pump-tied capability, the exact NEGATION of supportsDismissAck: true only
    // when the phone build supports the raw-snapshot backstop AND the connected pump does NOT honor a
    // remote dismiss (t:slim X2 — no op-184 dismissAck is ever emitted for it). Mirrors
    // supportsDismissAck exactly: persisted (Storage.setValue on parse) and restored in loadPrefs, so a
    // relaunch resumes on the raw-snapshot tier instead of defaulting false and falling through to the
    // statusRead-reconcile fallback (`reconcileDismissSent`) on the first post-relaunch reply. Parsed in
    // handle() BEFORE the alerts-replace, alongside supportsDismissAck, for the same reason. The two
    // capabilities can never both be true for the same connected pump.
    (:background)
    var supportsRawAlertSnapshot as Lang.Boolean = false;

    // The host's authoritative "may a remote start a bolus right now?" (schema `canBolus`),
    // plus its reason token (`bolusBlockReason`: "pumpNotLinked" | "bolusInFlight" | "accessDenied").
    // null until the host sends them (older host) → pumpBolusAllowed() falls back to deriving from the
    // connection string. Lets the START gate stop treating a substring match of the localized display
    // string ("Delivering…") as load-bearing safety logic.
    (:background)
    var hostCanBolus as Lang.Boolean or Null = null;
    (:background)
    var hostBolusBlockReason as Lang.String or Null = null;

    // Whether the phone has enabled bolusing FROM THIS GARMIN. Default false ⇒ fail-closed: a
    // cold launch / glance with no push keeps the bolus affordance hidden until a push arms it (persisted
    // so a restart doesn't re-hide an already-enabled watch). The host also refuses a Garmin deliver when
    // false (AccessPolicy). `bolusPasscodeRequired` mirrors whether a 4-digit passcode confirms the bolus.
    (:background)
    var garminBolusEnabled as Lang.Boolean = false;
    (:background)
    var bolusPasscodeRequired as Lang.Boolean = false;

    // The PHONE-OWNED, watch-synced alert-intensity setting. The watch reads these off the statusRead
    // reply (handle) + restores them on a cold launch (loadPrefs) and gates ALL watch alert output
    // (vibrate/tone/backlight/DND-override) through the pure alertActionFor() gate. The config lives
    // on the phone; there is NO watch-side properties.xml/settings UI. DEFAULT = vibration-only for
    // EVERY severity, nothing audible and nothing DND-piercing unless the user opts in.
    // `alertIntensityMode` is a frozen 3-token enum ("silent"|"vibrate"|"audible"); an
    // absent/unrecognized value fails closed to "vibrate". `alertAudibleMinSeverity` is the severity
    // floor (tier token) at/above which "audible" mode plays a tone (default "critical"). Persisted +
    // change-detected exactly like garminBolusEnabled so a relaunch / background service honors the last
    // phone-synced value. SETTINGS-ONLY: this NEVER feeds/gates/delays a dose — alert-surface only.
    (:background)
    var alertIntensityMode as Lang.String = "vibrate";
    (:background)
    var alertAudibleMinSeverity as Lang.String = "critical";
    // The "let critical alerts override Do Not Disturb / vibrateOn=off" opt-in. USER setting, turn-off-able,
    // DEFAULT OFF: nothing pierces DND unless the user turns this on. In Silent mode + OFF the watch
    // is FULLY silent for every alert including critical; + ON adds an opt-in critical-only vibration wrist
    // fallback (never a tone).
    (:background)
    var alertCriticalOverridesDnd as Lang.Boolean = false;

    // The pump's automated-controller identity + its Control-IQ runtime on/off, pushed on
    // the statusRead reply so the watch can reconstruct the auto-correction DISCLOSURE locally (no prose
    // crosses the wire). Both mirror faBolusCore (ControllerVariant / PumpSnapshot.controlIQEnabled).
    // `controllerVariant` is a FROZEN token (schema `controllerVariant` enum): "none" / "controlIQ" /
    // "controlIQPro" — never invent others. DISPLAY-ONLY: neither ever gates, changes, or delays a bolus
    // — nothing here feeds a dose. Safe legacy default ("none" / false) ⇒ render nothing controller-
    // specific. Not persisted (matches the nearby display-only capability fields, e.g.
    // supportsRemoteAlertDismiss): a cold launch shows nothing controller-specific until the first push.
    (:background)
    var controllerVariant as Lang.String = "none";
    (:background)
    var controlIQEnabled as Lang.Boolean = false;

    // The pump's live Sleep/Exercise activity mode (0 normal / 1 sleep / 2 exercise), on the shared
    // statusRead reply (RemoteCommand.controlIQMode) so this Garmin can gate its own activity-mode
    // row locally. Same display-only, not-persisted treatment as controllerVariant/controlIQEnabled
    // just above (a capability-like fact that changes rarely enough that a cold launch showing nothing
    // Sleep/Exercise-specific until the first push is acceptable, matching those two fields'
    // documented reasoning). DISPLAY-ONLY: never gates, changes, or delays a bolus.
    (:background)
    var controlIQMode as Lang.Number = 0;
    // The already-decoded exercise countdown (op-179), a RAW remaining-seconds DURATION — NOT an
    // epoch: this device counts down LOCALLY against ITS OWN receipt time for animation only,
    // re-anchored on every statusRead, never trusted as absolute past that point. UNLIKE
    // controllerVariant/controlIQEnabled above, this DOES need to survive a restart between phone
    // syncs (mirrors lockoutUntilEpochSec's own persistence exactly, same reasoning — it changes far
    // more often than the display-only capability fields). `null` ⇒ the timer fact renders ABSENT —
    // never a stale/negative countdown (fail-closed).
    (:background)
    var exerciseTimeRemainingSec as Lang.Number? = null;

    // The pump's live Control-IQ action zone, a FROZEN wire token (schema `ciqZone`:
    // "increases"/"decreases"/"maintains"/"stops"/"delivers" — Tandem's own zone words, (c) Tandem,
    // never invent others). UNLIKE `controllerVariant`/`controlIQEnabled` above, this one DOES need
    // to survive a restart between phone syncs (matches `garminBolusEnabled`'s persistence, not the
    // display-only capability fields) because it changes far more often and a watch that restarts
    // mid-session should still show the last-known zone rather than nothing. `null` ⇒ render the row
    // ABSENT — never a stale/fabricated word. DISPLAY-ONLY: never gates, changes, or delays a bolus.
    (:background)
    var ciqZone as Lang.String? = null;

    // Whether the pump's OWN control-state currently attributes an active basal suspend to Control-IQ
    // (fail-closed cause-attribution). UNLIKE `controllerVariant`/`controlIQEnabled`, this DOES need
    // to survive a restart between phone syncs (mirrors `ciqZone`'s own persistence exactly, same
    // reasoning). `null`/`false` ⇒ this watch has no generic-suspend signal to fall back to either, so
    // the row is simply ABSENT — never a fabricated "Control-IQ paused" claim. DISPLAY-ONLY: never
    // gates, changes, or delays a bolus.
    (:background)
    var ciqSuspendedForLow as Lang.Boolean? = null;
    // The immutable SOURCE epoch (Unix seconds, raw — NOT an age) of the moment `ciqSuspendedForLow`
    // first became true. Elapsed minutes are computed at DRAW time from this (DetailsView's
    // `ciqSuspendElapsedMinutes()`), never transmitted as a pre-computed age.
    (:background)
    var ciqSuspendStartEpochSec as Lang.Number? = null;

    // The immutable SOURCE epoch (Unix seconds, raw — NOT an age) of the most-recent Control-IQ
    // auto-correction. A real historical fact never un-happens, so — UNLIKE `ciqZone`/
    // `ciqSuspendedForLow` above — this is never cleared on an absent key, only ever overwritten by a
    // newer instant. Persisted (survives a restart between phone syncs, matches `ciqZone`'s own
    // persistence). `null` ⇒ the row renders ABSENT (never "--" — no recent auto-correction is the
    // common/expected case, not an error). DISPLAY-ONLY: never gates, changes, or delays a bolus.
    (:background)
    var lastAutoCorrectionEpochSec as Lang.Number? = null;
    // The immutable SOURCE epoch of the most-recent "Control-IQ tried and couldn't deliver an
    // automatic correction" event. Remote MARKER only (no on-watch/Garmin timeline — this device
    // never had the pump history to build one from). `null` ⇒ the marker renders ABSENT.
    // DISPLAY-ONLY: never gates, changes, or delays a bolus.
    (:background)
    var ciqLastCouldNotDeliverEpochSec as Lang.Number? = null;

    // The immutable SOURCE epoch (Unix seconds, raw — NOT an age) of the instant Control-IQ's
    // automatic correction becomes available again. UNLIKE `lastAutoCorrectionEpochSec` above (a
    // monotonic historical marker that never un-happens), this is a DERIVED instant the phone
    // recomputes fresh on every statusRead — so it is always fully authoritative (assign/clear, never
    // "ignore if invalid, keep last"), mirroring `ciqZone`'s unconditional guard, NOT
    // `lastAutoCorrectionEpochSec`'s monotonic one. Persisted (survives a restart between phone
    // syncs, matches `ciqZone`'s own persistence). `null` ⇒ the bar/numeral renders ABSENT (never a
    // frozen 0%/100% bar, never a negative countdown). DISPLAY-ONLY: never gates, changes, or delays
    // a bolus.
    (:background)
    var lockoutUntilEpochSec as Lang.Number? = null;

    // The pump's configured max-basal delivery limit, mirrored from the phone's `maxBasalUnitsPerHour`.
    // Like `lockoutUntilEpochSec` above, the phone relays its CURRENT knowledge every statusRead
    // (never "unread ⇒ omit the key", `<= 0` means unread on the wire), so this is always fully
    // authoritative (assign/clear, never "ignore if invalid, keep last") — a stale max surviving past
    // the moment it actually cleared would misrepresent the pump's real configured limit. Persisted
    // (survives a restart between phone syncs, matches `lockoutUntilEpochSec`'s own persistence).
    // `null` ⇒ the "% of configured max basal" text row renders ABSENT (fail-closed: hidden, never
    // "0%"/"--"). DISPLAY-ONLY: never gates, changes, or delays a bolus.
    (:background)
    var maxBasalUnitsPerHour as Lang.Float? = null;

    // Details rows shown (in order) + which history ranges the plot cycles through on tap — both
    // mirrored from the phone ("detailsOrder" / "watchChartRanges" in the statusRead reply).
    (:background)
    var detailsOrder as Lang.Array = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"];
    // "ciqZone"/"ciqSuspend"/"autoCorrection"/"couldNotDeliver" registered so any CAN be selected
    // once a phone-side customizer opts them in — deliberately NOT added to the default
    // `detailsOrder` above (opt-in). The rows exist and render correctly once selected.
    (:background)
    const ALL_DETAILS = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus", "ciqZone", "ciqSuspend", "autoCorrection", "couldNotDeliver", "maxBasal"];
    (:background)
    var chartRanges as Lang.Array = [3, 6, 12, 24];
    // How the BG complication presents: "numericColor" (numeric value + range color + Latin trend
    // in the unit slot) or "stringTrend" (plain "124 ^" string). Mirrored from the phone.
    (:background)
    var complicationDisplay as Lang.String = "numericColor";

    // Which pump-status fields fill the THREE user-assignable complication slots
    // (ids 1..3, published alongside the fixed glucose id 0). Connect IQ caps an app at FOUR complications
    // total, so only three slots exist; this phone-owned, watch-synced ORDERED list chooses which up-to-3
    // of the four available fields (COMPLICATION_FIELDS) occupy them and in what order. DEFAULT = glucose
    // (fixed) + IOB + reservoir + pump battery (all three slots filled) until the user re-assigns them on
    // the phone. Sanitized on parse/restore (allowed tokens only, de-duped, capped at 3). Display only —
    // never a dose input.
    (:background)
    const COMPLICATION_FIELDS = ["iob", "reservoir", "battery", "basal"];
    (:background)
    var garminComplicationSlots as Lang.Array = ["iob", "reservoir", "battery"];

    // Load persisted layout at launch (getInitialView needs defaultScreen before any phone message).
    (:background)
    function loadPrefs() as Void {
        var so = Storage.getValue("screenOrder");
        if (so instanceof Lang.Array) { screenOrder = sanitizeOrder(so); }
        var ds = Storage.getValue("defaultScreen");
        if (ds instanceof Lang.String && contains(screenOrder, ds)) { defaultScreen = ds; }
        ensureValidDefault();
        var dord = Storage.getValue("detailsOrder");
        if (dord instanceof Lang.Array) {
            var s = sanitizeAgainst(dord, ALL_DETAILS);
            if (s.size() > 0) { detailsOrder = s; }
        }
        var cr = Storage.getValue("watchChartRanges");
        if (cr instanceof Lang.Array) {
            var sr = sanitizeRanges(cr);
            if (sr.size() > 0) { chartRanges = sr; ensureValidPlotHours(); }
        }
        var cdp = Storage.getValue("complicationDisplay");
        if (cdp instanceof Lang.String) { complicationDisplay = cdp; }
        // Restore the persisted complication-slot selection so a cold launch /
        // background service publishes the last phone-synced set instead of reverting to the default until
        // the next statusRead. Sanitized (allowed tokens, de-duped, cap 3); an empty result keeps the default.
        var gcs = Storage.getValue("garminComplicationSlots");
        if (gcs instanceof Lang.Array) {
            var gcsSan = sanitizeComplicationSlots(gcs);
            if (gcsSan.size() > 0) { garminComplicationSlots = gcsSan; }
        }
        // Restore the staleness policy so a restart / background launch honors the phone-synced
        // value instead of silently reverting to the 6-min default until the next statusRead.
        var ss = Storage.getValue("staleSec");
        if (ss instanceof Lang.Number && ss > 0) { staleSec = ss; }
        var hd = Storage.getValue("hideDelaySec");
        hideDelaySec = (hd instanceof Lang.Number && hd >= 0) ? hd : null;   // absent/null = never hide
        // Restore the persisted bolus-enable so a cold launch stays on the last-known value
        // (fail-closed to false when never armed) instead of re-hiding an already-enabled watch.
        var gbe = Storage.getValue("garminBolusEnabled");
        if (gbe instanceof Lang.Boolean) { garminBolusEnabled = gbe; }
        // Restore the persisted zone the same guarded way, so a cold
        // launch before the first statusRead shows the last-known zone rather than nothing. A
        // corrupt/absent/non-member value keeps the safe default (null ⇒ row absent).
        var cz0 = Storage.getValue("ciqZone");
        if (cz0 instanceof Lang.String && containsStr(CIQ_ZONES, cz0 as Lang.String)) { ciqZone = cz0; }
        // Restore the persisted suspend attribution the same guarded
        // way as ciqZone, so a cold launch before the first statusRead shows the last-known attribution
        // rather than nothing. A corrupt/absent value keeps the safe default (null ⇒ row absent).
        var csfl0 = Storage.getValue("ciqSuspendedForLow");
        if (csfl0 instanceof Lang.Boolean) { ciqSuspendedForLow = csfl0; }
        var csse0 = Storage.getValue("ciqSuspendStartEpochSec");
        if (csse0 instanceof Lang.Number && csse0 > 0) { ciqSuspendStartEpochSec = csse0; }
        // Restore the persisted markers the same guarded way, so a cold
        // launch before the first statusRead shows the last-known instant rather than nothing. A
        // corrupt/absent value keeps the safe default (null ⇒ row/marker absent).
        var lac0 = Storage.getValue("lastAutoCorrectionEpochSec");
        if (lac0 instanceof Lang.Number && lac0 > 0) { lastAutoCorrectionEpochSec = lac0; }
        var cncd0 = Storage.getValue("ciqLastCouldNotDeliverEpochSec");
        if (cncd0 instanceof Lang.Number && cncd0 > 0) { ciqLastCouldNotDeliverEpochSec = cncd0; }
        // Restore the persisted lockout-until epoch the same guarded way, so
        // a cold launch before the first statusRead shows the last-known instant rather than nothing.
        // A corrupt/absent value keeps the safe default (null ⇒ bar/numeral absent).
        var lue0 = Storage.getValue("lockoutUntilEpochSec");
        if (lue0 instanceof Lang.Number && lue0 > 0) { lockoutUntilEpochSec = lue0; }
        // Restore the persisted exercise countdown the same guarded way, so
        // a cold launch before the first statusRead shows the last-known duration rather than
        // nothing. A corrupt/absent/non-positive value keeps the safe default (null ⇒ timer absent).
        var etrs0 = Storage.getValue("exerciseTimeRemainingSec");
        if (etrs0 instanceof Lang.Number && etrs0 > 0) { exerciseTimeRemainingSec = etrs0; }
        // Restore the persisted configured max-basal limit the same guarded
        // way, so a cold launch before the first statusRead shows the last-known value rather than
        // nothing. A corrupt/absent/non-positive value keeps the safe default (null ⇒ row absent).
        var mbu0 = fltRange(Storage.getValue("maxBasalUnitsPerHour"), 0.01, 25.0);
        if (mbu0 != null) { maxBasalUnitsPerHour = mbu0; }
        // Restore the persisted passcode-required flag the same way, so a cold launch before the
        // first statusRead already knows a passcode confirms the bolus — closing the window where a
        // required→(default not-required) flip could briefly offer the tap/hold confirm instead. Default
        // false is a safe fail-open here (worst case the phone still denies an unverified bolus), but
        // persisting matches garminBolusEnabled and avoids that transient.
        var bpr0 = Storage.getValue("bolusPasscodeRequired");
        if (bpr0 instanceof Lang.Boolean) { bolusPasscodeRequired = bpr0; }
        // Restore the persisted alert-intensity setting the same guarded way,
        // so a cold launch / background service honors the last phone-synced value instead of silently
        // reverting to the vibration-only default until the next statusRead. Fail-closed guards mirror the
        // handle() parse (mode must be a frozen token; floor must be a valid tier).
        var aim0 = Storage.getValue("alertIntensityMode");
        if (aim0 instanceof Lang.String && containsStr(ALERT_MODES, aim0 as Lang.String)) { alertIntensityMode = aim0; }
        var aams0 = Storage.getValue("alertAudibleMinSeverity");
        if (aams0 instanceof Lang.String && isValidSeverityTier(aams0 as Lang.String)) { alertAudibleMinSeverity = aams0; }
        var acod0 = Storage.getValue("alertCriticalOverridesDnd");
        if (acod0 instanceof Lang.Boolean) { alertCriticalOverridesDnd = acod0; }
        // Restore the persisted display-unit token the same guarded way, so a cold
        // launch before the first statusRead already renders in the last unit the phone pushed
        // (fail-closed to the "mgdl" default when never set / not yet a recognized token).
        var gu0 = Storage.getValue("glucoseDisplayUnit");
        if (gu0 instanceof Lang.String && isValidUnitToken(gu0 as Lang.String)) { glucoseUnit = gu0; }
        // Restore the persisted plot bounds so a cold launch (before the first statusRead)
        // already renders the last phone-pushed range instead of silently reverting to the 40/300
        // defaults. Strict guard (mirrors staleSec): only a sane in-range Number is adopted; a corrupt/
        // absent value keeps the compile-time default.
        var pf0 = Storage.getValue("plotFloor");
        var pc0 = Storage.getValue("plotCeiling");
        if (pf0 instanceof Lang.Number && pf0 > 0 && pf0 < 1000) { plotFloor = pf0; }
        if (pc0 instanceof Lang.Number && pc0 > 0 && pc0 < 1000) { plotCeiling = pc0; }
        if (plotFloor >= plotCeiling) { plotFloor = 40; plotCeiling = 300; }   // min-gap invariant
        // Restore the durable unresolved-delivery tombstone (if any) so a cold
        // relaunch still knows a prior dispatch is unresolved — reattemptBlocked() consults this in
        // sendBolusNow, independent of pendingRequestId (deliberately NOT restored here — the tombstone
        // alone is sufficient to block a re-send; see the field's own doc comment).
        var tomb = Storage.getValue(KEY_UNRESOLVED_TOMBSTONE);
        if (tomb instanceof Lang.Dictionary) {
            var trid = strCap(tomb["requestId"], 64);
            if (trid != null) {
                unresolvedTombstoneReqId = trid;
                var tsa = tomb["sentAt"];
                unresolvedTombstoneSentAt = (tsa instanceof Lang.Number) ? tsa : 0;
                unresolvedTombstoneDoseKey = strCap(tomb["doseKey"], 64);
            }
        }
        // Restore the lock-release audit record too, so "this lock was released by a human, not by a
        // confirmed outcome" survives a relaunch and stays visible rather than vanishing silently.
        var lr = Storage.getValue(KEY_LOCK_RESOLVED);
        if (lr instanceof Lang.Dictionary) {
            var lrid = strCap(lr["requestId"], 64);
            if (lrid != null) {
                lockResolvedReqId = lrid;
                var lat = lr["at"];
                lockResolvedAtEpoch = (lat instanceof Lang.Number) ? lat : 0;
            }
        }
        // Restore the two-lane dismiss state (retry lane + display
        // provisional lane) AND the persisted supportsDismissAck capability, so a cold relaunch resumes
        // in ack-mode (last-known) and keeps a wearer-dismissed-but-unacked alert overlaid instead of
        // starting fresh with no memory of it.
        loadDismissState();
    }

    // Frozen wire-token set for the display-unit field (never a raw enum on the wire).
    (:background, :glance)
    function isValidUnitToken(t as Lang.String) as Lang.Boolean {
        return t.equals("mgdl") || t.equals("mmol");
    }

    // Keep only allowed string ids (de-duped), preserving the phone-chosen subset + order.
    (:background)
    function sanitizeAgainst(list as Lang.Array, allow as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.String && contains(allow, v) && !containsStr(out, v)) { out.add(v); }
        }
        return out;
    }

    // Sanitize the complication-slot field list — allowed tokens only, de-duped,
    // preserving the phone-chosen order, then capped at the three available slots (ids 1..3).
    (:background)
    function sanitizeComplicationSlots(list as Lang.Array) as Lang.Array {
        var s = sanitizeAgainst(list, COMPLICATION_FIELDS);
        if (s.size() <= 3) { return s; }
        var out = [];
        for (var i = 0; i < 3; i += 1) { out.add(s[i]); }
        return out;
    }

    // Keep only the allowed history ranges {3,6,12,24}, de-duped, preserving order.
    (:background)
    function sanitizeRanges(list as Lang.Array) as Lang.Array {
        var allowed = [3, 6, 12, 24];
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.Number && containsNum(allowed, v) && !containsNum(out, v)) { out.add(v); }
        }
        return out;
    }

    (:background)
    function containsStr(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.String && (list[i] as Lang.String).equals(v)) { return true; }
        }
        return false;
    }
    (:background)
    function containsNum(list as Lang.Array, v as Lang.Number) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.Number && (list[i] as Lang.Number) == v) { return true; }
        }
        return false;
    }
    (:background)
    function ensureValidPlotHours() as Void {
        if (chartRanges.size() > 0 && !containsNum(chartRanges, plotHours)) {
            plotHours = chartRanges[0] as Lang.Number;
        }
    }

    // Gridlines for CgmView's dynamic plot, computed to fall STRICTLY inside
    // [floor, ceiling] — never exactly at either edge, so a gridline is never visually confused with
    // the top/bottom of the plotted domain. Prefers a 100 mg/dL step (matches today's 100/200/300
    // default view exactly for the 40..300 default combo, since the domain floor/ceiling never land
    // exactly on a multiple of 100); falls back to a 50 mg/dL step only if that would produce fewer
    // than 2 lines. Every discrete floor×ceiling preset combo (floorOptions × ceilingOptions,
    // faBolusCore.GlucosePlotScale) already clears >=2 lines at the 100 step today — the 50 fallback
    // is a defensive guard against a future preset-set edit narrowing the domain further (mirrors
    // GlucosePlotScale.minGap's own "never triggers today" precedent).
    function plotGridlines(floor as Lang.Number, ceiling as Lang.Number) as Lang.Array {
        var lines = multiplesStrictlyBetween(floor, ceiling, 100);
        if (lines.size() < 2) {
            lines = multiplesStrictlyBetween(floor, ceiling, 50);
        }
        return lines;
    }

    // Every multiple of `step` with floor < v < ceiling, ascending.
    function multiplesStrictlyBetween(floor as Lang.Number, ceiling as Lang.Number, step as Lang.Number) as Lang.Array {
        var out = [];
        var v = ((floor / step) + 1) * step;   // smallest multiple of step, may equal floor if floor is
        if (v <= floor) { v += step; }         // itself already a multiple — bump past it (strict >)
        while (v < ceiling) {
            out.add(v);
            v += step;
        }
        return out;
    }

    // Keep only known ids (de-duped), preserving the phone-chosen subset + order. Screens the user
    // hid are intentionally omitted. Falls back to all screens only if the result would be empty,
    // so the watch is never left with nothing to show.
    (:background)
    function sanitizeOrder(list as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.String && contains(ALL_SCREENS, v) && !contains(out, v)) { out.add(v); }
        }
        if (out.size() == 0) {
            for (var i = 0; i < ALL_SCREENS.size(); i += 1) { out.add(ALL_SCREENS[i]); }
        }
        return out;
    }

    // Ensures the default screen is one that's actually shown; otherwise falls back to the first.
    (:background)
    function ensureValidDefault() as Void {
        if (!contains(screenOrder, defaultScreen)) {
            defaultScreen = (screenOrder.size() > 0) ? (screenOrder[0] as Lang.String) : "glance";
        }
    }

    (:background)
    function contains(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.String && (list[i] as Lang.String).equals(v)) { return true; }
        }
        return false;
    }

    // Advance to the next phone-enabled history range (wrapping). The set comes from the phone's
    // watchChartRanges; if the current window isn't in it, start at the first.
    function cyclePlotHours() as Void {
        if (chartRanges.size() == 0) { return; }
        var idx = -1;
        for (var i = 0; i < chartRanges.size(); i += 1) {
            if ((chartRanges[i] as Lang.Number) == plotHours) { idx = i; break; }
        }
        idx = (idx + 1) % chartRanges.size();
        plotHours = chartRanges[idx] as Lang.Number;
    }

    // A cached BG older than 6 minutes must not be shown (per spec).
    function glucoseStale() as Lang.Boolean {
        if (glucose == null || readingEpoch <= 0) { return true; }
        return (Time.now().value() - readingEpoch) > staleSec;
    }
    // Past the hide delay → show "--" instead of the greyed value. null delay = never hide.
    function glucoseHidden() as Lang.Boolean {
        if (hideDelaySec == null) { return false; }
        if (readingEpoch <= 0) { return true; }
        return (Time.now().value() - readingEpoch) > (staleSec + hideDelaySec);
    }

    // The three stale-CGM choices, mirroring faBolusCore StaleBolusChoice. Kept as
    // module consts + pure predicates HERE (not on the view) so the safety-critical semantics are
    // unit-testable — the view/delegate aren't compiled into the test binary (see test.jungle).
    const STALE_INCLUDE = 0;      // dose the correction off the stale-but-REAL reading (insulin-INCREASING)
    const STALE_CARBS_ONLY = 1;   // today's silent behavior — drop the stale BG, carbs-only, now acknowledged
    const STALE_CANCEL = 2;       // pure UI back-out — compose/send NOTHING

    // Mirror of StaleBolusPrompt.proceeds: every path composes + sends EXCEPT cancel, which sends nothing.
    function staleChoiceProceeds(opt as Lang.Number) as Lang.Boolean { return opt != STALE_CANCEL; }
    // Mirror of StaleBolusPrompt.bgForCalculation: only "include" carries the stale reading into the dose.
    function staleChoiceIncludesBg(opt as Lang.Number) as Lang.Boolean { return opt == STALE_INCLUDE; }

    // Mirror of StaleBolusPrompt.shouldWarn — show the three-way stale-CGM choice only
    // when there IS a reading value AND it is stale at compose. No reading at all is simply carbs-only
    // (nothing to include); a fresh reading composes normally. Same staleness the UI grays (glucoseStale).
    // (Garmin: only carbs mode has a correction term, so the delegate additionally gates on carbs mode.)
    function staleBolusShouldWarn() as Lang.Boolean {
        return glucose != null && glucoseStale();
    }

    // The BG (mg/dL) to feed the correction / send with a carb bolus — mirror of
    // StaleBolusPrompt.bgForCalculation composed with freshness. Fresh → the reading. Stale → included
    // ONLY when the wearer made the explicit per-attempt "include" choice this compose (includeStaleBg);
    // otherwise nil-dropped to carbs-only. No reading → nil. A nil result means the carb request omits
    // bgMgdl (RemoteComm.bolusRequestCarbs), so the phone recomputes carbs-only too.
    function bgForBolus() as Lang.Number? {
        if (glucose == null) { return null; }
        if (!glucoseStale()) { return glucose; }
        return includeStaleBg ? glucose : null;
    }

    // The pump is reachable when the phone reports it connected or actively delivering.
    // "Connecting…", "Scanning…", "Disconnected", "Error", and unknown ("") mean not reachable.
    (:background)
    function pumpConnected() as Lang.Boolean {
        return connection.equals("Connected") || bolusing();
    }

    // A bolus is currently being delivered ("Delivering…").
    (:background)
    function bolusing() as Lang.Boolean {
        return connection.find("Deliver") == 0;
    }

    // Whether the PUMP side permits a new bolus — the host's authoritative flag when present (schema
    // `canBolus`: pump linked AND not mid-delivery AND remotes not read-only), otherwise derived from
    // the connection string. Excludes phone reachability (the Garmin's own local link), so it is
    // deterministically unit-testable; canBolus() ANDs in reachability. This is what
    // stops the START gate from depending on a substring match of the localized display string.
    (:background)
    function pumpBolusAllowed() as Lang.Boolean {
        if (hostCanBolus != null) { return hostCanBolus; }
        return pumpConnected() && !bolusing();
    }

    // App-level liveness — the faBolus phone app has sent a reply within CONNECTION_STALE_SEC.
    // Distinct from RemoteComm.phoneReachable() (the raw BLE link, which stays "connected" even when
    // faBolus is killed). 0 (never replied / cold launch) fails closed. Anchored on `lastReplyEpoch`,
    // stamped at the top of handle() on every inbound reply. Pure decision (wall-clock only) → testable.
    (:background)
    function appLive() as Lang.Boolean {
        return lastReplyEpoch > 0 && (Time.now().value() - lastReplyEpoch) <= CONNECTION_STALE_SEC;
    }

    // A new bolus is only possible when the phone (which owns the pump link) is reachable AND the faBolus
    // app is live (recent reply) AND the pump side permits it. The Garmin never touches the pump
    // directly. `pumpBolusAllowed()` stays PURE (no liveness) so its own tests remain deterministic.
    //
    // ...AND no durable unresolved-send tombstone is outstanding. That last term is not a new gate: a
    // tombstone ALREADY made every send fail at sendBolusNow's reattemptBlocked() guard. Leaving it out of
    // canBolus() meant the affordance LIED — a fully enabled indigo Bolus button that opened entry, let the
    // wearer compose a dose and tap 1-2-3, and then refused at the send with no explanation, permanently
    // and across reboots. Reflecting it here makes the button's appearance match what the send gate will
    // actually do, and routes the wearer to the disclosure surface instead (MainDelegate/BolusOnlyDelegate).
    //
    // Deliberately NOT added to eligibilityFingerprint(): that fingerprint uses pumpBolusAllowed()
    // directly and never consults canBolus(), so this term cannot perturb bolusEligibilityGen and cannot
    // spuriously tear down an armed confirm. Nor does it touch canCancel() — cancelling an in-flight bolus
    // is a safety action and must never be blocked by a tombstone from an EARLIER dose.
    function canBolus() as Lang.Boolean {
        return garminBolusEnabled && RemoteComm.phoneReachable() && appLive() && pumpBolusAllowed()
            && !hasUnresolvedTombstone();
    }

    // The bolus affordance is HOST-POLICY-disabled when the phone put the remote in
    // read-only mode OR hasn't enabled Garmin bolusing. Distinct from canBolus() (which ALSO needs phone
    // reachability + pump-side allowance): this is exactly the pair of phone-pushed flags whose mid-flow
    // flip must tear down an already-armed confirm. Deterministic (no reachability) → unit-testable.
    function bolusPolicyDisabled() as Lang.Boolean {
        return readOnly || !garminBolusEnabled;
    }

    // A fingerprint of everything that makes an armed Garmin dose still valid to send. When ANY of
    // these change on a statusRead the armed dose is no longer the one the wearer confirmed against, so
    // `bolusEligibilityGen` is bumped (see handle()) and the armed confirm is torn down / the send refused
    // (re-confirm). `lastBolus` is folded in so an OBSERVED completed bolus (a new "last bolus" amount)
    // between arm and send also invalidates.
    //
    // Also folds in `appLive()` and `armContextExpired()` — liveness + elapsed-time-since-arm.
    // Note both are evaluated ONLY from inside handle() (the sole caller), where `lastReplyEpoch` has
    // JUST been stamped a few lines above (top of handle()) — so `appLive()` is unconditionally true at
    // THIS evaluation point every time; it is folded in anyway so the fingerprint's identity is already
    // liveness-aware if a future caller ever evaluates it from elsewhere. `armContextExpired()` is where
    // the REAL signal lives here: it is false at arm and for the whole window after, but flips true once
    // the CURRENTLY-armed context has aged past ARM_CONTEXT_STALE_SEC — so a statusRead landing after
    // that point differs from the last-seen fingerprint and bumps the gen, tearing the stale arm down
    // even though nothing else about eligibility changed. (The harder backstop — no intervening
    // statusRead at all — is sendBolusNow()'s own direct armContextExpired()/appLive() re-check at the
    // final send.) Otherwise deterministic (no OTHER wall-clock read) → unit-testable.
    (:background)
    function eligibilityFingerprint() as Lang.String {
        var ro = readOnly ? "1" : "0";
        var gbe = garminBolusEnabled ? "1" : "0";
        var pba = pumpBolusAllowed() ? "1" : "0";
        var bpr = bolusPasscodeRequired ? "1" : "0";
        var live = appLive() ? "1" : "0";
        var expired = armContextExpired() ? "1" : "0";
        return ro + "|" + gbe + "|" + pba + "|" + bpr + "|" + connection + "|" + lastBolus.format("%.2f")
            + "|" + live + "|" + expired;
    }

    // Snapshot the current eligibility generation at compose (BolusEntryDelegate.captureDose, after
    // deliverUnits is set). A later statusRead that changes the fingerprint bumps `bolusEligibilityGen`
    // past this snapshot → mustTeardownArmedBolus()/sendBolusNow() refuse the now-stale arm.
    function armBolus() as Void {
        armedEligibilityGen = bolusEligibilityGen;
        armedAtEpoch = Time.now().value();   // elapsed-time anchor for armContextExpired()
        lastSendRefusal = null;              // a fresh arm starts with a clean refusal slot
    }

    // Whether an armed, pre-delivery confirm must be torn down RIGHT NOW — nothing has been
    // sent yet (status == null; once a request is out the outcome flow owns the screen and must not be
    // disturbed) AND EITHER bolusing was policy-disabled (read-only / Garmin-bolus-off) OR the therapy/
    // policy state changed since the wearer armed (armedEligibilityGen != bolusEligibilityGen). Pure/
    // deterministic; HoldView calls it on every redraw (a phone push always triggers Ui.requestUpdate()).
    // Kept gated on status == null so an in-flight bolus is never torn down (HoldTeardownTest pins this).
    function mustTeardownArmedBolus() as Lang.Boolean {
        return status == null && (bolusPolicyDisabled() || armedEligibilityGen != bolusEligibilityGen);
    }

    // Pure token → short display text mapping (deterministic → unit-testable). "" for null/unknown.
    function bolusReasonText(reason as Lang.String or Null) as Lang.String {
        if (reason == null) { return ""; }
        if (reason.equals("pumpNotLinked")) { return "Pump not connected"; }
        if (reason.equals("bolusInFlight")) { return "Bolus in progress"; }
        if (reason.equals("accessDenied")) { return "Read-only"; }
        if (reason.equals("remoteUnreachable")) { return "Phone not connected"; }
        return "";
    }

    // Capability channel: the verb for the alert-dismiss confirmation — "Clear" when the pump honors
    // a REMOTE dismissal (Mobi), "Snooze" when it doesn't (t:slim, where it only snoozes locally), so the
    // Garmin prompt is honest and matches the phone. Pure/deterministic → unit-testable.
    function alertActionWord() as Lang.String {
        return supportsRemoteAlertDismiss ? "Clear" : "Snooze";
    }

    // Auto-correction DISCLOSURE derivation. A faithful Monkey C hand-port of faBolusCore
    // `ControllerDescriptor` + `AutoCorrectionDisclosure`, kept HERE as pure module functions so the
    // safety-neutral copy is unit-testable (the view is not compiled into the test binary — see
    // test.jungle). DISPLAY-ONLY: every function returns a string to show (or "") — nothing here blocks,
    // disables, clamps, delays, or resizes a dose; the Deliver button is unchanged.
    //
    // Clinical-disclosure values (subject to the clinical-review distribution gate), mirroring the
    // faBolusCore source of truth so the copy is a verbatim cross-surface contract:
    //   • display names "Control-IQ" / "Control-IQ+"  (ControllerDescriptor.displayName)
    //   • lockout window 60 min for BOTH variants      (AutomaticCorrection.blockedByRecentBolusMinutes)
    //   • thresholds 180 / 150-when-rising             (AutoCorrectionDisclosure.disclose{,Rising}AtOrAbove)
    //   • "rising" = the pump's OWN reported up arrows  (risingTrends [.rising,.up,.upUp] → up45/up/upup);
    //     the arrow is READ, never a computed/synthesized glucose rate.
    // FROZEN token set (schema `controllerVariant` enum) — never invent others.
    (:background)
    const CONTROLLER_VARIANTS = ["none", "controlIQ", "controlIQPro"];
    // FROZEN token set (schema `ciqZone` enum) — never invent a 6th.
    (:background)
    const CIQ_ZONES = ["increases", "decreases", "maintains", "stops", "delivers"];
    // The honest "% of your configured max basal rate" fraction, hand-ported mirror
    // of faBolusCore's `MaxBasalFraction.fraction` (Garmin has no shared Swift runtime): `basalRate ÷
    // maxBasalUnitsPerHour`, clamped to [0.0, 1.0]. `null` (fail-closed) when
    // `maxBasalUnitsPerHour` is unknown/absent — this is faBolus's OWN construct, never a Control-IQ
    // figure. DISPLAY-ONLY: a fraction, never a dose/units value; never gates,
    // changes, or delays a bolus.
    function maxBasalFraction() as Lang.Float? {
        if (maxBasalUnitsPerHour == null) { return null; }
        var max = maxBasalUnitsPerHour as Lang.Float;
        if (max <= 0.0) { return null; }
        var fraction = basalRate / max;
        if (fraction < 0.0) { fraction = 0.0; }
        if (fraction > 1.0) { fraction = 1.0; }
        return fraction;
    }

    // A short user-facing reason the bolus button is disabled, so the bolus screen can say WHY
    // (every disabled control shows a reason). Prefers the host's reason token; falls back to the
    // connection string / reachability for an older host. "" when a bolus IS possible.
    function bolusBlockLabel() as Lang.String {
        if (canBolus()) { return ""; }
        // FIRST, ahead of every transient reason. Two reasons this branch must not sit behind
        // phoneReachable()/appLive()/bolusing(): (a) an unresolved prior send is the ONLY block in this
        // function that never clears on its own — every other one resolves itself once the link, the pump
        // or the in-flight dose settles, so a wearer told "Reconnecting…" would wait forever for a
        // reconnect that had already happened; and (b) the disclosure surface is opened only when this
        // label reports the lock (MainDelegate.pressBolusButton), so masking the reason would make the
        // explanation unreachable — reintroducing the same silence this whole fix exists to remove.
        if (hasUnresolvedTombstone()) { return "Earlier dose unresolved"; }
        if (!RemoteComm.phoneReachable()) { return "Phone not connected"; }
        // The BLE link is up but the faBolus app hasn't replied within CONNECTION_STALE_SEC (app
        // killed / backgrounded) — say we're reconnecting rather than showing a stale-derived reason.
        if (!appLive()) { return "Reconnecting…"; }
        // Bolusing from this Garmin is turned off on the phone — say so (and how to fix it).
        if (!garminBolusEnabled) { return "Bolusing off (enable on phone)"; }
        var t = bolusReasonText(hostBolusBlockReason);
        if (!t.equals("")) { return t; }
        if (bolusing()) { return "Bolus in progress"; }
        if (!pumpConnected()) { return "Pump not connected"; }
        return "Unavailable";
    }

    // A bolus started from this watch is in flight and can be cancelled from the glance (e.g. after
    // the user left the delivery screen). Needs the request id we issued so the phone can correlate.
    function canCancel() as Lang.Boolean {
        return bolusing() && pendingRequestId != null;
    }
    // Show the number whenever we have one — a stale reading is shown but marked (grayed + age
    // called out), never hidden. "--" only when there's no reading at all. Unit-aware:
    // renders in the active glucoseUnit via the pure displayGlucoseForUnit() funnel below.
    function displayGlucose() as Lang.String {
        return glucose == null ? "--" : formatMgdl(glucose as Lang.Number);
    }

    // Format an arbitrary mg/dL value (glucose, isf, targetBg — anything canonical mg/dL) in
    // the CURRENT instance unit. Every Garmin glucose/ISF/target display site routes through this (or
    // the pure displayGlucoseForUnit() below), mirroring faBolusCore.GlucoseUnit.format(mgdl:) exactly:
    // mgdl → the plain integer string (unchanged); mmol → 1-decimal, never a second inline
    // "/ 18.0182" — GlucoseUnitTest.mc pins this against the same expected strings as the Swift funnel.
    (:background)
    function formatMgdl(v as Lang.Number) as Lang.String {
        return displayGlucoseForUnit(v, glucoseUnit);
    }

    // Pure variant of formatMgdl()/displayGlucose(), independent of the instance's loaded
    // glucoseUnit — for contexts (FaBolusGlanceView's (:glance) surface) that read Storage directly
    // rather than depending on AppState.loadPrefs() having run first (see FaBolusGlanceView.mc's own
    // "reads Storage directly" note). Both call sites route through this ONE conversion so the math
    // is never duplicated.
    (:background, :glance)
    function displayGlucoseForUnit(v as Lang.Number, unitToken as Lang.String) as Lang.String {
        if (unitToken.equals("mmol")) { return (v.toFloat() / MGDL_PER_MMOL).format("%.1f"); }
        return v.toString();
    }

    // The unit suffix for a glucose/target reading ("mg/dL"/"mmol/L"). Callers compose
    // displayGlucose() + " " + glucoseUnitLabel() instead of ever hardcoding "mg/dL".
    function glucoseUnitLabel() as Lang.String {
        return glucoseUnitLabelForToken(glucoseUnit);
    }

    // Pure variant of glucoseUnitLabel(), for the same Storage-direct (:glance) contexts as
    // displayGlucoseForUnit() above.
    (:glance)
    function glucoseUnitLabelForToken(unitToken as Lang.String) as Lang.String {
        return unitToken.equals("mmol") ? "mmol/L" : "mg/dL";
    }

    // The unit suffix for an ISF reading ("mg/dL/U"/"mmol/L/U") — the one glucose-family label that
    // isn't the bare glucoseUnitLabel() suffix.
    function isfUnitLabel() as Lang.String {
        return glucoseUnit.equals("mmol") ? "mmol/L/U" : "mg/dL/U";
    }
    // Minutes since the current reading (-1 if unknown).
    function ageMinutes() as Lang.Number {
        if (readingEpoch <= 0) { return -1; }
        return (Time.now().value() - readingEpoch) / 60;
    }
    // Relative age label ("now", "3 min ago", "1h 4m ago"), or "" when unknown.
    function ageLabel() as Lang.String {
        var m = ageMinutes();
        if (m < 0) { return ""; }
        if (m == 0) { return "now"; }
        if (m < 60) { return m.toString() + " min ago"; }
        var h = m / 60; var mm = m % 60;
        return mm == 0 ? h.toString() + "h ago" : h.toString() + "h " + mm.toString() + "m ago";
    }

    // Bolus entry
    var mode as Lang.String = "carbs";    // "units" | "carbs"; default from phone settings
    (:background)
    var defaultMode as Lang.String = "carbs";
    var unitsValue as Lang.Float = 0.0;
    var carbsValue as Lang.Number = 0;
    // Per-attempt choice to include a STALE CGM reading in the correction. Off by
    // default and cleared by reset() before every compose, so it is NEVER sticky and NEVER a default —
    // set true only when the wearer explicitly picks "include" in the three-way stale prompt this attempt.
    var includeStaleBg as Lang.Boolean = false;
    (:background)
    var stepU as Lang.Float = 0.05;       // bolus increment (from phone settings)
    (:background)
    var stepC as Lang.Number = 5;         // carb increment (from phone settings)
    const MAX_CARBS = 200;

    // Delivery
    var deliverUnits as Lang.Float = 0.0; // captured when entering the hold screen
    var holdProgress as Lang.Float = 0.0; // 0..1 for the hold-to-deliver ring
    (:background)
    var pendingRequestId as Lang.String? = null;
    (:background)
    var status as Lang.String? = null;    // delivering/delivered/failed/...
    (:background)
    var message as Lang.String? = null;
    // Whether the phone has been seen bolusing since this request started, so a lost/late
    // terminal echo can be recovered from the connection state (see handle()).
    (:background)
    var sawPhoneBolusing as Lang.Boolean = false;

    // WHY the last sendBolusNow() refused, as a bolusSendRefusal() token — or null when the last send
    // proceeded / nothing has been attempted. This exists because sendBolusNow() returns a bare Boolean:
    // the confirm surfaces could see THAT a send was refused but not WHICH of the six gates stopped it, so
    // four of the six reset the wearer's tap progress with no on-screen explanation at all (the 3rd tap of
    // the 1-2-3 confirm appearing to "do nothing"). Written ONLY by sendBolusNow, and cleared by
    // armBolus()/reset() so one arm owns exactly one refusal slot and a re-entered bolus flow never
    // inherits the previous screen's notice. DISPLAY-ONLY: nothing reads this to decide whether to send.
    var lastSendRefusal as Lang.String? = null;

    // A DURABLE unresolved-delivery tombstone {requestId, sentAt, doseKey},
    // persisted to Application.Storage — UNLIKE `pendingRequestId` above, which is in-memory only and
    // lost on a nav/restart/kill. Written ONLY once dispatch to the phone might have occurred (i.e.
    // AFTER RemoteComm.sendBolus returns dispatched==true in sendBolusNow, via
    // maybeWriteUnresolvedTombstone below), NEVER at the point pendingRequestId is armed above (that
    // happens BEFORE the phoneReachable() check; a synchronously-failed dispatch there — the outOfRange
    // return, or a `dispatched==false` transmit failure — means nothing reached the phone, so no phone
    // echo can EVER arrive, and a durable tombstone in that case would be an unrecoverable permanent
    // lock). Consulted by reattemptBlocked() so a fresh sendBolusNow — even
    // after a cold relaunch that lost pendingRequestId — is refused while unresolved. Cleared ONLY on an
    // authoritative terminal echo (delivered/cancelled/failed) for the MATCHING requestId — see
    // handle()'s bolusStatus branch, which checks this independently of pendingRequestId (onBack's
    // clearInFlight() below wipes pendingRequestId/status locally WITHOUT touching the tombstone, so a
    // back-out before the echo lands must not orphan it). `doseKey` is diagnostic content-identity
    // metadata only — requestId is the sole correlation key used to block a re-send / clear on echo.
    (:background)
    const KEY_UNRESOLVED_TOMBSTONE = "unresolvedTombstone";
    (:background)
    var unresolvedTombstoneReqId as Lang.String? = null;
    (:background)
    var unresolvedTombstoneSentAt as Lang.Number = 0;
    (:background)
    var unresolvedTombstoneDoseKey as Lang.String? = null;

    function hasUnresolvedTombstone() as Lang.Boolean {
        return unresolvedTombstoneReqId != null;
    }

    // A short content-identity string for the tombstone's `doseKey` field — diagnostic metadata only,
    // mirroring the mode-specific compose inputs sendBolusNow already sends on the wire (no NEW
    // dose-identity concept introduced). The requestId, not this, is what reattemptBlocked() / the
    // terminal-echo clear actually key on.
    function doseKeyFor() as Lang.String {
        return mode.equals("carbs") ? ("carbs:" + carbsValue.toString()) : ("units:" + deliverUnits.format("%.2f"));
    }

    function persistUnresolvedTombstone(reqId as Lang.String, sentAt as Lang.Number, doseKey as Lang.String) as Void {
        unresolvedTombstoneReqId = reqId;
        unresolvedTombstoneSentAt = sentAt;
        unresolvedTombstoneDoseKey = doseKey;
        Storage.setValue(KEY_UNRESOLVED_TOMBSTONE, { "requestId" => reqId, "sentAt" => sentAt, "doseKey" => doseKey });
    }

    (:background)
    function clearUnresolvedTombstone() as Void {
        unresolvedTombstoneReqId = null;
        unresolvedTombstoneSentAt = 0;
        unresolvedTombstoneDoseKey = null;
        Storage.deleteValue(KEY_UNRESOLVED_TOMBSTONE);
    }

    // ── The unresolved-send LOCK, and how it is legitimately released ────────────────────────────
    //
    // A tombstone locks watch bolusing (reattemptBlocked() → sendBolusNow; and now canBolus(), so the
    // button stops lying). Releasing that lock is a delivery-safety act, so exactly TWO paths may do it,
    // both AUTHORITATIVE and both keyed on the specific requestId — never a blanket unlock:
    //
    //   1. An authoritatively-resolved bolusStatus echo for that requestId (handle(), the pre-existing
    //      path). This is and remains the PREFERRED route: the phone reports what actually happened, so
    //      the dose outcome itself is resolved, not merely the lock.
    //   2. resolveUnresolvedSendLock() below — the phone telling the watch that a HUMAN has reconciled
    //      this dispatch against the pump's own history. Releases the LOCK ONLY. It asserts nothing about
    //      whether insulin was delivered, because nobody knows: that is precisely why the tombstone exists.
    //
    // Path 1 can still win after path 2 has run, and that ordering is deliberate — see the audit record
    // below, which is why a resolve does not destroy the requestId it resolved.
    //
    // NOTHING here auto-clears. There is no timer, no age-out, no clear on redraw/poll/reset/back-out
    // (clearInFlight() has always deliberately left the tombstone alone), and no watch-local unlock: the
    // watch cannot know the dose outcome, and the phone — which owns the pump link, the reconciliation
    // ledger and the history the wearer must actually consult — is the only place the question can be
    // answered. See DEBUG/phone-side requirement notes for the faBolus-side surface this expects.
    const KEY_LOCK_RESOLVED = "unresolvedLockResolved";

    // AUDIT RECORD of the last path-2 release: the requestId whose lock a human resolved, and when.
    // Durable, and deliberately NOT cleared by the resolve itself — an unexplained silent unlock is its
    // own hazard, and keeping the id means a later authoritative echo for that same dispatch is still
    // recognisable, so path 1 can supersede path 2 rather than being locked out by it.
    var lockResolvedReqId as Lang.String? = null;
    var lockResolvedAtEpoch as Lang.Number = 0;

    // Whether the lock's last release was a human reconciliation rather than a confirmed outcome. Pure.
    function lockWasManuallyResolved() as Lang.Boolean {
        return lockResolvedReqId != null;
    }

    // Unit-test seam (mirrors RemoteComm.testPhoneReachable / testSuppressTransmit). The audit record is
    // DURABLE by design, which means a case that exercises a release would otherwise leak it into every
    // later case and every later simulator session. Clears the in-memory pair AND the Storage key so
    // tests/UnresolvedSendLockTest.mc's cases stay order-independent. Never called outside the unit
    // suite: shipping code has no reason to erase an audit record, and deliberately no way to.
    function clearLockResolvedRecordForTest() as Void {
        lockResolvedReqId = null;
        lockResolvedAtEpoch = 0;
        Storage.deleteValue(KEY_LOCK_RESOLVED);
    }

    // Path 2. Release the LOCK for a SPECIFIC dispatch, on the phone's say-so, after a human checked the
    // pump. Returns whether it applied. Refuses unless `reqId` matches the live tombstone, so a stale,
    // duplicated or mismatched message can never unlock a DIFFERENT unresolved dispatch, and a resolve
    // arriving when nothing is locked is a no-op rather than a state change.
    function resolveUnresolvedSendLock(reqId as Lang.String) as Lang.Boolean {
        var live = unresolvedTombstoneReqId;
        if (live == null) { return false; }
        if (!reqId.equals(live as Lang.String)) { return false; }
        lockResolvedReqId = reqId;
        lockResolvedAtEpoch = Time.now().value();
        Storage.setValue(KEY_LOCK_RESOLVED, { "requestId" => reqId, "at" => lockResolvedAtEpoch });
        clearUnresolvedTombstone();
        return true;
    }

    // The write is gated on `dispatched` here, structurally separated from sendBolusNow's
    // own control flow, specifically so "no durable tombstone unless dispatch might have occurred" is
    // directly unit-testable — RemoteComm.sendBolus's own true/false outcome depends on
    // System.getDeviceSettings().phoneConnected, which is not sim-controllable in this environment (see
    // tests/UnresolvedDeliveryTombstoneTest.mc, which drives this seam with both booleans directly).
    function maybeWriteUnresolvedTombstone(dispatched as Lang.Boolean, reqId as Lang.String, sentAt as Lang.Number, doseKey as Lang.String) as Void {
        if (dispatched) { persistUnresolvedTombstone(reqId, sentAt, doseKey); }
    }

    // Armed-dose eligibility generation. `bolusEligibilityGen` increments whenever the bolus
    // eligibility fingerprint changes on a statusRead (see handle()); `armBolus()` snapshots it into
    // `armedEligibilityGen` at compose (BolusEntryDelegate.captureDose). A mismatch means the therapy/
    // policy state changed AFTER the wearer armed, so the armed confirm must be torn down and the send
    // refused (re-confirm). `_prevEligibilityFp` is the last-seen fingerprint — null until the first
    // statusRead, so the very first reply never counts as a change.
    (:background)
    var bolusEligibilityGen as Lang.Number = 0;
    var armedEligibilityGen as Lang.Number = 0;
    (:background)
    var _prevEligibilityFp as Lang.String? = null;

    // The wall-clock instant the CURRENT arm (armBolus()) was snapshotted — 0 before the first
    // ever arm. This is the "elapsed-time" half of the arm-staleness guard, distinct from `appLive()`'s
    // own liveness anchor (`lastReplyEpoch`, refreshed by every inbound reply): a dose can stay "live" the whole time
    // (the phone keeps replying to routine polls) yet the wearer's OWN confirm can still land long after
    // they armed it — this tracks THAT gap specifically. `armContextExpired()` is the pure decision;
    // sendBolusNow() re-checks it at the final send (belt), and eligibilityFingerprint() folds it in so
    // an intervening statusRead can also catch it via the existing gen-bump teardown path (suspenders).
    (:background)
    var armedAtEpoch as Lang.Number = 0;
    (:background)
    const ARM_CONTEXT_STALE_SEC = 120;

    // Pure: has the CURRENTLY-armed context aged past ARM_CONTEXT_STALE_SEC since armBolus()?
    // Guards on armedAtEpoch > 0 so "never armed" can never spuriously read as expired. Deterministic
    // (wall-clock only, no reachability) → unit-testable.
    (:background)
    function armContextExpired() as Lang.Boolean {
        return armedAtEpoch > 0 && (Time.now().value() - armedAtEpoch) > ARM_CONTEXT_STALE_SEC;
    }

    // Outcome watchdog. `outcomeSentEpoch` is the wall-clock (Unix sec) a bolus/cancel was sent;
    // if no authoritative terminal echo arrives within OUTCOME_DEADLINE_SEC the watchdog flips a stuck
    // "delivering"/"cancelling" to an honest "unknown" (never fabricating delivered/cancelled). Distinct
    // from `lastReplyEpoch` (reply-time, below) — this is send-time.
    var outcomeSentEpoch as Lang.Number = 0;
    const OUTCOME_DEADLINE_SEC = 30;

    // App-level liveness. `lastReplyEpoch` is the wall-clock (Unix sec) of the last inbound phone
    // reply (stamped at the top of handle()); `appLive()` gates a bolus on a RECENT reply — distinct from
    // the raw BLE link (RemoteComm.phoneReachable()), which stays "connected" even when faBolus is killed.
    (:background)
    var lastReplyEpoch as Lang.Number = 0;
    (:background)
    const CONNECTION_STALE_SEC = 60;

    // Foreground poll cadence + the reply-outstanding deadline. Deadline ordering (kept consistent):
    // POLL_REPLY_DEADLINE_SEC (12) < OUTCOME_DEADLINE_SEC (30) < CONNECTION_STALE_SEC (60); POLL_MAX_MS
    // bounds the backoff so the outcome watchdog's backstop (which rides the poll's reschedule loop)
    // keeps ticking. The jitter + outstanding-gate live in FaBolusApp; only pollBaseDelayMs is pure.
    const POLL_REPLY_DEADLINE_SEC = 12;
    const POLL_BASE_MS = 15000;
    const POLL_MAX_MS = 120000;

    // The requestId minted for the FOREGROUND poll's statusRead REQUEST (FaBolusApp.pollTick),
    // retained so FaBolusApp.handlePhoneData can accept ONLY the correlated reply — mirroring
    // BgServiceDelegate.mintedReqId (BgService.mc) exactly. Before this, the fg path applied ANY
    // statusRead-kind reply without checking it was the one WE asked for; a stale/late reply (e.g. from a
    // superseded poll) could mutate glucose/iob/etc. isCorrelatedStatusReply() is the shared correlation
    // primitive (already used by the bg service) — this field is the fg side's counterpart storage.
    var fgPollMintedReqId as Lang.String? = null;

    function reset() as Void {
        mode = defaultMode; unitsValue = 0.0; carbsValue = 0;
        pendingRequestId = null; status = null; message = null; sawPhoneBolusing = false;
        outcomeSentEpoch = 0;     // clear the outcome watchdog send-stamp with the in-flight state
        includeStaleBg = false;   // the stale-BG include choice is per-attempt — never carried over
        lastSendRefusal = null;   // a new compose never inherits the last attempt's refusal notice
    }

    // WHICH hard guard blocks a send RIGHT NOW — the six conditions of sendBolusNow(), in sendBolusNow's
    // exact order, as a reason TOKEN instead of a bare Boolean; null when nothing blocks. sendBolusNow()
    // consumes THIS as its single decision point, so the gate and what the wearer is told can never
    // diverge and no predicate is duplicated between them.
    //
    // It exists because the Boolean threw the cause away. HoldView could only explain the two conditions
    // mustTeardownArmedBolus() covers (bolusPolicyDisabled, a moved eligibility gen); the other four
    // silently reset the 1-2-3 tap progress, so the wearer's 3rd tap looked dead with no reason given —
    // on a delivery-authorising surface. Two of those four are silent BY CONSTRUCTION, not by accident:
    // eligibilityFingerprint()'s `live` token is evaluated only inside handle(), immediately after
    // lastReplyEpoch is stamped, so it is unconditionally "1" and an appLive() lapse can NEVER bump the
    // gen; and reattemptBlocked() is not folded into the fingerprint at all.
    //
    // NOTHING here loosens, reorders, shortens or fails open any gate: these are the send gate's own six
    // expressions in the send gate's own order, character for character. reattemptBlocked() is entered on
    // the identical condition and only its REPORTING splits in two, because "wait for the result you already
    // have in flight" and "an earlier dispatch was never confirmed — check the pump's own history" are
    // different remedies for the wearer. Pure/deterministic (wall-clock only) → unit-testable; see
    // tests/SendRefusalDisclosureTest.mc.
    function bolusSendRefusal() as Lang.String? {
        if (bolusPolicyDisabled()) { return "policyDisabled"; }
        if (armedEligibilityGen != bolusEligibilityGen) { return "staleArm"; }
        if (!appLive()) { return "phoneNotLive"; }
        if (armContextExpired()) { return "armExpired"; }
        if (!pumpBolusAllowed()) { return "pumpBlocked"; }
        if (reattemptBlocked()) { return outcomePending() ? "outcomePending" : "unresolvedPriorSend"; }
        return null;
    }

    // Confirm-screen copy budgets, from what this tree already ships: the longest FONT_SMALL literal on
    // any screen is 14 chars ("Status changed", "Cancel (START)") and DetailsView documents a ~28-char
    // FONT_XTINY row budget. A refusal notice that CLIPS is barely better than the silence it replaces, so
    // both limits are asserted over every string below in tests/SendRefusalDisclosureTest.mc. They are
    // what keeps the specific host reason (bolusReasonText, up to 19 chars: "Phone not connected") off the
    // headline — pumpBlocked's headline is therefore the fixed literal "Pump not ready", NOT a
    // bolusReasonText() lookup, and the wearer still gets the host's own reason on the main screen
    // through bolusBlockLabel().
    // The detail cap carries 2 chars of slack over the 28-glyph budget on purpose: every detail line
    // contains one em dash, and Lang.String.length() counting UTF-8 BYTES rather than characters would
    // inflate each of them by 2. The slack makes the assertion robust to that ambiguity while still
    // catching a genuinely runaway line. Headlines have no multi-byte characters, so 14 is exact.
    const REFUSAL_HEAD_MAX_CHARS = 14;
    const REFUSAL_DETAIL_MAX_CHARS = 30;

    // Pure token → confirm-screen HEADLINE. "" for null/unknown so a future token can never crash the
    // draw (mirrors bolusReasonText). policyDisabled/staleArm keep the wording HoldView's own pre-existing
    // notice already uses, so the vocabulary stays identical across the two surfaces.
    function sendRefusalText(reason as Lang.String or Null) as Lang.String {
        if (reason == null) { return ""; }
        if (reason.equals("policyDisabled")) { return "Bolusing off"; }
        if (reason.equals("staleArm")) { return "Status changed"; }
        if (reason.equals("phoneNotLive")) { return "No phone reply"; }
        if (reason.equals("armExpired")) { return "Expired"; }
        if (reason.equals("pumpBlocked")) { return "Pump not ready"; }
        if (reason.equals("outcomePending")) { return "Bolus pending"; }
        if (reason.equals("unresolvedPriorSend")) { return "Earlier dose"; }
        return "";
    }

    // Pure token → confirm-screen DETAIL line. Every line opens with "not sent" — on a delivery-
    // authorising surface the wearer must never be left able to believe insulin went in, and the honest
    // fact common to all six is that this attempt transmitted nothing (all six guards return before
    // RemoteComm mints a requestId). unresolvedPriorSend deliberately does NOT claim the earlier dose was
    // or was not delivered: that outcome is genuinely unknown, which is the whole reason the durable
    // tombstone exists, so it names the pump's own history as the authority instead. "" for null/unknown.
    function sendRefusalDetail(reason as Lang.String or Null) as Lang.String {
        if (reason == null) { return ""; }
        if (reason.equals("policyDisabled")) { return "not sent — off on phone"; }
        if (reason.equals("staleArm")) { return "not sent — re-confirm"; }
        if (reason.equals("phoneNotLive")) { return "not sent — reopen faBolus"; }
        if (reason.equals("armExpired")) { return "not sent — start over"; }
        if (reason.equals("pumpBlocked")) { return "not sent — check the pump"; }
        if (reason.equals("outcomePending")) { return "not sent — wait for result"; }
        if (reason.equals("unresolvedPriorSend")) { return "not sent — see pump history"; }
        return "";
    }

    // The watch-side DISCLOSURE for a locked-out bolus affordance, as plain-language lines the
    // UnresolvedSendView draws verbatim. Pure (no state read) → unit-testable, and kept here rather than
    // in the view so the honesty properties below are asserted by the test suite rather than by eyeball.
    //
    // Every line is held to the ~28-char FONT_XTINY row budget DetailsView documents (asserted in
    // tests/UnresolvedSendLockTest.mc), because a disclosure that clips off the edge of a 390 px round
    // face is not a disclosure. The wording is bounded by three hard rules, all of them tested:
    //   • it must NOT say the dose was delivered, and must NOT say it was not delivered — the honest
    //     state is UNKNOWN, and claiming either direction could cause a double-dose or a missed dose;
    //   • it must send the wearer to the PUMP'S OWN history/IOB, the only authority on the wrist's side
    //     of the question;
    //   • it must not promise the watch can unlock itself, because it cannot and must not.
    const UNRESOLVED_LINE_MAX_CHARS = 30;
    function unresolvedSendDisclosure() as Lang.Array {
        return ["A bolus was sent but never",
                "confirmed. faBolus cannot",
                "know if insulin was given.",
                "Check the pump's history and",
                "IOB before dosing again.",
                "Clears when faBolus confirms."];
    }

    // The SINGLE bolus send funnel. Extracted verbatim from HoldView.deliver() so
    // BOTH confirm surfaces send through the identical path with NO duplicated or divergent delivery
    // semantics:
    //   • HoldView (tap/hold confirm, no passcode)      → sendBolusNow(null)
    //   • PasscodeEntryView (passcode confirm)          → sendBolusNow(enteredCode)
    // It mints the reqId, sets pendingRequestId, resets the lost-echo tracker, checks reachability, sets
    // status="delivering", and calls the RemoteComm builder — exactly as before. `code` is threaded to the
    // builder, which adds "bolusPasscode" to the wire only when non-null. The WATCH NEVER verifies or
    // persists the code — the phone is the sole authority and denies a wrong/absent one.
    //
    // Returns false — WITHOUT sending anything — when a hard guard blocks the send, so the caller de-arms
    // its own view-local confirm state and the wearer re-confirms against current state:
    //   • policy-disabled (read-only ON or Garmin bolusing OFF pushed while confirming);
    //   • the eligibility generation moved since the arm (therapy/policy/last-bolus changed);
    //   • the pump no longer permits a bolus (pumpBolusAllowed() re-check at transmit);
    //   • the wrist context has gone stale/offline (appLive()) or the arm itself has aged past
    //     ARM_CONTEXT_STALE_SEC (armContextExpired()) — re-checked HERE, at the literal final send, so a
    //     dose armed in a since-expired context is never transmitted even when no intervening statusRead
    //     ever bumped bolusEligibilityGen to catch it;
    //   • an outcome is still pending (reattemptBlocked() — never mint a second reqId in flight).
    // Returns true when a request was sent OR a terminal status was set (outOfRange), i.e. the confirm
    // surface is done and status now owns the screen.
    function sendBolusNow(code as Lang.String?) as Lang.Boolean {
        // The six hard guards live in bolusSendRefusal() — verbatim, in this same order, with this same
        // short-circuit behavior — so the refusal the wearer is SHOWN is by construction the refusal the
        // gate actually stopped on. Reading them from one place is the whole point: a duplicated predicate
        // list on a delivery-authorising path could drift and disclose a different reason than it enforced.
        // Refuses, in order: policy-disabled (read-only ON or Garmin bolusing OFF pushed while
        // confirming); the eligibility generation moved since the arm (therapy/policy/last-bolus changed);
        // the wrist context has gone stale/offline (appLive()) or the arm itself has aged past
        // ARM_CONTEXT_STALE_SEC (armContextExpired()) — re-checked HERE, at the literal final send, so a
        // dose armed in a since-expired context is never transmitted even when no intervening statusRead
        // ever bumped bolusEligibilityGen to catch it; the pump no longer permits a bolus
        // (pumpBolusAllowed() re-check at transmit); an outcome is still pending or a prior dispatch is
        // unresolved (reattemptBlocked() — never mint a second reqId on top of one, a double-dose decision
        // hazard). Nothing has been transmitted and no reqId minted at this point, so the caller de-arms
        // its view-local confirm and the wearer re-confirms against current state.
        var refusal = bolusSendRefusal();
        if (refusal != null) {
            // Record WHY so the confirm surface can say it. Before this, the bare `return false` left
            // HoldView.deliver() able only to zero the tap progress — silently, for the four conditions
            // mustTeardownArmedBolus() cannot see.
            lastSendRefusal = refusal;
            return false;
        }
        lastSendRefusal = null;   // this attempt is proceeding — never show a stale refusal over it
        var reqId = RemoteComm.newRequestId();
        pendingRequestId = reqId;
        sawPhoneBolusing = false;   // reset the lost-echo recovery tracker for this request
        if (!RemoteComm.phoneReachable()) {
            status = "outOfRange"; message = "iPhone unreachable"; return true;
        }
        status = "delivering";
        outcomeSentEpoch = Time.now().value();   // stamp send-time for the outcome watchdog
        // Carbs mode: send carbsGrams (+ bg + this watch's estimate) so the phone is the single
        // calculator and can run the divergence guard. Units mode: send the units as before.
        // Dispatch through RemoteComm.sendBolus (NOT the fire-and-forget send) so a transmit that
        // fails is reported back — dispatched==false means nothing went out.
        var dispatched = false;
        if (mode.equals("carbs")) {
            // Fresh → the reading; stale → included only on the explicit per-attempt
            // "include" choice, else nil-dropped (carbs-only). bgForBolus() encapsulates that decision.
            // Also forward the include-stale INTENT (includeStaleBg — the same per-attempt flag,
            // cleared by reset()) so the host can honor an acknowledged-stale correction instead of failing
            // closed to carbs-only. The builder omits it entirely unless true (never sent on units mode).
            var bg = bgForBolus();
            dispatched = RemoteComm.sendBolus(RemoteComm.bolusRequestCarbs(carbsValue, bg, deliverUnits, reqId, code, includeStaleBg), reqId);
        } else {
            dispatched = RemoteComm.sendBolus(RemoteComm.bolusRequest(deliverUnits, reqId, code), reqId);
        }
        // Persist the durable tombstone ONLY when dispatch might have occurred —
        // see maybeWriteUnresolvedTombstone's own doc for why this exact gate matters (a
        // provably-unsent request must never leave a permanent lock).
        maybeWriteUnresolvedTombstone(dispatched, reqId, outcomeSentEpoch, doseKeyFor());
        // A synchronously-failed dispatch (the phone dropped between the reachability check above
        // and transmit, or Comm.transmit threw) must surface as "failed" — never a stuck "delivering…".
        // An ASYNC transport failure AFTER a true dispatch is caught by BolusCommListener.onError →
        // noteBolusSendFailed(reqId). We keep pendingRequestId so a late authoritative echo can still
        // upgrade the outcome.
        if (!dispatched) {
            status = "failed";
            if (message == null) { message = "Send failed — not delivered."; }
        }
        return true;
    }

    // An outcome is PENDING while a bolus/cancel we sent hasn't reached an authoritative terminal
    // state — only "delivering"/"cancelling" (delivered/cancelled/failed/unknown/outOfRange are terminal).
    // Pure/deterministic → unit-testable.
    function outcomePending() as Lang.Boolean {
        return status != null && (status.equals("delivering") || status.equals("cancelling"));
    }

    // A bolus status is TERMINAL once it reaches an authoritative outcome — delivered/cancelled/failed,
    // plus 'unknown' as a degraded-terminal (the watchdog's honest timeout). The complement of outcomePending's
    // non-terminal set (delivering/cancelling). Pure/deterministic → unit-testable. Used to stop a late
    // duplicate NON-terminal echo (same requestId) from regressing an authoritative terminal in handle().
    (:background)
    function isTerminalStatus(s as Lang.String?) as Lang.Boolean {
        return s != null && (s.equals("delivered") || s.equals("cancelled") || s.equals("failed") || s.equals("unknown"));
    }

    // A status is AUTHORITATIVELY RESOLVED only for a
    // genuine outcome — delivered/cancelled/failed. Deliberately EXCLUDES "unknown": that token is
    // the outcome watchdog's honest-timeout / the phone's indeterminate echo, meaning the outcome is still
    // genuinely AMBIGUOUS — exactly the case the unresolved-delivery tombstone exists to guard against a
    // race re-send. isTerminalStatus() above INCLUDES "unknown" because it serves a different purpose
    // (stopping a late non-terminal echo from regressing an honest timeout in the block below) — do not
    // reuse it for the tombstone-clear gate, and do not add "unknown" here.
    (:background)
    function isAuthoritativelyResolved(s as Lang.String?) as Lang.Boolean {
        return s != null && (s.equals("delivered") || s.equals("cancelled") || s.equals("failed"));
    }

    // The outcome deadline has passed with no authoritative terminal echo. Guards on
    // outcomeSentEpoch > 0 so a pending status with no send-stamp can never spuriously expire.
    function outcomeDeadlineExpired() as Lang.Boolean {
        return outcomePending() && outcomeSentEpoch > 0
            && (Time.now().value() - outcomeSentEpoch) > OUTCOME_DEADLINE_SEC;
    }

    // The watchdog tick. Flips a stuck delivering/cancelling to an honest "unknown" once the
    // deadline expires — NEVER fabricating delivered/cancelled. KEEPS pendingRequestId so a late
    // authoritative echo (by requestId) can still upgrade the outcome. Returns true when it changed state
    // so the caller (HoldView timer / FaBolusApp poll) can Ui.requestUpdate(). Idempotent once flipped.
    function tickOutcomeWatchdog() as Lang.Boolean {
        if (!outcomeDeadlineExpired()) { return false; }
        status = "unknown";
        if (message == null) { message = "No response — check the pump/t:connect history."; }
        return true;
    }

    // Clear ALL in-flight bolus state — used by HoldDelegate.onBack() so a back-out doesn't orphan
    // a "delivering" status + pendingRequestId (a stale outcome left on screen that could confuse a later
    // attempt). The phone owns the actual delivery + its own (peer,requestId) ledger, so forgetting the
    // local view state here never re-triggers or double-doses.
    function clearInFlight() as Void {
        status = null; message = null; pendingRequestId = null;
        sawPhoneBolusing = false; outcomeSentEpoch = 0;
    }

    // A NEW send must be refused while an outcome is still pending — never mint a second reqId on
    // top of an in-flight one. Checked in sendBolusNow before minting.
    // ALSO refused while a durable unresolved-delivery tombstone survives from a
    // PRIOR process (a cold relaunch loses `status`/`outcomePending()`'s in-memory backing, but the
    // tombstone is durable) — this is what makes a relaunch honor an unresolved dispatch, not just the
    // current process's own in-memory outcome tracking.
    function reattemptBlocked() as Lang.Boolean {
        return outcomePending() || hasUnresolvedTombstone();
    }

    // Mark an in-flight bolus send as FAILED — pure/guarded so it can never regress a terminal
    // outcome or touch the wrong request. Called by RemoteComm.BolusCommListener.onError (async transport
    // failure) and by sendBolusNow itself when the synchronous dispatch reports false. No-op unless there
    // IS an in-flight request (pendingRequestId non-null), the reqId matches it (a late error for a
    // superseded/other request — or a null reqId — is ignored), and the status is still pending
    // (delivering|cancelling): a terminal delivered/cancelled/unknown/failed is NEVER regressed. Keeps
    // pendingRequestId so a later authoritative bolusStatus echo can still upgrade the outcome.
    function noteBolusSendFailed(reqId as Lang.String?) as Void {
        if (pendingRequestId == null) { return; }
        if (reqId == null || !reqId.equals(pendingRequestId)) { return; }
        if (!outcomePending()) { return; }
        status = "failed";
        if (message == null) { message = "Send failed — not delivered."; }
    }

    // Pure: the base poll delay (ms) for a given consecutive-miss backoff level — POLL_BASE_MS
    // doubled per level, capped at POLL_MAX_MS. level 0 => 15000, 1 => 30000, 2 => 60000, 3+ => 120000.
    // Jitter + the outstanding-gate live in FaBolusApp (sim/hardware-only); this pure step is unit-tested.
    function pollBaseDelayMs(level as Lang.Number) as Lang.Number {
        var d = POLL_BASE_MS;
        for (var i = 0; i < level; i += 1) {
            d *= 2;
            if (d > POLL_MAX_MS) { d = POLL_MAX_MS; }
        }
        return d;
    }

    // A one-time, plain-language notice shown the first time the wearer opens the
    // bolus flow — that bolusing from the watch is off by default and is turned on/off from faBolus on
    // the phone. The "shown" flag is PERSISTED so it appears exactly once for the life of the install
    // (survives restarts / re-opens). Garmin-local: this does NOT invert or restate any host copy — the
    // phone owns the enable toggle's own wording; this only tells the wearer where that toggle lives.
    const KEY_BOLUS_INTRO_SHOWN = "bolusIntroShown";
    function bolusIntroShown() as Lang.Boolean {
        return Storage.getValue(KEY_BOLUS_INTRO_SHOWN) == true;
    }
    function markBolusIntroShown() as Void {
        Storage.setValue(KEY_BOLUS_INTRO_SHOWN, true);
    }

    // A SEPARATE one-time notice, shown the FIRST time a passcode is actually
    // required, explaining that a 4-digit passcode set in faBolus on the phone now confirms a bolus
    // (replacing the tap/hold). A "prompt at pairing time" has no on-watch equivalent — pairing
    // is done phone-side on Garmin — so this first-use notice is the correct on-watch stand-in. Its own
    // persisted flag (separate from KEY_BOLUS_INTRO_SHOWN) so it appears exactly once for the life of the
    // install, set at DISPLAY time (before the notice is pushed) so it shows once even if the wearer backs
    // out. Same persisted-boolean shape as bolusIntroShown() (a non-true value errs toward showing).
    const KEY_PASSCODE_INTRO_SHOWN = "passcodeIntroShown";
    function passcodeIntroShown() as Lang.Boolean {
        return Storage.getValue(KEY_PASSCODE_INTRO_SHOWN) == true;
    }
    function markPasscodeIntroShown() as Void {
        Storage.setValue(KEY_PASSCODE_INTRO_SHOWN, true);
    }

    // Seed glucose/trend from the persisted complication value so the glance shows the last-known
    // reading immediately on open, instead of "--" while the first phone reply is in flight.
    (:background)
    function loadPersisted() as Void {
        var g = Storage.getValue(BgComplication.KEY_BG);
        if (g != null && isNum(g)) { glucose = g.toNumber(); }
        var t = Storage.getValue(BgComplication.KEY_TREND);
        if (t != null && t instanceof Lang.String) { trend = t; }
        var e = Storage.getValue(BgComplication.KEY_EPOCH);
        if (e != null && isNum(e)) { readingEpoch = e.toNumber(); }
    }

    function toggleMode() as Void {
        mode = mode.equals("units") ? "carbs" : "units";
    }

    // dir = +1 / -1
    function adjust(dir as Lang.Number) as Void {
        if (mode.equals("units")) {
            unitsValue += dir * stepU;
            if (unitsValue < 0.0) { unitsValue = 0.0; }
            if (unitsValue > maxUnits) { unitsValue = maxUnits; }
        } else {
            carbsValue += dir * stepC;
            if (carbsValue < 0) { carbsValue = 0; }
            if (carbsValue > MAX_CARBS) { carbsValue = MAX_CARBS; }
        }
    }

    // The units that will actually be delivered (rounded to 0.05, clamped to the pump max).
    // A wrist-side preview only: the phone (host) recomputes the authoritative dose with the same
    // oracle-backed calculator and runs the divergence guard before delivery.
    //
    // This is a hand-port of faBolusCore/BolusMath.estimate() — the faithful Tandem oracle logic
    // Keep it in lockstep with that Swift/Java source. The key correctness point:
    //   • food = carbs / carbRatio
    //   • fromBG = (glucose - target) / isf   (SIGNED — a below-target BG is negative and REDUCES the dose)
    //   • fromIOB = -iob (only when iob > 0)   — IOB offsets a BG correction, never a bare carb dose
    //   • at/above target: add (fromBG + fromIOB) only if that sum is positive
    //   • below target: apply (fromBG + fromIOB) if it keeps the total positive, else floor total at 0
    // The old code floored the *correction* at 0 before combining, which dropped every below-target
    // reduction and over-recommended. Units mode is a manual fixed dose (no correction / IOB).
    // The oracle's BolusCalcUnits.doublePrecision — BigDecimal.setScale(2, HALF_UP): round to two
    // decimals, ties AWAY from zero (so it matches faBolusCore/BolusMath.dp on every component). Monkey C's
    // Math.round is not HALF_UP for negatives, so we floor(|v|*100 + 0.5) and re-apply the sign.
    function dp2(v as Lang.Float) as Lang.Float {
        if (v >= 0.0) { return Math.floor(v * 100.0 + 0.5) / 100.0; }
        return -(Math.floor(-v * 100.0 + 0.5) / 100.0);
    }

    function computeUnits() as Lang.Float {
        var total;
        if (mode.equals("units")) {
            total = unitsValue;
        } else {
            total = carbCorrectionTotal();
        }
        total = Math.round(total * 20.0) / 20.0;   // 0.05 u steps
        if (total < 0.0) { total = 0.0; }
        if (total > maxUnits) { total = maxUnits; }
        return total;
    }

    // The carb+correction math ONLY (unrounded, unclamped) — factored out of computeUnits()'s former
    // "carbs" branch so callers can read the SAME calculator total regardless of the CURRENT mode,
    // without a second, independently-drifting copy of this logic.
    // 0.0 when the carb ratio hasn't arrived from the phone (do NOT silently assume 10 g/U;
    // that is an unverified guess that could misdose. `carbCalcAvailable()` tells "genuinely zero"
    // apart from "not available yet").
    function carbCorrectionTotal() as Lang.Float {
        if (carbRatio <= 0.0) { return 0.0; }
        // Round EACH component to two decimals (half-up) before combining — exactly as the
        // oracle-backed host does. Combining unrounded components then rounding only the total drifted
        // by one 0.05 U pump increment on ~1.5% of inputs, and the host's 0.10 U tolerance accepted it,
        // so the delivered dose could differ from the number shown on the hold screen.
        var fromCarbs = dp2(carbsValue.toFloat() / carbRatio);
        var fromBG = 0.0;
        // A stale BG is dropped from the correction (carbs-only) UNLESS the wearer
        // made the explicit, per-attempt "include" choice this compose (includeStaleBg) — never sticky,
        // never default. Fresh always corrects. Keeps the wrist preview in lockstep with bgForBolus().
        if (isf > 0 && glucose != null && (!glucoseStale() || includeStaleBg)) {
            fromBG = dp2((glucose - targetBg).toFloat() / isf.toFloat());   // signed
        }
        var fromIOB = (iob > 0.0) ? dp2(-iob) : 0.0;
        var total = fromCarbs;
        if (fromBG >= 0.0) {                        // at or above target
            var corr = fromBG + fromIOB;
            if (corr > 0.0) { total += corr; }      // else IOB cancels the correction → add nothing
        } else {                                    // below target — correction reduces the dose
            var corr = fromBG + fromIOB;
            if (total + corr > 0.0) { total += corr; }
            else { total = 0.0; }                   // would go negative → floor the total at 0
        }
        return dp2(total);                           // oracle dp() on the combined total too
    }

    function valueLabel() as Lang.String {
        if (mode.equals("units")) { return unitsValue.format("%.2f") + " U"; }
        return carbsValue.toString() + " g";
    }

    // A carb bolus can only be estimated on the wrist once the pump's carb ratio has synced from
    // the phone. Units mode never needs it. When false the UI shows "calculator unavailable" and blocks
    // the bolus (we do NOT fall back to an assumed 10 g/U).
    function carbCalcAvailable() as Lang.Boolean {
        return !mode.equals("carbs") || carbRatio > 0.0;
    }

    // Route an inbound phone message.
    // Pure: is this inbound phone message the correlated statusRead reply the background
    // service is waiting for? The background poll sends a statusRead and must publish + exit ONLY on the
    // matching reply — an unrelated dict (a stray bolusStatus echo, or an
    // empty {}) that lands first must be IGNORED (not mistaken for the reply, which would exit early and
    // drop the fresh read). This is the KIND discriminator, retained as the fallback for a legacy
    // phone that does not echo the requestId; `isCorrelatedStatusReply` layers true id correlation on top.
    (:background)
    function isStatusReply(dict as Lang.Dictionary) as Lang.Boolean {
        var kind = dict["kind"];
        return kind instanceof Lang.String && (kind as Lang.String).equals("statusRead");
    }

    // Pure: TRUE request-id correlation for a statusRead reply. The watch mints a requestId for its
    // statusRead REQUEST and retains it; the phone now ECHOES that id in its reply (faBolus
    // AppModel.statusCommand(replyingTo:)). Accept a reply as OURS iff it is a statusRead (kind) AND its
    // echoed requestId matches the one we minted. A reply with NO requestId is a legacy phone that doesn't
    // echo → fall back to the kind discrimination only (backward-compatible). A mismatching requestId is a
    // stale/other reply and is rejected. `mintedReqId == null` (we didn't retain one) also falls back to
    // kind. Deterministic → unit-testable.
    (:background)
    function isCorrelatedStatusReply(dict as Lang.Dictionary, mintedReqId as Lang.String?) as Lang.Boolean {
        if (!isStatusReply(dict)) { return false; }
        var rid = strCap(dict["requestId"], 64);
        if (rid == null || mintedReqId == null) { return true; }   // legacy phone (no echo) / no retained id → kind fallback
        return rid.equals(mintedReqId);
    }

    // Should the background push-wake path (BgServiceDelegate.onPhoneAppMessage)
    // consume this inbound message? A push-wake creates a FRESH service instance that sent no request, so
    // it has no minted requestId (mintedReqId == null) — isCorrelatedStatusReply then falls back to the
    // kind discriminator, accepting a `kind=="statusRead"` push. A non-Dictionary payload, or a
    // non-statusRead dict (a stray toggle/echo), is NOT handleable — the caller changes nothing and does
    // not exit early (mirrors onPhoneMessage's guard; the system bounds the wake's runtime). Deterministic
    // → unit-testable, so BgPushWakeTest can drive it without a system-delivered PhoneAppMessage instance.
    (:background)
    function isHandleablePush(data, mintedReqId as Lang.String?) as Lang.Boolean {
        return (data instanceof Lang.Dictionary)
            && isCorrelatedStatusReply(data as Lang.Dictionary, mintedReqId);
    }

    (:background)
    function handle(data as Lang.Dictionary) as Void {
        // Reuse the existing strCap() guard (instanceof-checked) instead of the bare
        // `as Lang.String?` cast — a non-null, non-String `kind` (malformed/hostile wire dict) used to hit
        // an unguarded cast here and crash the handler. A non-String kind now safely resolves to null,
        // same as an absent kind.
        var kind = strCap(data["kind"], 64);
        if (kind == null) { return; }
        // Any well-formed inbound reply (statusRead OR bolusStatus) proves the faBolus app is
        // alive — stamp the liveness anchor before dispatching. appLive()/canBolus() read this.
        lastReplyEpoch = Time.now().value();
        // Any phone reply reconciles the alerts list authoritatively, so clear the transient
        // offline-dismiss notice here (its lifetime is "until the next handle()").
        alertDismissFailedOffline = false;
        if (kind.equals("statusRead")) {
            // Guard the assignment: a partial statusRead that omits bgMgdl must NOT null out the
            // last-known glucose (which would blank the value + disable correction dosing). Keep last.
            // Every field is range/finite-validated before it mutates state; a bad value returns
            // null and the last good reading is kept (see numRange/fltRange/validTrend/strCap).
            var bg = numRange(data["bgMgdl"], 0, 600); if (bg != null) { glucose = bg; }
            var t = validTrend(data["trend"]); if (t != null) { trend = t; }
            var i = fltRange(data["units"], 0.0, 100.0); if (i != null) { iob = i; }
            var cr = fltRange(data["carbRatio"], 1.0, 300.0); if (cr != null) { carbRatio = cr; }
            var isfv = numRange(data["isf"], 1, 1000); if (isfv != null) { isf = isfv; }
            var tb = numRange(data["targetBg"], 40, 400); if (tb != null) { targetBg = tb; }
            var mx = fltRange(data["maxBolusUnits"], 0.0, 100.0); if (mx != null) { maxUnits = mx; }
            // Current basal delivery rate — NOT persisted (mirrors `iob`), kept
            // at its last-known value on an absent/invalid key exactly like every other live field here.
            var br = fltRange(data["basalRate"], 0.0, 25.0); if (br != null) { basalRate = br; }
            var rv = fltRange(data["reservoirUnits"], 0.0, 1000.0); if (rv != null) { reservoir = rv; }
            var bt = numRange(data["batteryPercent"], 0, 100); if (bt != null) { battery = bt; }
            // Fail-closed, unconditional — true ONLY on an explicit
            // boolean-true wire value; absent/invalid/false all resolve to false every statusRead
            // (never "keep last known true"), so a stale claim can't survive a dropped key.
            var bc = data["batteryCharging"];
            batteryCharging = (bc instanceof Lang.Boolean) && bc;
            var cn = strCap(data["message"], 120); if (cn != null) { connection = cn; }
            // The AUTHORITATIVE terminal outcome is the phone's bolusStatus echo (by
            // requestId), handled below — including the "unknown" status when the pump outcome is
            // genuinely indeterminate. If we've seen the phone bolusing and it's no longer bolusing but the
            // terminal echo never arrived, do NOT fabricate an outcome from the connection string. That
            // applies to a cancel too: a cancel REQUEST we sent is not a confirmed cancellation — the pump
            // may have finished the dose first. On a lost echo, surface "unknown" (delivering OR cancelling)
            // and point the user to pump/t:connect history; only an authoritative echo may show
            // delivered/cancelled.
            if (bolusing()) {
                sawPhoneBolusing = true;
            } else if (sawPhoneBolusing && status != null &&
                       (status.equals("delivering") || status.equals("cancelling"))) {
                status = "unknown";
                if (message == null) { message = "Outcome unknown — check the pump/t:connect history."; }
            }
            // Don't overwrite last-bolus from a routine push while a bolus is in progress — that value
            // is still the PREVIOUS bolus mid-delivery and would flicker. The bolusStatus echo (or the
            // recovery above) settles it to the just-delivered amount.
            var deliveringNow = (status != null && (status.equals("delivering") || status.equals("cancelling")));
            var lb = fltRange(data["lastBolusUnits"], 0.0, 100.0); if (lb != null && !deliveringNow) { lastBolus = lb; }
            // Prefer the phone's IMMUTABLE source epoch: an age is computed when
            // the phone composes the message, so by the time it lands here it already understates the
            // reading's true age. Fall back to the age only for a host too old to send an epoch.
            //
            // A reading with NEITHER an epoch nor an age has an UNKNOWN age, and unknown must mean
            // stale. It previously meant "now" — a value labelled "1 minute old"
            // that was in fact hours stale, and which then passed `!glucoseStale()` and fed the
            // correction term at `computeUnits()`. Leaving `readingEpoch` untouched makes such a value
            // inherit the previous reading's epoch and age out, matching what iOS already does
            // (`PumpSnapshot.isGlucoseStale`: no date ⇒ stale). Losing the arrow on an unknown-age
            // reading is the correct trade: showing less beats showing something inferred.
            var ep = data["glucoseEpochSec"];
            var ag = fltRange(data["glucoseAgeSec"], 0.0, 86400.0);
            if (ep instanceof Lang.Number && ep > 0) {
                // Clamp a future stamp (phone/watch clock skew) to "now" so it can never read as
                // fresher than fresh — a negative age would render as permanently current.
                var nowSec = Time.now().value();
                readingEpoch = (ep > nowSec) ? nowSec : ep;
            } else if (ag != null) {
                readingEpoch = Time.now().value() - ag.toNumber();
            }
            // Staleness policy from the phone: glucoseStaleMinutes (>0), glucoseHideDelayMinutes
            // (0 = hide when stale, absent = never hide).
            // The persist below is CONDITIONAL on glucoseStaleMinutes being
            // present+in-range (sm != null) — previously it ran on EVERY statusRead reply regardless,
            // which (a) clobbered the persisted policy with the in-memory default/last-good value on a
            // reply that simply omitted the key (never the phone's intent — every other field in this
            // parser already treats an absent/invalid key as "keep last", see numRange's own contract),
            // and (b) rewrote the same flash cell on every ~15s poll even when the policy never changed.
            var sm = numRange(data["glucoseStaleMinutes"], 1, 720);
            if (sm != null) {
                staleSec = sm * 60;
                // Persist the staleness policy so the glance / complication (separate launch
                // contexts) and a cold restart honor it before the next statusRead arrives.
                Storage.setValue("staleSec", staleSec);
            }
            var hd = numRange(data["glucoseHideDelayMinutes"], 0, 1440);
            hideDelaySec = (hd != null) ? hd * 60 : null;
            if (hideDelaySec != null) { Storage.setValue("hideDelaySec", hideDelaySec); }
            else { Storage.deleteValue("hideDelaySec"); }
            // Parse history and its per-point epochs in LOCKSTEP so the two arrays are guaranteed
            // equal-length and 1:1 aligned. sanitizeHistory drops out-of-range mg/dL, which would
            // misalign a separately-sanitized epochs array — so when epochs are present AND the raw
            // arrays are the same length, sanitize them as PAIRS (keep index k only if BOTH the reading
            // and the epoch are valid). Otherwise fall back to the mg/dL-only path and clear epochs, so
            // the invariant (aligned-or-empty) always holds.
            var hs = data["history"];
            if (hs instanceof Lang.Array) {
                var es = data["historyEpochs"];
                if (es instanceof Lang.Array && (es as Lang.Array).size() == hs.size()) {
                    var pair = sanitizeHistoryPairs(hs, es);
                    history = pair[0];
                    historyEpochs = pair[1];
                } else {
                    history = sanitizeHistory(hs);
                    historyEpochs = [];   // no/misaligned epochs → fall back to assumed spacing
                }
            }
            // Parse the DYNAMIC pump-tied capability BEFORE the alerts replace below: a relaunch's
            // first post-restart filtered statusRead (capability restored+re-parsed from THIS message)
            // must not fall through to the statusRead-reconcile fallback (`reconcileDismissSent`) with
            // no authenticated ack. Persisted (mirrors garminBolusEnabled), NOT
            // supportsRemoteAlertDismiss (declared false, never restored).
            var sda2 = data["supportsDismissAck"];
            if (sda2 instanceof Lang.Boolean) {
                // Change-detected — this capability is present on EVERY reply, so
                // writing unconditionally re-wrote the same flash cell on every poll even when unchanged.
                if (supportsDismissAck != sda2) { Storage.setValue(KEY_SUPPORTS_DISMISS_ACK, sda2); }
                supportsDismissAck = sda2;
            }
            // The raw-snapshot backstop's DYNAMIC capability, parsed+persisted alongside
            // supportsDismissAck (same reason: BEFORE the alerts-replace below, so the first
            // post-relaunch statusRead resolves the correct tier).
            var sra = data["supportsRawAlertSnapshot"];
            if (sra instanceof Lang.Boolean) {
                // Change-detected, same reasoning as supportsDismissAck above.
                if (supportsRawAlertSnapshot != sra) { Storage.setValue(KEY_SUPPORTS_RAW_ALERT_SNAPSHOT, sra); }
                supportsRawAlertSnapshot = sra;
            }
            // Detect whether `rawAlerts` is a PRESENT Array (nil/non-Array ⇒ absent) and, if
            // so, parse it into an identity set BEFORE the alerts-replace, using the TITLE-AGNOSTIC
            // absence-oracle parser (rawAlertIdentities, below) — never sanitizeAlerts, which would drop
            // a valid (id,kind) over a malformed title and falsely treat it as absent.
            var ra = data["rawAlerts"];
            var rawPresent = (ra instanceof Lang.Array);
            var rawIdents = rawPresent ? rawAlertIdentities(ra as Lang.Array) : [];
            // A fresh, authoritative alerts list just replaced the old one.
            // CAPABILITY-FIRST 3-way (never chosen by rawAlerts' presence): (1) supportsDismissAck ⇒
            // authenticated-ack-only; (2) else supportsRawAlertSnapshot ⇒ the
            // raw-snapshot tier — prune provisionals proven absent from a PRESENT rawAlerts (skip the
            // prune entirely when absent — fail-closed, keep-visible), THEN always overlay; (3) else ⇒
            // the statusRead-reconcile fallback (reconcileDismissSent — the ONLY proof-of-absence event
            // for the dismissSentAlertIdentities mechanism; markDismissSent/reconcileDismissSent
            // above). NEVER more than one branch: overlaying in the fallback branch would defeat its
            // filtered-absence removal with a stale, never-to-be-acked provisional; falling through
            // from the raw tier to that fallback on an absent rawAlerts would reintroduce the
            // local-snooze fail-open.
            var al = data["alerts"];
            if (al instanceof Lang.Array) {
                alerts = sanitizeAlerts(al);
                if (supportsDismissAck) {
                    overlayUnackedDismissProvisionals();
                } else if (supportsRawAlertSnapshot) {
                    if (rawPresent) { pruneProvisionalsAbsentFromRawSnapshot(rawIdents); }
                    overlayUnackedDismissProvisionals();
                } else {
                    reconcileDismissSent();
                }
            }
            var ro = data["remotesReadOnly"]; if (ro instanceof Lang.Boolean) { readOnly = ro; }
            // Capability channel: whether a remote dismiss clears on the pump (Mobi) or only snoozes
            // locally (t:slim) — drives the alert confirm verb. Strict guard: a non-boolean is ignored.
            var sd = data["supportsRemoteAlertDismiss"]; if (sd instanceof Lang.Boolean) { supportsRemoteAlertDismiss = sd; }
            // The host's semantic bolus availability + reason token (see hostCanBolus).
            var cb = data["canBolus"]; if (cb instanceof Lang.Boolean) { hostCanBolus = cb; }
            var cbr = data["bolusBlockReason"]; if (cbr instanceof Lang.String) { hostBolusBlockReason = strCap(cbr, 40); }
            // Whether bolusing from this Garmin is enabled on the phone (default OFF). Persist so a
            // cold launch stays fail-closed on the last-known value. Also the passcode-required flag (drives
            // confirm). Strict guards: a non-boolean is ignored (keeps the last / safe default).
            // Change-detected — garminBolusEnabled/bolusPasscodeRequired are present
            // on EVERY reply, so writing unconditionally re-wrote the same flash cell on every poll.
            var gbe2 = data["garminBolusEnabled"];
            if (gbe2 instanceof Lang.Boolean) {
                if (garminBolusEnabled != gbe2) { Storage.setValue("garminBolusEnabled", gbe2); }
                garminBolusEnabled = gbe2;
            }
            var bpr = data["bolusPasscodeRequired"];
            // Persist like garminBolusEnabled so a cold launch / background context knows a
            // passcode is required before the first statusRead (loadPrefs restores it). Strict guard: a
            // non-boolean is ignored (keeps the last / safe default). The watch only COLLECTS the code and
            // sends it; the phone verifies + persists nothing here beyond this required flag.
            if (bpr instanceof Lang.Boolean) {
                if (bolusPasscodeRequired != bpr) { Storage.setValue("bolusPasscodeRequired", bpr); }
                bolusPasscodeRequired = bpr;
            }
            // The phone-owned alert-intensity setting (mode / audible floor /
            // critical-DND-override). Persisted + change-detected exactly like garminBolusEnabled so a
            // relaunch / background service honors the last phone-synced value. FAIL-CLOSED: `mode` adopts
            // only one of the frozen tokens ("silent"|"vibrate"|"audible") — an absent/garbage value keeps
            // the safe "vibrate" default (vibration-only, nothing audible, nothing DND-piercing).
            // SETTINGS-ONLY — never a dose input; alert-surface only.
            var aim = data["alertIntensityMode"];
            if (aim instanceof Lang.String && containsStr(ALERT_MODES, aim as Lang.String)) {
                if (!alertIntensityMode.equals(aim)) { Storage.setValue("alertIntensityMode", aim); }
                alertIntensityMode = aim;
            }
            var aams = data["alertAudibleMinSeverity"];
            if (aams instanceof Lang.String && isValidSeverityTier(aams as Lang.String)) {
                if (!alertAudibleMinSeverity.equals(aams)) { Storage.setValue("alertAudibleMinSeverity", aams); }
                alertAudibleMinSeverity = aams;
            }
            var acod = data["alertCriticalOverridesDnd"];
            if (acod instanceof Lang.Boolean) {
                if (alertCriticalOverridesDnd != acod) { Storage.setValue("alertCriticalOverridesDnd", acod); }
                alertCriticalOverridesDnd = acod;
            }
            // The pump's controller identity + Control-IQ runtime on/off, for the LOCAL
            // auto-correction disclosure. FROZEN token set (CONTROLLER_VARIANTS = the schema
            // `controllerVariant` enum) — an unknown/garbage variant is ignored (keeps the last / safe
            // "none"). controlIQEnabled is strict-guarded like the other capability booleans. Display-
            // only: nothing here feeds a dose, so no persistence is needed.
            var cvr = data["controllerVariant"];
            if (cvr instanceof Lang.String && containsStr(CONTROLLER_VARIANTS, cvr as Lang.String)) { controllerVariant = cvr; }
            var ciqe = data["controlIQEnabled"];
            if (ciqe instanceof Lang.Boolean) { controlIQEnabled = ciqe; }
            // The pump's live Sleep/Exercise activity mode, now ALSO on
            // the shared statusRead reply. Strict-guarded to the pump's own 3-state range; an
            // out-of-range/non-Number value is ignored (keeps the last / safe "0" default), matching
            // controllerVariant's guard style just above. Not persisted (mirrors
            // controllerVariant/controlIQEnabled's own not-persisted reasoning).
            var ciqm = numRange(data["controlIQMode"], 0, 2);
            if (ciqm != null) { controlIQMode = ciqm; }
            // The already-decoded exercise countdown, raw remaining-seconds (NOT an epoch) — the phone
            // relays its CURRENT knowledge every statusRead (nil unless
            // genuinely in Exercise right now), so this is always fully authoritative (assign/clear,
            // mirrors lockoutUntilEpochSec's unconditional guard), never "ignore if invalid, keep
            // last" — a stale timer must never survive past the moment the pump's own mode changed.
            // Persisted (mirrors lockoutUntilEpochSec's own persistence) so a restart between syncs
            // still shows the last-known countdown rather than nothing.
            var etrs = numRange(data["exerciseTimeRemainingSec"], 0, 24 * 60 * 60);
            if (etrs != null && etrs > 0) {
                exerciseTimeRemainingSec = etrs;
                Storage.setValue("exerciseTimeRemainingSec", exerciseTimeRemainingSec);
            } else {
                exerciseTimeRemainingSec = null;
                Storage.deleteValue("exerciseTimeRemainingSec");
            }
            // Fail-closed: UNLIKE controllerVariant/controlIQEnabled
            // above (where absent only ever means "legacy host" and the last-known value stays safe to
            // keep), `ciqZone` can legitimately clear on a MODERN host too — CIQ turns off, or the raw
            // zone becomes unmapped — and a Monkey C dictionary can't distinguish "key never sent" from
            // "key sent null" once decoded. So this field is always fully authoritative on every
            // statusRead (assign/clear, never "ignore if invalid, keep last"): a stale zone word must
            // never survive past the moment it actually cleared. Persisted (mirrors garminBolusEnabled,
            // not the not-persisted controllerVariant above) so it survives a restart between syncs.
            var cz = data["ciqZone"];
            if (cz instanceof Lang.String && containsStr(CIQ_ZONES, cz as Lang.String)) {
                ciqZone = cz;
                Storage.setValue("ciqZone", ciqZone);
            } else {
                ciqZone = null;
                Storage.deleteValue("ciqZone");
            }
            // Fail-closed: mirrors ciqZone's unconditional
            // assign-or-clear exactly — `ciqSuspendedForLow` can legitimately clear on a MODERN host too
            // (the suspend ends, or its cause is no longer CIQ-attributed), so a stale `true` must never
            // survive past the moment it actually cleared. Persisted (mirrors ciqZone/garminBolusEnabled)
            // so it survives a restart between syncs.
            var csfl = data["ciqSuspendedForLow"];
            if (csfl instanceof Lang.Boolean) {
                ciqSuspendedForLow = csfl;
                Storage.setValue("ciqSuspendedForLow", ciqSuspendedForLow);
            } else {
                ciqSuspendedForLow = null;
                Storage.deleteValue("ciqSuspendedForLow");
            }
            var csse = data["ciqSuspendStartEpochSec"];
            if (csse instanceof Lang.Number && csse > 0) {
                ciqSuspendStartEpochSec = csse;
                Storage.setValue("ciqSuspendStartEpochSec", ciqSuspendStartEpochSec);
            } else {
                ciqSuspendStartEpochSec = null;
                Storage.deleteValue("ciqSuspendStartEpochSec");
            }
            // UNLIKE ciqZone/ciqSuspendedForLow
            // above, these are monotonic historical markers — a real occurrence never un-happens, so
            // a missing/invalid key means only "this reply didn't repeat it", never "it un-happened".
            // Keep the last-known value (no else-clear branch) — never overwritten with null.
            var lac = data["lastAutoCorrectionEpochSec"];
            if (lac instanceof Lang.Number && lac > 0) {
                lastAutoCorrectionEpochSec = lac;
                Storage.setValue("lastAutoCorrectionEpochSec", lastAutoCorrectionEpochSec);
            }
            var cncd = data["ciqLastCouldNotDeliverEpochSec"];
            if (cncd instanceof Lang.Number && cncd > 0) {
                ciqLastCouldNotDeliverEpochSec = cncd;
                Storage.setValue("ciqLastCouldNotDeliverEpochSec", ciqLastCouldNotDeliverEpochSec);
            }
            // Fail-closed: UNLIKE lastAutoCorrectionEpochSec/
            // ciqLastCouldNotDeliverEpochSec just above, this is a DERIVED instant the phone
            // recomputes fresh every statusRead — so it is always fully authoritative (assign/clear,
            // mirrors ciqZone's unconditional guard), never "ignore if invalid, keep last".
            var lue = data["lockoutUntilEpochSec"];
            if (lue instanceof Lang.Number && lue > 0) {
                lockoutUntilEpochSec = lue;
                Storage.setValue("lockoutUntilEpochSec", lockoutUntilEpochSec);
            } else {
                lockoutUntilEpochSec = null;
                Storage.deleteValue("lockoutUntilEpochSec");
            }
            // Fail-closed: mirrors lockoutUntilEpochSec's unconditional
            // assign-or-clear exactly — the phone relays its CURRENT knowledge every statusRead (`<= 0`
            // means unread on the wire, same convention as PumpSnapshot.maxBasalUnitsPerHour==0), so a
            // stale max must never survive past the moment it actually cleared.
            var mbu = fltRange(data["maxBasalUnitsPerHour"], 0.01, 25.0);
            if (mbu != null) {
                maxBasalUnitsPerHour = mbu;
                Storage.setValue("maxBasalUnitsPerHour", maxBasalUnitsPerHour);
            } else {
                maxBasalUnitsPerHour = null;
                Storage.deleteValue("maxBasalUnitsPerHour");
            }
            var bm = data["bolusMode"] as Lang.String?;
            if (bm != null && (bm.equals("units") || bm.equals("carbs"))) { defaultMode = bm; }
            var bi = fltRange(data["bolusIncrement"], 0.01, 5.0); if (bi != null) { stepU = bi; }
            var ci = numRange(data["carbIncrement"], 1, 100); if (ci != null) { stepC = ci; }
            // Change-detected — screenOrder/defaultScreen/detailsOrder/
            // watchChartRanges are sent on every reply the phone has them configured, so writing
            // unconditionally re-wrote the same flash cell on every poll even when the layout never
            // changed. Lang.Array has no built-in structural equality (sameArray() above); scalars use
            // the same `!=`/`.equals()` idiom as the Boolean settings above.
            var so = data["screenOrder"];
            if (so instanceof Lang.Array) {
                var sanSo = sanitizeOrder(so);
                if (!sameArray(screenOrder, sanSo)) { Storage.setValue("screenOrder", sanSo); }
                screenOrder = sanSo;
            }
            var ds = data["defaultScreen"] as Lang.String?;
            if (ds != null && contains(screenOrder, ds)) {
                if (!defaultScreen.equals(ds)) { Storage.setValue("defaultScreen", ds); }
                defaultScreen = ds;
            }
            ensureValidDefault();
            var detOrderRaw = data["detailsOrder"];
            if (detOrderRaw instanceof Lang.Array) {
                var detOrderSan = sanitizeAgainst(detOrderRaw, ALL_DETAILS);
                if (detOrderSan.size() > 0) {
                    if (!sameArray(detailsOrder, detOrderSan)) { Storage.setValue("detailsOrder", detOrderSan); }
                    detailsOrder = detOrderSan;
                }
            }
            // Which pump-status fields fill the three complication slots, mirroring the
            // detailsOrder array-setting idiom (sanitize against the allowed tokens, de-dupe, cap 3;
            // change-detected persist). An empty result (all-garbage) is ignored so the safe default stands.
            var slotsRaw = data["garminComplicationSlots"];
            if (slotsRaw instanceof Lang.Array) {
                var slotsSan = sanitizeComplicationSlots(slotsRaw);
                if (slotsSan.size() > 0) {
                    if (!sameArray(garminComplicationSlots, slotsSan)) { Storage.setValue("garminComplicationSlots", slotsSan); }
                    garminComplicationSlots = slotsSan;
                }
            }
            var chartRaw = data["watchChartRanges"];
            if (chartRaw instanceof Lang.Array) {
                var chartSan = sanitizeRanges(chartRaw);
                if (chartSan.size() > 0) {
                    if (!sameArray(chartRanges, chartSan)) { Storage.setValue("watchChartRanges", chartSan); }
                    chartRanges = chartSan;
                    ensureValidPlotHours();
                }
            }
            // Garmin is in the SMALL-SCREEN group — resolve the small-screen OVERRIDE first
            // (glucosePlotFloorSmall/CeilingSmall), falling back to the shared/phone-scoped bounds
            // (glucosePlotFloor/Ceiling) when no override is on the wire. A field absent on BOTH keeps
            // the last-persisted/default value (legacy-safe) — this is a SEPARATE channel from
            // watchChartRanges/chartRanges above, never derived from it. A resolved pair failing the
            // floor<ceiling invariant is dropped to the compile-time defaults rather than applied
            // (never a corrupt/inverted domain).
            var pf = numRange(data["glucosePlotFloorSmall"], 1, 1000);
            if (pf == null) { pf = numRange(data["glucosePlotFloor"], 1, 1000); }
            var pc = numRange(data["glucosePlotCeilingSmall"], 1, 1000);
            if (pc == null) { pc = numRange(data["glucosePlotCeiling"], 1, 1000); }
            // Change-detected — plotFloor/plotCeiling are recomputed and re-sent on
            // every reply even when the resolved bounds are identical to last time.
            if (pf != null && pc != null) {
                var priorPlotFloor = plotFloor;
                var priorPlotCeiling = plotCeiling;
                if (pf < pc) {
                    plotFloor = pf;
                    plotCeiling = pc;
                } else {
                    plotFloor = 40;
                    plotCeiling = 300;
                }
                if (priorPlotFloor != plotFloor) { Storage.setValue("plotFloor", plotFloor); }
                if (priorPlotCeiling != plotCeiling) { Storage.setValue("plotCeiling", plotCeiling); }
            }
            // Change-detected, same reasoning as the settings keys above.
            var cdisp = data["garminComplicationDisplay"];
            if (cdisp instanceof Lang.String && ((cdisp as Lang.String).equals("numericColor") || (cdisp as Lang.String).equals("stringTrend"))) {
                if (!complicationDisplay.equals(cdisp)) { Storage.setValue("complicationDisplay", cdisp); }
                complicationDisplay = cdisp;
            }
            // The clock screen's analog-vs-digital choice is PHONE-DRIVEN, replacing the old
            // on-watch tap toggle. Persist under the SAME "clockAnalog" Storage key ClockView.analog()
            // reads, so a cold launch keeps the last phone-pushed value. Strict guard (mirrors
            // remotesReadOnly / garminBolusEnabled): a non-boolean is ignored, leaving the last persisted
            // value (or ClockView's digital default when never set) untouched.
            // Change-detected against the CURRENT persisted value (this field has
            // no in-memory AppState mirror — ClockView reads Storage directly — so the "before" value is
            // read back rather than compared against a field).
            var ca = data["clockAnalog"];
            if (ca instanceof Lang.Boolean) {
                var priorCa = Storage.getValue("clockAnalog");
                if (!(priorCa instanceof Lang.Boolean) || (priorCa as Lang.Boolean) != ca) {
                    Storage.setValue("clockAnalog", ca);
                }
            }
            // Display-unit token mirrored from the phone (RemoteCommand.
            // glucoseDisplayUnit, additive-optional). Strict guard (mirrors clockAnalog/
            // garminComplicationDisplay above): only a recognized "mgdl"|"mmol" token is adopted +
            // persisted; an absent/unrecognized token is ignored, keeping the last persisted value —
            // which fails closed to "mgdl" on a fresh install / older phone build that never sends it.
            // The canonical glucose/isf/targetBg Numbers are never touched here — only the
            // label this token selects. Change-detected, same reasoning as above.
            var gu = data["glucoseDisplayUnit"];
            if (gu instanceof Lang.String && isValidUnitToken(gu as Lang.String)) {
                if (!glucoseUnit.equals(gu)) { Storage.setValue("glucoseDisplayUnit", gu); }
                glucoseUnit = gu;
            }
            // After EVERY field above is parsed, recompute the bolus eligibility fingerprint. When
            // it changes from the last-seen one, bump the generation — any armed confirm whose snapshot
            // (armedEligibilityGen) predates the bump is now stale and is torn down / refused at send.
            // The first statusRead only establishes the baseline (_prevEligibilityFp == null ⇒ no bump).
            var fp = eligibilityFingerprint();
            if (_prevEligibilityFp != null && !fp.equals(_prevEligibilityFp)) { bolusEligibilityGen += 1; }
            _prevEligibilityFp = fp;
        } else if (kind.equals("bolusStatus")) {
            var rid = strCap(data["requestId"], 64);
            // Only adopt a recognized status token, and cap the message length.
            var st = data["status"];
            var incoming = (st instanceof Lang.String && containsStr(STATUS_TOKENS, st as Lang.String)) ? st as Lang.String : null;
            // Clear the durable tombstone on an AUTHORITATIVELY RESOLVED echo for
            // its requestId, independent of pendingRequestId/status — onBack's clearInFlight() may have
            // already wiped those locally WITHOUT touching the tombstone (see its own comment), so
            // gating the clear on pendingRequestId (which a back-out nulls) would leave a tombstone
            // stuck forever once a matching late echo can no longer be recognized. A non-terminal echo
            // (delivering/cancelling) must NOT clear it — the outcome is still unknown.
            // Nor must an "unknown" echo (indeterminate) — that is the ambiguous-outcome
            // case this tombstone exists to protect, so this gate deliberately uses
            // isAuthoritativelyResolved(), NOT isTerminalStatus() (which treats "unknown" as terminal for
            // an unrelated purpose below).
            if (unresolvedTombstoneReqId != null && rid != null && rid.equals(unresolvedTombstoneReqId)
                    && isAuthoritativelyResolved(incoming)) {
                clearUnresolvedTombstone();
            }
            if (pendingRequestId != null && rid != null && rid.equals(pendingRequestId)) {
                // Never regress an authoritative TERMINAL outcome (delivered/cancelled/failed/unknown)
                // to a late duplicate NON-terminal token (delivering/cancelling) that arrives with the SAME
                // requestId — a delayed/retransmitted echo must not overwrite the real result. A later
                // TERMINAL may still replace a terminal (e.g. delivered → cancelled-partial). Mirrors
                // noteBolusSendFailed's "never regress a terminal" guard.
                var regresses = incoming != null && isTerminalStatus(status) && !isTerminalStatus(incoming);
                if (!regresses) {
                    if (incoming != null) { status = incoming; }
                    message = data.hasKey("message") ? strCap(data["message"], 160) : null;
                    // Reflect the actual delivered amount from the outcome echo so "Last bolus" shows the
                    // just-delivered value immediately (e.g. 0.05), not the previous bolus.
                    if (status != null && (status.equals("delivered") || status.equals("cancelled"))) {
                        var du = fltRange(data["deliveredUnits"], 0.0, 100.0); if (du != null) { lastBolus = du; }
                    }
                }
            }
        } else if (kind.equals("dismissAck")) {
            // The SOLE authenticated remover of a wearer-initiated Garmin dismiss.
            // handleDismissAck is guarded (malformed/mismatched/expired ⇒ safe no-op).
            handleDismissAck(strCap(data["requestId"], 64), data["alertId"], data["alertKind"]);
        } else if (kind.equals("bolusLockResolved")) {
            // The phone reporting that a HUMAN reconciled a specific unresolved dispatch against the
            // pump's own history, releasing the watch's LOCK only (see resolveUnresolvedSendLock —
            // it asserts nothing about whether insulin was delivered). requestId-matched, so this can
            // never blanket-unlock; a missing/malformed/mismatched id is a safe no-op. Note this is
            // strictly weaker than the bolusStatus path above: an authoritatively-resolved echo resolves
            // the DOSE, and remains the preferred resolution whenever the phone actually knows.
            var lrid = strCap(data["requestId"], 64);
            if (lrid != null) { resolveUnresolvedSendLock(lrid as Lang.String); }
        }
    }
    (:background)
    const STATUS_TOKENS = ["delivering", "delivered", "cancelled", "cancelling", "failed", "unknown"];

    (:background)
    function isNum(v) as Lang.Boolean {
        return v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double;
    }
    function numOrNull(v) as Lang.Number? { return isNum(v) ? v.toNumber() : null; }
    function flt(v) as Lang.Float? { return isNum(v) ? v.toFloat() : null; }

    // Inbound-payload validation. A malformed / hostile phone message must not poison global
    // state — every physiological field is bounds- and finiteness-checked, strings are length-capped,
    // and nested arrays are size-capped with per-element validation. A rejected field returns null so
    // the caller KEEPS the last good value rather than adopting garbage.
    (:background)
    function isFiniteNum(v) as Lang.Boolean {
        if (!isNum(v)) { return false; }
        return v == v && v < 1.0e12 && v > -1.0e12;   // v==v rejects NaN; the bounds reject ±Inf / absurd
    }
    (:background)
    function numRange(v, lo as Lang.Number, hi as Lang.Number) as Lang.Number? {
        if (!isFiniteNum(v)) { return null; }
        var n = v.toNumber();
        return (n < lo || n > hi) ? null : n;
    }
    (:background)
    function fltRange(v, lo as Lang.Float, hi as Lang.Float) as Lang.Float? {
        if (!isFiniteNum(v)) { return null; }
        var f = v.toFloat();
        return (f < lo || f > hi) ? null : f;
    }
    (:background)
    function strCap(v, max as Lang.Number) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        var s = v as Lang.String;
        return (s.length() > max) ? s.substring(0, max) : s;
    }
    // Shallow element-wise equality for the settings-key change-detection below
    // (screenOrder/detailsOrder/watchChartRanges are Arrays of Strings/Numbers). Lang.Array has no
    // built-in structural equals() (it inherits Object's reference equality), so a change-detect guard
    // needs its own compare; `==` is the same value-equality idiom this file already uses for boxed
    // String/Number dictionary values (e.g. the dismissIdentity lookup's `a["id"] == id`).
    (:background)
    function sameArray(a as Lang.Array, b as Lang.Array) as Lang.Boolean {
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }
    (:background)
    const TREND_TOKENS = ["flat", "up", "down", "upup", "downdown", "up45", "down45", ""];
    (:background)
    function validTrend(v) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        return containsStr(TREND_TOKENS, v as Lang.String) ? v : null;
    }
    // Keep the newest ≤288 finite readings in [0,600]; drop everything else.
    (:background)
    function sanitizeHistory(arr as Lang.Array) as Lang.Array {
        var out = [];
        var n = arr.size();
        var start = (n > 288) ? n - 288 : 0;
        for (var k = start; k < n; k += 1) {
            var v = numRange(arr[k], 0, 600);
            if (v != null) { out.add(v); }
        }
        return out;
    }
    // Keep the newest ≤288 (mg/dL, epoch) PAIRS where BOTH the reading is finite in [0,600] AND
    // the epoch is a finite Number > 0. Sanitizing as PAIRS (never independently) is the whole point:
    // an out-of-range reading drops its epoch too, so a surviving reading can never shift onto the
    // wrong timestamp. Callers pass equal-length raw arrays. Returns [historyOut, epochsOut], always
    // of equal size (the aligned-pair invariant). Reuses numRange/isFiniteNum.
    (:background)
    function sanitizeHistoryPairs(hs as Lang.Array, es as Lang.Array) as Lang.Array {
        var histOut = [];
        var epOut = [];
        var n = hs.size();
        var start = (n > 288) ? n - 288 : 0;
        for (var k = start; k < n; k += 1) {
            var v = numRange(hs[k], 0, 600);
            if (v != null && isFiniteNum(es[k])) {
                var e = es[k].toNumber();
                if (e > 0) { histOut.add(v); epOut.add(e); }
            }
        }
        return [histOut, epOut];
    }
    // Keep ≤50 well-formed alert dicts (each must have id/kind/title of the right type).
    // ADDITIVELY preserve an optional per-alert `severity` tier string (a valid tier token
    // only; absent/malformed stays absent) so the gate (alertSeverityTier/alertActionFor) has a
    // reliable per-alert salience signal. Backward-compatible — a legacy phone omits it and the gate then
    // fails closed to highest salience (unknown ⇒ critical). Never a dose input.
    (:background)
    function sanitizeAlerts(arr as Lang.Array) as Lang.Array {
        var out = [];
        var lim = (arr.size() > 50) ? 50 : arr.size();
        for (var k = 0; k < lim; k += 1) {
            var e = arr[k];
            if (e instanceof Lang.Dictionary
                && isNum(e["id"]) && isNum(e["kind"]) && (e["title"] instanceof Lang.String)) {
                var o = { "id" => e["id"], "kind" => e["kind"], "title" => strCap(e["title"], 80) };
                var sev = e["severity"];
                if (sev instanceof Lang.String && isValidSeverityTier(sev as Lang.String)) { o["severity"] = sev; }
                out.add(o);
            }
        }
        return out;
    }

    // A conservative safety margin well under Toybox.Background.exit's documented ~8 KB
    // ExitDataSizeLimitException threshold — absorbs the unknown per-entry background-data
    // serialization overhead (the SDK does not document its on-wire encoding), leaving headroom for
    // future exit-data growth alongside the alerts list.
    (:background)
    const SAFE_EXIT_BUDGET_BYTES = 6000;

    // A conservative OVERESTIMATE of one {id,kind,title} alert dict's Background.exit serialized
    // size — the numeric id/kind (small ints) plus the title string (generously assumed up to 2
    // bytes/char for non-ASCII) plus dict/key-name framing overhead (~40 bytes for the three key
    // names). Deliberately pessimistic since the SDK never documents its background-data encoding.
    (:background)
    function estimatedAlertExitBytes(a as Lang.Dictionary) as Lang.Number {
        var title = a["title"];
        var titleLen = (title instanceof Lang.String) ? title.length() : 0;
        return 60 + (titleLen * 2);
    }

    // The byte-budget-safe subset of `arr` (an alerts array) to forward across
    // Background.exit's documented ~8 KB ExitDataSizeLimitException boundary. PURE — never mutates
    // `arr` — and preserves the caller's existing most-serious-first ordering (the phone already sends
    // `alerts` in that order; sanitizeAlerts/notifyNewAlerts rely on it), so the kept subset is always
    // an unbroken PREFIX, never a reshuffled/sampled one. A small (already-within-budget) array is
    // returned unchanged.
    (:background)
    function alertsForBackgroundExit(arr as Lang.Array) as Lang.Array {
        var out = [];
        var used = 0;
        for (var i = 0; i < arr.size(); i += 1) {
            var a = arr[i];
            var cost = estimatedAlertExitBytes(a as Lang.Dictionary);
            if (used + cost > SAFE_EXIT_BUDGET_BYTES) { break; }
            out.add(a);
            used += cost;
        }
        return out;
    }

    // Alert identity = kind + "-" + id. This is the (kind, id) pair the dismiss path already keys on
    // (see AlertConfirmDelegate / RemoteComm.dismissAlert) — NOT a new schema field. It's the stable
    // handle the notifier uses to tell a genuinely NEW alert from a re-fetch of one already surfaced.
    (:background)
    function alertIdentity(a as Lang.Dictionary) as Lang.String {
        return a["kind"].toString() + "-" + a["id"].toString();
    }

    // The pure, phone-synced watch alert gate.
    // Frozen severity-tier token set (least→most salient). The phone classifies each alert's
    // typed kind into one of these and puts it on the wire as the per-alert `severity`; the watch never
    // invents its own severity. Kept small + frozen (never a raw enum on the wire).
    (:background)
    const ALERT_TIERS = ["info", "high", "critical"];
    (:background)
    const ALERT_MODES = ["silent", "vibrate", "audible"];

    (:background)
    function isValidSeverityTier(t as Lang.String) as Lang.Boolean {
        return containsStr(ALERT_TIERS, t);
    }

    // Rank a tier: info=0, high=1, critical=2. Unknown ⇒ critical's rank (highest salience, never
    // suppressed) — a fail-closed CLASSIFICATION only (see the note on alertActionFor: this rule
    // NEVER resurrects output against an explicit Silent+override-off user choice).
    (:background)
    function severityRank(t as Lang.String) as Lang.Number {
        if (t.equals("info")) { return 0; }
        if (t.equals("high")) { return 1; }
        return 2;   // "critical" or anything unknown ⇒ highest salience
    }

    // Read an alert's per-alert `severity` tier. A valid tier token is honored; an absent/malformed one
    // fails closed to "critical" (highest salience) so a legacy phone (no severity) or a garbage value can
    // never SUPPRESS a genuinely critical alert. Pure + Attention/DeviceSettings-free (unit-testable).
    (:background)
    function alertSeverityTier(a as Lang.Dictionary) as Lang.String {
        var s = a["severity"];
        if (s instanceof Lang.String && isValidSeverityTier(s as Lang.String)) { return s; }
        return "critical";
    }

    // The most-severe tier across a batch of alerts (fail toward higher salience — if ANY new alert is
    // critical the single batch vibrate/tone uses the critical treatment). Empty ⇒ "info" (never reached
    // with output, since notifyNewAlerts only gates when the batch is non-empty).
    (:background)
    function mostSevereTier(list as Lang.Array) as Lang.String {
        var best = "info";
        var bestRank = -1;
        for (var i = 0; i < list.size(); i += 1) {
            var t = alertSeverityTier(list[i] as Lang.Dictionary);
            var r = severityRank(t);
            if (r > bestRank) { bestRank = r; best = t; }
        }
        return best;
    }

    // The per-tier haptic signature as PURE data ([[dutyCyclePct, durationMs], ...]) — distinct per
    // tier so the wearer can tell a critical from an info by feel: critical ⇒ triple-long, high ⇒ double,
    // info ⇒ single-short. The caller (FaBolusApp) turns these into Attention.VibeProfile objects (the
    // only Attention touch), so this stays unit-testable. Unknown key ⇒ the critical (most-salient) pattern.
    (:background)
    function vibePatternFor(key as Lang.String) as Lang.Array {
        if (key.equals("info")) { return [[50, 200]]; }
        if (key.equals("high")) { return [[75, 300], [75, 300]]; }
        return [[100, 400], [100, 400], [100, 400]];   // "critical" / unknown ⇒ triple-long
    }

    // THE GATE (pure — no Attention, no DeviceSettings): resolve the {vibrate, vibeProfileKey, tone,
    // backlight} decision from the already-classified severity tier, the phone-synced intensity mode +
    // audible floor + critical-override opt-in, and the device's vibrateOn / doNotDisturb state.
    //
    // SAFETY INVARIANTS encoded here:
    //  • DEFAULT (mode "vibrate", override off) ⇒ vibration-only for EVERY tier; nothing audible, nothing
    //    pierces DND unless opted in.
    //  • FULLY-SILENT GUARANTEE: mode "silent" + criticalOverridesDnd=false ⇒ ZERO output (no vibrate, no
    //    tone, no backlight) for EVERY tier INCLUDING critical (and including an unknown-severity alert,
    //    which alertSeverityTier already resolved to "critical"). There is NO code path that forces output
    //    in this combination — the phone is the sole authoritative alerting surface.
    //  • Silent + override ON ⇒ opt-in wrist fallback: a CRITICAL-tier alert gets a vibrate (NEVER a tone);
    //    a non-critical tier stays silent.
    //  • The explicit user Silent(+override-off) choice ALWAYS wins: the unknown⇒critical fail-closed rule
    //    is a CLASSIFICATION applied before this gate; it does not resurrect output inside Silent.
    //  • Non-silent (vibrate/audible): routine (non-critical) honors vibrateOn/doNotDisturb; the critical
    //    tier pierces DND ONLY when criticalOverridesDnd is on. Audible tone+backlight fire only for a tier
    //    at/above the audible floor that also passes the DND gate.
    (:background)
    function alertActionFor(tier as Lang.String, mode as Lang.String, audibleMinSeverity as Lang.String,
                            criticalOverridesDnd as Lang.Boolean, vibrateOn as Lang.Boolean,
                            doNotDisturb as Lang.Boolean) as Lang.Dictionary {
        var isCritical = tier.equals("critical");
        // Silent mode: the phone owns alerting entirely — the ONLY watch output is the opt-in critical
        // wrist-vibration fallback (never a tone), and only when the user turned the override on.
        if (mode.equals("silent")) {
            if (criticalOverridesDnd && isCritical) {
                return { "vibrate" => true, "vibeProfileKey" => tier, "tone" => false, "backlight" => false };
            }
            return { "vibrate" => false, "vibeProfileKey" => tier, "tone" => false, "backlight" => false };
        }
        // Non-silent (vibrate / audible): DND / vibrateOn is HONORED for routine alerts; the critical tier
        // pierces it only on the opt-in.
        var dndBlocks = doNotDisturb || !vibrateOn;
        var vibrate;
        if (isCritical) {
            vibrate = dndBlocks ? criticalOverridesDnd : true;
        } else {
            vibrate = !dndBlocks;
        }
        // Audible tone+backlight only when the user chose "audible", the tier is at/above the audible floor,
        // AND the DND gate permitted output (a routine alert under DND, or a critical alert not opted to
        // pierce, stays quiet).
        var audible = mode.equals("audible")
                      && vibrate
                      && (severityRank(tier) >= severityRank(audibleMinSeverity));
        return { "vibrate" => vibrate, "vibeProfileKey" => tier, "tone" => audible, "backlight" => audible };
    }

    // May a CLOSED-app background alert surface a system
    // notification (BgServiceDelegate.surfaceNewAlertsInBackground)? The foreground gate (alertActionFor)
    // only governs the app's own vibrate/tone; the background Toybox.Notifications path is separate and
    // used to fire regardless of the setting — so a closed-app critical could still post (and buzz per the
    // OS) in Silent mode, contradicting the "phone is the sole authoritative alerting surface" choice.
    // This extends the Silent guarantee to the background: Silent + override-off ⇒ surface NOTHING (the
    // phone alerts); Silent + override-on ⇒ surface ONLY the critical tier (the opt-in wrist fallback);
    // "vibrate"/"audible" ⇒ always surface (the closed-app safety net is intact). Unknown severity
    // is already classified to "critical" by alertSeverityTier, so it surfaces exactly where critical does.
    (:background)
    function shouldSurfaceInBackground(tier as Lang.String, mode as Lang.String,
                                       criticalOverridesDnd as Lang.Boolean) as Lang.Boolean {
        if (mode.equals("silent")) {
            return criticalOverridesDnd && tier.equals("critical");
        }
        return true;
    }

    // The raw-snapshot proof-of-absence oracle's OWN identity parser. Deliberately NOT
    // sanitizeAlerts (which DROPS any item whose `title` is not a Lang.String) — a raw item with a valid
    // (id,kind) but a malformed/absent title must still count as PRESENT (title-agnostic), or a bad
    // title on the wire would falsely remove a still-pump-active wearer dismiss. Only a missing/non-
    // numeric id OR kind skips an item (never traps).
    (:background)
    function rawAlertIdentities(arr as Lang.Array) as Lang.Array {
        var out = [];
        var lim = (arr.size() > 50) ? 50 : arr.size();
        for (var k = 0; k < lim; k += 1) {
            var e = arr[k];
            if (e instanceof Lang.Dictionary && isNum(e["id"]) && isNum(e["kind"])) {
                var ident = e["kind"].toString() + "-" + e["id"].toString();
                if (!containsStr(out, ident)) { out.add(ident); }
            }
        }
        return out;
    }

    // Pure: drop exactly the (id, kind) alert from the active list, leaving every other alert
    // (and their order) untouched. NO LONGER called on a DISPATCHED dismiss (see the two-lane dismiss
    // state below) — kept for any future authenticated-ack path that would need a real local removal.
    // Extracted verbatim from the old inline loop in AlertConfirmDelegate so it's unit-testable.
    (:background)
    function removeAlert(id, kind) as Void {
        var kept = [];
        for (var i = 0; i < alerts.size(); i += 1) {
            var a = alerts[i] as Lang.Dictionary;
            if (!(a["id"] == id && a["kind"] == kind)) { kept.add(a); }
        }
        alerts = kept;
    }

    // The statusRead-reconcile lane: identities
    // whose dismiss was DISPATCHED to the phone (RemoteComm.send returned true) but not yet PROVEN
    // absent by an authoritative statusRead reply. There is no correlated dismiss-ack path today (no
    // retained request id, no ack state machine in handle()), so AlertConfirmDelegate.onResponse no
    // longer removes the alert on a bare dispatch — it only flags it here. The alert stays visible/
    // active until reconcileDismissSent() (called from handle() the moment a fresh `alerts` list
    // replaces the old one) drops it because the phone's own authoritative list no longer contains it.
    // In-memory only (mirrors the existing transient alertDismissFailedOffline flag) — a cold relaunch
    // simply re-derives "not yet proven" from the next statusRead, which is always coming.
    (:background)
    var dismissSentAlertIdentities as Lang.Array = [];

    // Mark (id, kind) as a dispatched-but-unproven dismiss. Idempotent (re-dispatching the same alert
    // doesn't duplicate the identity).
    function markDismissSent(id, kind) as Void {
        var ident = kind.toString() + "-" + id.toString();
        if (!containsStr(dismissSentAlertIdentities, ident)) {
            dismissSentAlertIdentities.add(ident);
        }
    }

    // Whether (id, kind)'s dismiss is still an unproven, provisional "dismiss sent" — i.e. dispatched
    // but not yet reconciled away by an authoritative statusRead.
    function isDismissSent(id, kind) as Lang.Boolean {
        return containsStr(dismissSentAlertIdentities, kind.toString() + "-" + id.toString());
    }

    // The ONLY thing that actually drops a provisional dismiss-sent identity: called right after a
    // fresh, authoritative `alerts` list replaces the old one (handle()). An identity no longer present
    // in the new active list has been proven absent by the phone — drop it. An identity still present
    // (the phone hasn't cleared it yet, or rejected the dismiss) stays flagged; re-dispatching it is
    // still safe/idempotent via markDismissSent.
    (:background)
    function reconcileDismissSent() as Void {
        var active = activeAlertIdentities();
        var kept = [];
        for (var i = 0; i < dismissSentAlertIdentities.size(); i += 1) {
            var ident = dismissSentAlertIdentities[i];
            if (containsStr(active, ident)) { kept.add(ident); }
        }
        dismissSentAlertIdentities = kept;
    }

    // ========================================================================================
    // Authenticated dismiss-ack: TWO-LANE durable state.
    //
    // Mirrors the phone's `GarminDismissReceiptStore` lifecycle exactly (see that type's own doc
    // comment): Lane 1 (RETRY/PENDING, {requestId, generation, createdAt}, per identity) has a named
    // TTL WELL under the pump's 30-min re-nag — MAY expire/prune, capped; pruning removes NO alert.
    // Lane 2 (DISPLAY provisional, {id, kind, title}, per identity) is retained until an
    // authenticated dismissAck removes it — NEVER TTL-pruned, NEVER evicted on cap overflow (eviction =
    // fail-open). Both persisted (Application.Storage) so they survive a relaunch; overlaid
    // onto the statusRead alerts replace in handle() when `supportsDismissAck` is true.
    (:background)
    const KEY_DISMISS_PENDING = "dismissPending";           // identity -> {requestId, generation, createdAt}
    (:background)
    const KEY_DISMISS_PROVISIONAL = "dismissProvisional";   // identity -> {id, kind, title}
    (:background)
    const KEY_SUPPORTS_DISMISS_ACK = "supportsDismissAck";
    // Mirrors KEY_SUPPORTS_DISMISS_ACK exactly, for the raw-snapshot backstop's capability.
    (:background)
    const KEY_SUPPORTS_RAW_ALERT_SNAPSHOT = "supportsRawAlertSnapshot";
    // 10 minutes — WELL under the pump's 30-min re-nag (snoozeWindow, TandemBackend.swift) and matching
    // the phone's own GarminDismissReceiptStore.ttl, so the two ends stop correlating together.
    (:background)
    const DISMISS_RETRY_TTL_SEC = 600;
    // Bounded RETRY lane only (oldest pruned on overflow) — the DISPLAY lane is never capped.
    const DISMISS_RETRY_CAP = 8;

    (:background)
    var dismissPending as Lang.Dictionary = {};
    (:background)
    var dismissProvisional as Lang.Dictionary = {};

    (:background)
    function dismissIdentity(id, kind) as Lang.String {
        return kind.toString() + "-" + id.toString();
    }

    // Look up an active alert's title by identity, for the DISPLAY provisional snapshot —
    // AlertConfirmDelegate only holds `_id`/`_kind`, never the title.
    function alertTitleFor(id, kind) as Lang.String {
        for (var i = 0; i < alerts.size(); i += 1) {
            var a = alerts[i] as Lang.Dictionary;
            if (a["id"] == id && a["kind"] == kind) {
                var t = a["title"];
                return (t instanceof Lang.String) ? t : "";
            }
        }
        return "";
    }

    // AlertConfirmDelegate.onResponse calls this ONCE per wearer confirm: mints a NEW requestId +
    // generation — a genuinely NEW occurrence always REPLACES any prior retry entry for the SAME
    // identity (per-identity: at most one retry entry + one provisional) — persists BOTH lanes, and
    // returns the requestId to send. A lost-ack RETRY (the bounded-retry mechanism below) reuses the
    // SAME requestId+generation instead of calling this again.
    function beginDismiss(id, kind, title as Lang.String) as Lang.String {
        var ident = dismissIdentity(id, kind);
        var prior = dismissPending[ident];
        var generation = (prior instanceof Lang.Dictionary && prior["generation"] instanceof Lang.Number)
            ? (prior["generation"] as Lang.Number) + 1 : 1;
        // ROUTINE mint (a wearer dismiss-confirm) — see RemoteComm.newRoutineRequestId().
        var reqId = RemoteComm.newRoutineRequestId();
        dismissPending[ident] = { "requestId" => reqId, "generation" => generation, "createdAt" => Time.now().value() };
        capDismissPending();
        dismissProvisional[ident] = { "id" => id, "kind" => kind, "title" => title };
        saveDismissPending();
        saveDismissProvisional();
        return reqId;
    }

    // Bounded cap on the RETRY lane ONLY (oldest createdAt pruned) — the DISPLAY lane
    // (dismissProvisional) is NEVER capped/evicted (eviction of a wearer-dismissed
    // provisional would be fail-open).
    function capDismissPending() as Void {
        var keys = dismissPending.keys();
        if (keys.size() <= DISMISS_RETRY_CAP) { return; }
        var oldestKey = null;
        var oldestCreated = null;
        for (var i = 0; i < keys.size(); i += 1) {
            var k = keys[i];
            var e = dismissPending[k] as Lang.Dictionary;
            var created = e["createdAt"];
            if (created instanceof Lang.Number && (oldestCreated == null || created < oldestCreated)) {
                oldestCreated = created;
                oldestKey = k;
            }
        }
        if (oldestKey != null) { dismissPending.remove(oldestKey); }
    }

    (:background)
    function saveDismissPending() as Void { Storage.setValue(KEY_DISMISS_PENDING, dismissPending); }
    (:background)
    function saveDismissProvisional() as Void { Storage.setValue(KEY_DISMISS_PROVISIONAL, dismissProvisional); }

    // Restore both lanes + the persisted capability on loadPrefs/restart. Strict shape validation
    // (never trap): a malformed entry is DROPPED rather than adopted (mirrors the tombstone restore's
    // strCap-guarded discipline just above).
    (:background)
    function loadDismissState() as Void {
        var pendRaw = Storage.getValue(KEY_DISMISS_PENDING);
        if (pendRaw instanceof Lang.Dictionary) {
            var pend = pendRaw as Lang.Dictionary;
            var outP = {};
            var pkeys = pend.keys();
            for (var i = 0; i < pkeys.size(); i += 1) {
                var k = pkeys[i];
                var e = pend[k];
                if (e instanceof Lang.Dictionary && (e["requestId"] instanceof Lang.String)
                        && (e["generation"] instanceof Lang.Number) && (e["createdAt"] instanceof Lang.Number)) {
                    outP[k] = e;
                }
            }
            dismissPending = outP;
        }
        var provRaw = Storage.getValue(KEY_DISMISS_PROVISIONAL);
        if (provRaw instanceof Lang.Dictionary) {
            var prov = provRaw as Lang.Dictionary;
            var outV = {};
            var vkeys = prov.keys();
            for (var i = 0; i < vkeys.size(); i += 1) {
                var k = vkeys[i];
                var e = prov[k];
                if (e instanceof Lang.Dictionary && isNum(e["id"]) && isNum(e["kind"]) && (e["title"] instanceof Lang.String)) {
                    outV[k] = e;
                }
            }
            dismissProvisional = outV;
        }
        var sda = Storage.getValue(KEY_SUPPORTS_DISMISS_ACK);
        if (sda instanceof Lang.Boolean) { supportsDismissAck = sda; }
        // Mirrors the supportsDismissAck restore exactly, so a cold relaunch resumes on the
        // raw-snapshot tier (last-known) rather than defaulting false and falling through to the
        // statusRead-reconcile fallback on the first post-relaunch reply.
        var sra = Storage.getValue(KEY_SUPPORTS_RAW_ALERT_SNAPSHOT);
        if (sra instanceof Lang.Boolean) { supportsRawAlertSnapshot = sra; }
    }

    // Clock-rollback / future-timestamp discipline (mirrors the phone's GarminDismissReceiptStore
    // exactly): a future `createdAt` or a negative elapsed treats the RETRY entry as expired/invalid —
    // it stops accepting acks + retries. The DISPLAY provisional (a SEPARATE map) is never touched by
    // this check either way (expiry is never a remover).
    (:background)
    function dismissRetryExpired(entry as Lang.Dictionary, now as Lang.Number) as Lang.Boolean {
        var created = entry["createdAt"];
        if (!(created instanceof Lang.Number)) { return true; }
        var elapsed = now - (created as Lang.Number);
        return elapsed < 0 || elapsed >= DISMISS_RETRY_TTL_SEC;
    }

    // The bounded-retry surface (called from FaBolusApp's existing foreground poll tick): identities
    // with an unacked, UNEXPIRED retry entry — the caller re-dispatches RemoteComm.dismissAlert
    // REUSING the SAME requestId (never minting a new one; a retry is not a new occurrence). Expired
    // entries are lazily pruned here — this removes ONLY retry-lane bookkeeping, never an alert.
    function dueDismissRetries(now as Lang.Number) as Lang.Array {
        var out = [];
        var keys = dismissPending.keys();
        var toPrune = [];
        for (var i = 0; i < keys.size(); i += 1) {
            var k = keys[i];
            var e = dismissPending[k] as Lang.Dictionary;
            if (dismissRetryExpired(e, now)) {
                toPrune.add(k);
                continue;
            }
            var prov = dismissProvisional[k];
            if (prov instanceof Lang.Dictionary) {
                out.add({ "requestId" => e["requestId"], "id" => prov["id"], "kind" => prov["kind"] });
            }
        }
        if (toPrune.size() > 0) {
            for (var j = 0; j < toPrune.size(); j += 1) { dismissPending.remove(toPrune[j]); }
            saveDismissPending();
        }
        return out;
    }

    // The `dismissAck` handle() branch (guarded): removes the alert ONLY when the incoming
    // requestId matches the retained retry entry for the ack's (alertId, alertKind) identity AND that
    // entry is unexpired. A mismatched requestId, a mismatched identity (the ack's alertId/alertKind
    // simply won't resolve to the entry that owns the matching requestId), an expired entry, or a
    // malformed ack (missing/non-Number/non-String fields) all safely no-op — never a false removal.
    // On success calls the PRESERVED `removeAlert` and clears BOTH persisted lanes for that
    // identity (a later re-occurrence mints a fresh entry via beginDismiss).
    (:background)
    function handleDismissAck(rid, aid, akind) as Void {
        if (!(rid instanceof Lang.String) || !isNum(aid) || !isNum(akind)) { return; }
        var ident = dismissIdentity(aid, akind);
        var entry = dismissPending[ident];
        if (!(entry instanceof Lang.Dictionary)) { return; }
        var storedReqId = entry["requestId"];
        if (!(storedReqId instanceof Lang.String) || !(storedReqId as Lang.String).equals(rid)) { return; }
        if (dismissRetryExpired(entry, Time.now().value())) { return; }   // expiry is never a remover
        removeAlert(aid, akind);
        dismissPending.remove(ident);
        dismissProvisional.remove(ident);
        saveDismissPending();
        saveDismissProvisional();
    }

    // Re-add any retained-but-unacked DISPLAY provisional NOT present in the
    // just-replaced `alerts` snapshot, so a filtered statusRead can never silently drop a
    // wearer-dismissed-but-unacked alert — called from handle() ONLY when `supportsDismissAck` is true
    // (ack-mode; the capability-absent/false branch runs the `reconcileDismissSent()` fallback
    // instead and must NOT overlay, or a stale provisional would defeat that fallback's filtered-
    // absence removal). Force-marks each overlaid identity 'seen' (KEY_SEEN_ALERTS) so re-overlaying it
    // on every subsequent statusRead never re-triggers a notify/vibrate — the wearer already knows.
    (:background)
    function overlayUnackedDismissProvisionals() as Void {
        var active = activeAlertIdentities();
        var keys = dismissProvisional.keys();
        if (keys.size() == 0) { return; }
        var overlaidIdents = [];
        for (var i = 0; i < keys.size(); i += 1) {
            var ident = keys[i] as Lang.String;
            if (containsStr(active, ident)) { continue; }   // already present — nothing to overlay
            var prov = dismissProvisional[ident] as Lang.Dictionary;
            alerts.add({ "id" => prov["id"], "kind" => prov["kind"], "title" => prov["title"] });
            overlaidIdents.add(ident);
        }
        if (overlaidIdents.size() > 0) {
            var seen = loadSeenAlerts();
            for (var j = 0; j < overlaidIdents.size(); j += 1) {
                if (!containsStr(seen, overlaidIdents[j])) { seen.add(overlaidIdents[j]); }
            }
            saveSeenAlerts(seen);
        }
    }

    // The raw-snapshot tier's remover: for each wearer `dismissProvisional` identity ABSENT
    // from `rawIdents` (a PRESENT rawAlerts snapshot's parsed identity set — the caller only invokes this
    // when rawAlerts was present; an absent rawAlerts skips this call entirely, fail-closed), the pump has
    // proven the alert cleared — remove it from the display (the PRESERVED `removeAlert`) and clear ALL
    // of its bookkeeping across every dismiss-tracking lane (retry, provisional, and the dismiss-
    // sent lane too, so a later capability flip doesn't resurrect stale state for this identity). An
    // identity STILL present in rawIdents is left untouched here — `overlayUnackedDismissProvisionals()`
    // (always called right after this, by the caller) is what keeps it visible-but-quiet.
    (:background)
    function pruneProvisionalsAbsentFromRawSnapshot(rawIdents as Lang.Array) as Void {
        var keys = dismissProvisional.keys();
        if (keys.size() == 0) { return; }
        var changed = false;
        for (var i = 0; i < keys.size(); i += 1) {
            var ident = keys[i] as Lang.String;
            if (containsStr(rawIdents, ident)) { continue; }   // still pump-active — keep, don't touch
            var prov = dismissProvisional[ident] as Lang.Dictionary;
            removeAlert(prov["id"], prov["kind"]);
            dismissProvisional.remove(ident);
            dismissPending.remove(ident);
            if (containsStr(dismissSentAlertIdentities, ident)) {
                var kept = [];
                for (var j = 0; j < dismissSentAlertIdentities.size(); j += 1) {
                    if (!(dismissSentAlertIdentities[j] as Lang.String).equals(ident)) { kept.add(dismissSentAlertIdentities[j]); }
                }
                dismissSentAlertIdentities = kept;
            }
            changed = true;
        }
        if (changed) {
            saveDismissProvisional();
            saveDismissPending();
        }
    }

    // Count bound (the "50-vs-4 mismatch"): sanitizeAlerts stores up to 50 alerts, but
    // FaBolusApp.mc's own doc comment on notifyNewAlerts already claimed the actively-surfaced
    // (vibrate + pushed Confirmation) count was bounded by AlertsListView.MAX_ROWS == 4 — nothing in
    // code enforced that, so a burst of >4 simultaneously-new alerts could stack up to 50 Confirmation
    // views on the nav stack. This is the actual, enforced bound (kept as its own named constant, not a
    // reference to the View class, so this pure logic has no View-layer dependency).
    const MAX_ALERT_PUSHES = 4;

    // Pure: at most MAX_ALERT_PUSHES entries from `list`, preserving order (most-serious-first is the
    // caller's existing convention for the active-alerts / new-alerts lists). Anything beyond the bound
    // is left for the caller to pick up on its NEXT notify pass (never dropped outright).
    function capAlertPushes(list as Lang.Array) as Lang.Array {
        if (list.size() <= MAX_ALERT_PUSHES) { return list; }
        var out = [];
        for (var i = 0; i < MAX_ALERT_PUSHES; i += 1) { out.add(list[i]); }
        return out;
    }

    // Pure: the active alerts whose identity is NOT in `seen` — i.e. genuinely new since the last
    // notify — preserving the list's most-serious-first order (the phone sends `alerts` most-serious
    // first). FaBolusApp.notifyNewAlerts surfaces EACH of these (the old code surfaced only the first but
    // marked ALL seen, so a 2nd simultaneous new alert was suppressed forever). Bounded by sanitizeAlerts.
    (:background)
    function newAlertsSince(seen as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < alerts.size(); i += 1) {
            var a = alerts[i] as Lang.Dictionary;
            if (!containsStr(seen, alertIdentity(a))) { out.add(a); }
        }
        return out;
    }

    // Pure: every currently-active alert identity (most-serious-first order). notifyNewAlerts
    // rewrites the persisted seen-set to exactly this after surfacing — so a cleared alert drops out and
    // re-notifies if it re-fires, and newAlertsSince(activeAlertIdentities()) is empty (nothing left new).
    (:background)
    function activeAlertIdentities() as Lang.Array {
        var out = [];
        for (var i = 0; i < alerts.size(); i += 1) {
            out.add(alertIdentity(alerts[i] as Lang.Dictionary));
        }
        return out;
    }

    // The set of alert identities the wearer has already been notified about, persisted (as an Array of
    // identity strings) so it survives background↔foreground transitions and a cold launch — a NEW
    // alert is one whose identity isn't in this set. A plain count comparison missed an alarm that
    // replaced another at the same count and re-fired on every reshuffle; identity tracking fixes both.
    (:background)
    const KEY_SEEN_ALERTS = "seenAlerts";
    (:background)
    function loadSeenAlerts() as Lang.Array {
        var s = Storage.getValue(KEY_SEEN_ALERTS);
        return (s instanceof Lang.Array) ? s : [];
    }
    (:background)
    function saveSeenAlerts(seen as Lang.Array) as Void {
        Storage.setValue(KEY_SEEN_ALERTS, seen);
    }

    // Pure: the seen-set to persist after one notifyNewAlerts() batch. `presented` is exactly
    // the identities whose Ui.pushView actually ran this batch (see FaBolusApp.pushAlertConfirm's
    // explicit failure model) — NOT every active identity, and NOT every "new" identity (the old,
    // buggy `saveSeenAlerts(activeAlertIdentities())` did both, marking an alert seen even when its
    // Confirmation never reached the wearer, or when the push-count bound left it for a later batch).
    // Result = (previously-seen ∩ still-active) ∪ presented — restricted to ACTIVE identities so a
    // cleared/reconciled alert still drops out of the seen-set (preserving the "a cleared
    // alert re-notifies if it re-fires" rule), while never adding an identity that wasn't actually presented.
    function reconciledSeenAlerts(presented as Lang.Array) as Lang.Array {
        var active = activeAlertIdentities();
        var prevSeen = loadSeenAlerts();
        var out = [];
        for (var i = 0; i < active.size(); i += 1) {
            var ident = active[i];
            if (containsStr(prevSeen, ident) || containsStr(presented, ident)) { out.add(ident); }
        }
        return out;
    }

    // The set of alert identities already surfaced as a BACKGROUND system notification
    // (Toybox.Notifications.showNotification(), called from BgServiceDelegate).
    // Tracked SEPARATELY from KEY_SEEN_ALERTS (the foreground vibrate+confirm dedup set, above) so the
    // background notification is a purely ADDITIVE early signal: it never marks an alert "seen" for the
    // foreground path, so the in-app confirm-to-clear flow the wearer sees once they open the app still
    // fires normally, unaffected by whether a background notification already fired for the same alert.
    (:background)
    const KEY_BG_NOTIFIED_ALERTS = "bgNotifiedAlerts";
    (:background)
    function loadBgNotifiedAlerts() as Lang.Array {
        var s = Storage.getValue(KEY_BG_NOTIFIED_ALERTS);
        return (s instanceof Lang.Array) ? s : [];
    }
    (:background)
    function saveBgNotifiedAlerts(seen as Lang.Array) as Void {
        Storage.setValue(KEY_BG_NOTIFIED_ALERTS, seen);
    }

    // Pure, no side effect: the active alerts not yet surfaced as a background
    // notification. Deliberately does NOT write bgNotifiedAlerts itself —
    // the old newBackgroundAlertsToNotify() rewrote the bg-notified set to activeAlertIdentities()
    // BEFORE BgServiceDelegate.surfaceNewAlertsInBackground() had even attempted
    // Notifications.showNotification() for any of them, so a single throw there both permanently marked
    // every active alert "already notified" (no self-heal) AND aborted Background.exit() for the whole
    // batch. The caller must persist ONLY the identities that actually posted — see
    // reconciledBgNotifiedAlerts() below, which BgService.mc calls with the post-attempt result.
    (:background)
    function pendingBgNotifyAlerts() as Lang.Array {
        return newAlertsSince(loadBgNotifiedAlerts());
    }

    // Pure: the bg-notified set to persist after one surfaceNewAlertsInBackground() pass.
    // `presented` is exactly the identities whose Notifications.showNotification() call actually
    // returned without throwing (BgService.mc's own per-item try/catch) — NOT every active identity, and
    // NOT every pending identity. Mirrors reconciledSeenAlerts()'s identical fix for the foreground
    // seen-set: result = (previously-notified ∩ still-active) ∪ presented, restricted to
    // ACTIVE identities so a cleared/reconciled alert still drops out of the set (preserving the
    // "a cleared alert re-notifies if it re-fires" rule), while never adding an identity that wasn't
    // actually posted.
    (:background)
    function reconciledBgNotifiedAlerts(presented as Lang.Array) as Lang.Array {
        var active = activeAlertIdentities();
        var prevNotified = loadBgNotifiedAlerts();
        var out = [];
        for (var i = 0; i < active.size(); i += 1) {
            var ident = active[i];
            if (containsStr(prevNotified, ident) || containsStr(presented, ident)) { out.add(ident); }
        }
        return out;
    }

    function glucoseColor() as Gfx.ColorValue {
        if (glucose == null) { return Gfx.COLOR_LT_GRAY; }
        return rangeColor(glucose as Lang.Number);
    }

    // Range color for an arbitrary mg/dL value (used by the number + the history plot). Closed
    // clinical convention (GLUCOSE_* / faBolusCore.GlucoseThresholds): 180 colors in-range, 250 high.
    function rangeColor(g as Lang.Number) as Gfx.ColorValue {
        if (g < GLUCOSE_LOW) { return Gfx.COLOR_RED; }         // < 70
        if (g <= GLUCOSE_HIGH) { return Gfx.COLOR_GREEN; }     // 70…180 in-range
        if (g <= GLUCOSE_VERY_HIGH) { return Gfx.COLOR_YELLOW; } // 181…250 high
        return Gfx.COLOR_ORANGE;                               // > 250 urgent
    }
}
