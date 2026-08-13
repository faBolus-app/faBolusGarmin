using Toybox.Lang;
using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Time;
using Toybox.Application.Storage;

// Shared app state for the faBolus Garmin remote. Glance data comes from the phone
// (statusRead reply); carbs→units is computed locally from the pump's calculator settings so
// the hold-to-deliver screen can show the exact units.
module AppState {
    // Clinical glucose display bands (mg/dL), mirroring faBolusCore.GlucoseThresholds — the Battelino
    // 2019 international Time-in-Range consensus (70…180 in-range, 181…250 high, > 250 very-high).
    // Kept numerically identical across every surface; the closed-convention edges (180 in-range, 250
    // high) match the phone's coloring and its TIR stat. RangeColorTest pins those edges.
    const GLUCOSE_LOW = 70;
    const GLUCOSE_HIGH = 180;
    const GLUCOSE_VERY_HIGH = 250;

    // P-mmol (Phase 4, D-01/D-02/D-05): the Garmin hand-port of faBolusCore.GlucoseUnit — the ONLY
    // place this factor may appear on the Garmin side, mirroring the Swift canonical
    // (Packages/faBolusCore/Sources/faBolusCore/GlucoseUnit.swift, mgdlPerMmol = 18.0182). Pinned by
    // GlucoseUnitTest.mc against the same expected strings the Swift GlucoseUnitTests assert.
    const MGDL_PER_MMOL = 18.0182;
    // Display-unit wire token ("mgdl"|"mmol"), mirrored from the phone's statusRead reply
    // (RemoteCommand.glucoseDisplayUnit). D-06: this NEVER changes GLUCOSE_*/rangeColor()/the
    // canonical glucose/isf/targetBg Numbers themselves — it only selects which label
    // formatMgdl()/glucoseUnitLabel()/isfUnitLabel() render. Default "mgdl" is the fail-closed value
    // (T-04-02): an absent field (legacy host) or an unrecognized token is never adopted (see handle()
    // below), so a fresh install / older phone build always renders mg/dL.
    var glucoseUnit as Lang.String = "mgdl";

    // HUD data (from phone)
    var glucose as Lang.Number? = null;   // mg/dL
    var trend as Lang.String = "";
    var iob as Lang.Float = 0.0;          // units
    var carbRatio as Lang.Float = 0.0;    // g/u
    var isf as Lang.Number = 0;           // mg/dL per unit
    var targetBg as Lang.Number = 0;      // mg/dL
    var maxUnits as Lang.Float = 25.0;
    // Extra pump status (from phone) for the details screen.
    var reservoir as Lang.Float = -1.0;   // units remaining (-1 = unknown)
    var battery as Lang.Number = -1;      // percent (-1 = unknown)
    var lastBolus as Lang.Float = -1.0;   // units of the last bolus (-1 = unknown)
    var connection as Lang.String = "";   // e.g. "Connected"
    var readingEpoch as Lang.Number = 0;  // unix sec the current BG was taken (0 = unknown)
    // Staleness policy, synced from the phone (statusRead). staleSec: age after which the reading is
    // stale (greyed + not used for carb→unit). hideDelaySec: extra age before hiding ("--"); null =
    // never hide (always greyed), 0 = hide as soon as stale. Defaults mirror the phone (6 min / never).
    var staleSec as Lang.Number = 360;
    var hideDelaySec as Lang.Number or Null = null;
    var history as Lang.Array = [];       // recent mg/dL (Numbers), oldest → newest, for the plot
    // E5: per-point Unix-sec source timestamps, aligned 1:1 with `history` (same size, oldest →
    // newest). Empty ⇒ the phone sent no (or misaligned) epochs and the plot falls back to assumed
    // ~5-min index spacing. INVARIANT after parsing: historyEpochs.size() == history.size() (1:1) OR
    // historyEpochs is empty — never a partial/off-by-one array (see the lockstep parse in handle()).
    var historyEpochs as Lang.Array = [];
    var alerts as Lang.Array = [];        // active pump alerts: dicts {id, kind, title}
    var plotHours as Lang.Number = 3;     // history-plot window: 3 → 6 → 12 → 24 → 3

    // Configurable layout (from phone settings, persisted so it survives restarts / offline launch).
    // The swipe order of the screens and which one opens first. Ids: glance/alerts/history/details.
    var screenOrder as Lang.Array = ["glance", "alerts", "history", "details"];
    var defaultScreen as Lang.String = "glance";
    // "glucose" = a current-glucose screen with no bolus button (users can add it to the order instead
    // of, or alongside, the bolus "glance").
    const ALL_SCREENS = ["glance", "glucose", "clock", "bolusonly", "alerts", "history", "details"];

    // Read-only mode pushed from the phone ("remotesReadOnly"): hide the bolus button everywhere.
    var readOnly as Lang.Boolean = false;

    // P13 capability channel ("supportsRemoteAlertDismiss"): whether the pump firmware honors a REMOTE
    // alert dismissal. t:slim X2 silently rejects it (dismiss only snoozes locally); Mobi clears it on
    // the pump. Drives the confirm verb (alertActionWord). Safe default false => "Snooze" (honest — the
    // dismiss won't clear on the pump); the statusRead that carries an alert also carries this flag.
    var supportsRemoteAlertDismiss as Lang.Boolean = false;

    // P12 group D: the host's authoritative "may a remote start a bolus right now?" (schema `canBolus`),
    // plus its reason token (`bolusBlockReason`: "pumpNotLinked" | "bolusInFlight" | "accessDenied").
    // null until the host sends them (older host) → pumpBolusAllowed() falls back to deriving from the
    // connection string. Lets the START gate stop treating a substring match of the localized display
    // string ("Delivering…") as load-bearing safety logic.
    var hostCanBolus as Lang.Boolean or Null = null;
    var hostBolusBlockReason as Lang.String or Null = null;

    // P15 §2.3: whether the phone has enabled bolusing FROM THIS GARMIN. Default false ⇒ fail-closed: a
    // cold launch / glance with no push keeps the bolus affordance hidden until a push arms it (persisted
    // so a restart doesn't re-hide an already-enabled watch). The host also refuses a Garmin deliver when
    // false (AccessPolicy). `bolusPasscodeRequired` mirrors whether a 4-digit passcode confirms the bolus.
    var garminBolusEnabled as Lang.Boolean = false;
    var bolusPasscodeRequired as Lang.Boolean = false;

    // B2 (S1 + O3): the pump's automated-controller identity + its Control-IQ runtime on/off, pushed on
    // the statusRead reply so the watch can reconstruct the auto-correction DISCLOSURE locally (no prose
    // crosses the wire). Both mirror faBolusCore (ControllerVariant / PumpSnapshot.controlIQEnabled).
    // `controllerVariant` is a FROZEN token (schema `controllerVariant` enum): "none" / "controlIQ" /
    // "controlIQPro" — never invent others. DISPLAY-ONLY: neither ever gates, changes, or delays a bolus
    // (C3 — nothing here feeds a dose). Safe legacy default ("none" / false) ⇒ render nothing controller-
    // specific. Not persisted (matches the nearby display-only capability fields, e.g.
    // supportsRemoteAlertDismiss): a cold launch shows nothing controller-specific until the first push.
    var controllerVariant as Lang.String = "none";
    var controlIQEnabled as Lang.Boolean = false;

    // Details rows shown (in order) + which history ranges the plot cycles through on tap — both
    // mirrored from the phone ("detailsOrder" / "watchChartRanges" in the statusRead reply).
    var detailsOrder as Lang.Array = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"];
    const ALL_DETAILS = ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"];
    var chartRanges as Lang.Array = [3, 6, 12, 24];
    // How the BG complication presents: "numericColor" (numeric value + range color + Latin trend
    // in the unit slot) or "stringTrend" (plain "124 ^" string). Mirrored from the phone.
    var complicationDisplay as Lang.String = "numericColor";

    // Load persisted layout at launch (getInitialView needs defaultScreen before any phone message).
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
        // GA-08: restore the staleness policy so a restart / background launch honors the phone-synced
        // value instead of silently reverting to the 6-min default until the next statusRead.
        var ss = Storage.getValue("staleSec");
        if (ss instanceof Lang.Number && ss > 0) { staleSec = ss; }
        var hd = Storage.getValue("hideDelaySec");
        hideDelaySec = (hd instanceof Lang.Number && hd >= 0) ? hd : null;   // absent/null = never hide
        // P15 §2.3: restore the persisted bolus-enable so a cold launch stays on the last-known value
        // (fail-closed to false when never armed) instead of re-hiding an already-enabled watch.
        var gbe = Storage.getValue("garminBolusEnabled");
        if (gbe instanceof Lang.Boolean) { garminBolusEnabled = gbe; }
        // C2 §2.3: restore the persisted passcode-required flag the same way, so a cold launch before the
        // first statusRead already knows a passcode confirms the bolus — closing the window where a
        // required→(default not-required) flip could briefly offer the tap/hold confirm instead. Default
        // false is a safe fail-open here (worst case the phone still denies an unverified bolus), but
        // persisting matches garminBolusEnabled and avoids that transient.
        var bpr0 = Storage.getValue("bolusPasscodeRequired");
        if (bpr0 instanceof Lang.Boolean) { bolusPasscodeRequired = bpr0; }
        // P-mmol / D-04: restore the persisted display-unit token the same guarded way, so a cold
        // launch before the first statusRead already renders in the last unit the phone pushed
        // (fail-closed to the "mgdl" default when never set / not yet a recognized token).
        var gu0 = Storage.getValue("glucoseDisplayUnit");
        if (gu0 instanceof Lang.String && isValidUnitToken(gu0 as Lang.String)) { glucoseUnit = gu0; }
    }

    // Frozen wire-token set for the display-unit field (Pitfall 6 — never a raw enum on the wire).
    function isValidUnitToken(t as Lang.String) as Lang.Boolean {
        return t.equals("mgdl") || t.equals("mmol");
    }

    // Keep only allowed string ids (de-duped), preserving the phone-chosen subset + order.
    function sanitizeAgainst(list as Lang.Array, allow as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.String && contains(allow, v) && !containsStr(out, v)) { out.add(v); }
        }
        return out;
    }

    // Keep only the allowed history ranges {3,6,12,24}, de-duped, preserving order.
    function sanitizeRanges(list as Lang.Array) as Lang.Array {
        var allowed = [3, 6, 12, 24];
        var out = [];
        for (var i = 0; i < list.size(); i += 1) {
            var v = list[i];
            if (v instanceof Lang.Number && containsNum(allowed, v) && !containsNum(out, v)) { out.add(v); }
        }
        return out;
    }

    function containsStr(list as Lang.Array, v as Lang.String) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.String && (list[i] as Lang.String).equals(v)) { return true; }
        }
        return false;
    }
    function containsNum(list as Lang.Array, v as Lang.Number) as Lang.Boolean {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] instanceof Lang.Number && (list[i] as Lang.Number) == v) { return true; }
        }
        return false;
    }
    function ensureValidPlotHours() as Void {
        if (chartRanges.size() > 0 && !containsNum(chartRanges, plotHours)) {
            plotHours = chartRanges[0] as Lang.Number;
        }
    }

    // Keep only known ids (de-duped), preserving the phone-chosen subset + order. Screens the user
    // hid are intentionally omitted. Falls back to all screens only if the result would be empty,
    // so the watch is never left with nothing to show.
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
    function ensureValidDefault() as Void {
        if (!contains(screenOrder, defaultScreen)) {
            defaultScreen = (screenOrder.size() > 0) ? (screenOrder[0] as Lang.String) : "glance";
        }
    }

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

    // AB4 (Addendum B): the three stale-CGM choices, mirroring faBolusCore StaleBolusChoice. Kept as
    // module consts + pure predicates HERE (not on the view) so the safety-critical semantics are
    // unit-testable — the view/delegate aren't compiled into the test binary (see test.jungle).
    const STALE_INCLUDE = 0;      // dose the correction off the stale-but-REAL reading (insulin-INCREASING)
    const STALE_CARBS_ONLY = 1;   // today's silent behavior — drop the stale BG, carbs-only, now acknowledged
    const STALE_CANCEL = 2;       // pure UI back-out — compose/send NOTHING

    // Mirror of StaleBolusPrompt.proceeds: every path composes + sends EXCEPT cancel, which sends nothing.
    function staleChoiceProceeds(opt as Lang.Number) as Lang.Boolean { return opt != STALE_CANCEL; }
    // Mirror of StaleBolusPrompt.bgForCalculation: only "include" carries the stale reading into the dose.
    function staleChoiceIncludesBg(opt as Lang.Number) as Lang.Boolean { return opt == STALE_INCLUDE; }

    // AB4 (Addendum B): mirror of StaleBolusPrompt.shouldWarn — show the three-way stale-CGM choice only
    // when there IS a reading value AND it is stale at compose. No reading at all is simply carbs-only
    // (nothing to include); a fresh reading composes normally. Same staleness the UI grays (glucoseStale).
    // (Garmin: only carbs mode has a correction term, so the delegate additionally gates on carbs mode.)
    function staleBolusShouldWarn() as Lang.Boolean {
        return glucose != null && glucoseStale();
    }

    // AB4 (Addendum B): the BG (mg/dL) to feed the correction / send with a carb bolus — mirror of
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
    function pumpConnected() as Lang.Boolean {
        return connection.equals("Connected") || bolusing();
    }

    // A bolus is currently being delivered ("Delivering…").
    function bolusing() as Lang.Boolean {
        return connection.find("Deliver") == 0;
    }

    // Whether the PUMP side permits a new bolus — the host's authoritative flag when present (schema
    // `canBolus`: pump linked AND not mid-delivery AND remotes not read-only), otherwise derived from
    // the connection string. Excludes phone reachability (the Garmin's own local link), so it is
    // deterministically unit-testable; canBolus() ANDs in reachability. P12 group D: this is what
    // stops the START gate from depending on a substring match of the localized display string.
    function pumpBolusAllowed() as Lang.Boolean {
        if (hostCanBolus != null) { return hostCanBolus; }
        return pumpConnected() && !bolusing();
    }

    // A new bolus is only possible when the phone (which owns the pump link) is reachable AND the pump
    // side permits it. The Garmin never touches the pump directly.
    function canBolus() as Lang.Boolean {
        return garminBolusEnabled && RemoteComm.phoneReachable() && pumpBolusAllowed();
    }

    // P15 §2.3 / G4: the bolus affordance is HOST-POLICY-disabled when the phone put the remote in
    // read-only mode OR hasn't enabled Garmin bolusing. Distinct from canBolus() (which ALSO needs phone
    // reachability + pump-side allowance): this is exactly the pair of phone-pushed flags whose mid-flow
    // flip must tear down an already-armed confirm. Deterministic (no reachability) → unit-testable.
    function bolusPolicyDisabled() as Lang.Boolean {
        return readOnly || !garminBolusEnabled;
    }

    // G4: whether an armed, pre-delivery confirm must be torn down RIGHT NOW — bolusing was policy-
    // disabled (read-only or Garmin-bolus-off) AND nothing has been sent yet (status == null; once a
    // request is out the outcome flow owns the screen and must not be disturbed). Pure/deterministic;
    // HoldView calls it on every redraw (a phone push always triggers Ui.requestUpdate()).
    function mustTeardownArmedBolus() as Lang.Boolean {
        return status == null && bolusPolicyDisabled();
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

    // P13 capability channel: the verb for the alert-dismiss confirmation — "Clear" when the pump honors
    // a REMOTE dismissal (Mobi), "Snooze" when it doesn't (t:slim, where it only snoozes locally), so the
    // Garmin prompt is honest and matches the phone. Pure/deterministic → unit-testable.
    function alertActionWord() as Lang.String {
        return supportsRemoteAlertDismiss ? "Clear" : "Snooze";
    }

    // B2 (S1 + O3) — auto-correction DISCLOSURE derivation. A faithful Monkey C hand-port of faBolusCore
    // `ControllerDescriptor` + `AutoCorrectionDisclosure`, kept HERE as pure module functions so the
    // safety-neutral copy is unit-testable (the view is not compiled into the test binary — see
    // test.jungle). DISPLAY-ONLY: every function returns a string to show (or "") — nothing here blocks,
    // disables, clamps, delays, or resizes a dose; the Deliver button is unchanged (C3).
    //
    // §13 clinical-disclosure values (subject to the clinical-review distribution gate), mirroring the
    // faBolusCore source of truth so the copy is a verbatim cross-surface contract:
    //   • display names "Control-IQ" / "Control-IQ+"  (ControllerDescriptor.displayName)
    //   • lockout window 60 min for BOTH variants      (AutomaticCorrection.blockedByRecentBolusMinutes)
    //   • thresholds 180 / 150-when-rising             (AutoCorrectionDisclosure.disclose{,Rising}AtOrAbove)
    //   • "rising" = the pump's OWN reported up arrows  (risingTrends [.rising,.up,.upUp] → up45/up/upup);
    //     C8 — the arrow is READ, never a computed/synthesized glucose rate.
    // FROZEN token set (schema `controllerVariant` enum) — never invent others.
    const CONTROLLER_VARIANTS = ["none", "controlIQ", "controlIQPro"];
    const CONTROLLER_RISING_TRENDS = ["up45", "up", "upup"];
    const CONTROLLER_DISCLOSE_AT_OR_ABOVE = 180;
    const CONTROLLER_DISCLOSE_RISING_AT_OR_ABOVE = 150;

    // Controller marketing name for a variant token; "" for "none"/unknown (mirror displayName).
    function controllerDisplayName(variant as Lang.String) as Lang.String {
        if (variant.equals("controlIQ")) { return "Control-IQ"; }
        if (variant.equals("controlIQPro")) { return "Control-IQ+"; }
        return "";
    }

    // Whether the variant names a real auto-correcting controller (mirror
    // ControllerDescriptor.automaticCorrection.enabled — true for controlIQ/controlIQPro, false for none).
    function controllerAutoCorrects(variant as Lang.String) as Lang.Boolean {
        return variant.equals("controlIQ") || variant.equals("controlIQPro");
    }

    // The documented auto-correction lockout window (minutes) a manual bolus imposes — 60 for BOTH
    // Control-IQ and Control-IQ+ (mirror AutomaticCorrection.blockedByRecentBolusMinutes). Kept as a
    // function (not a bare 60 in the copy) so the disclosure text derives it from the descriptor.
    function controllerLockoutMinutes(variant as Lang.String) as Lang.Number {
        return 60;
    }

    // "rising" trigger test: the pump's OWN reported up arrows (C8 — read, never a computed rate).
    function controllerTrendRising(trendToken as Lang.String) as Lang.Boolean {
        return containsStr(CONTROLLER_RISING_TRENDS, trendToken);
    }

    // O3 (ambient) — the persistent "automatic correction is active." line, or "" when it must not show.
    // Mirror of AutoCorrectionDisclosure.ambientIndicator: shown only when the variant auto-corrects AND
    // Control-IQ is ON at runtime. Glucose-independent. DISPLAY-ONLY.
    function controllerAmbientText(variant as Lang.String, enabled as Lang.Boolean) as Lang.String {
        if (!enabled || !controllerAutoCorrects(variant)) { return ""; }
        return controllerDisplayName(variant) + " automatic correction is active.";
    }

    // S1 (lockout) — the high/rising auto-correction lockout line, or "" when it must not show. Mirror of
    // AutoCorrectionDisclosure.lockoutMessage: shown only when the variant auto-corrects, Control-IQ is
    // ON, there IS a reading, and the trigger fires: glucose >= 180, OR (glucose >= 150 AND the pump's
    // own arrow is rising). DISPLAY-ONLY — a caution to READ; it never blocks/changes/delays the dose.
    function controllerLockoutText(variant as Lang.String, enabled as Lang.Boolean,
                                   glucoseMgdl as Lang.Number?, trendToken as Lang.String) as Lang.String {
        if (!enabled || !controllerAutoCorrects(variant) || glucoseMgdl == null) { return ""; }
        var g = glucoseMgdl as Lang.Number;
        var trigger = (g >= CONTROLLER_DISCLOSE_AT_OR_ABOVE)
                   || (g >= CONTROLLER_DISCLOSE_RISING_AT_OR_ABOVE && controllerTrendRising(trendToken));
        if (!trigger) { return ""; }
        return "Bolusing now pauses " + controllerDisplayName(variant)
             + "'s automatic correction for about " + controllerLockoutMinutes(variant).toString() + " min.";
    }

    // The single disclosure line for the small bolus screen: the S1 caution when it fires, otherwise the
    // O3 ambient line, otherwise "". Reads live state (controllerVariant/controlIQEnabled + the glucose /
    // trend already parsed from the SAME statusRead). When both would apply S1 wins — it is the caution.
    // Pairs with controllerDisclosureIsCaution() so the view can color it. DISPLAY-ONLY.
    function controllerDisclosureLine() as Lang.String {
        var s1 = controllerLockoutText(controllerVariant, controlIQEnabled, glucose, trend);
        if (!s1.equals("")) { return s1; }
        return controllerAmbientText(controllerVariant, controlIQEnabled);
    }
    // True when the line controllerDisclosureLine() would return is the S1 lockout caution (color it as a
    // caution), false for the ambient O3 line or none.
    function controllerDisclosureIsCaution() as Lang.Boolean {
        return !controllerLockoutText(controllerVariant, controlIQEnabled, glucose, trend).equals("");
    }

    // A short user-facing reason the bolus button is disabled, so the bolus screen can say WHY (P12
    // exit: every disabled control shows a reason). Prefers the host's reason token; falls back to the
    // connection string / reachability for an older host. "" when a bolus IS possible.
    function bolusBlockLabel() as Lang.String {
        if (canBolus()) { return ""; }
        if (!RemoteComm.phoneReachable()) { return "Phone not connected"; }
        // P15 §2.3: bolusing from this Garmin is turned off on the phone — say so (and how to fix it).
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
    // called out), never hidden. "--" only when there's no reading at all. Unit-aware (P-mmol):
    // renders in the active glucoseUnit via the pure displayGlucoseForUnit() funnel below.
    function displayGlucose() as Lang.String {
        return glucose == null ? "--" : formatMgdl(glucose as Lang.Number);
    }

    // P-mmol: format an arbitrary mg/dL value (glucose, isf, targetBg — anything canonical mg/dL) in
    // the CURRENT instance unit. Every Garmin glucose/ISF/target display site routes through this (or
    // the pure displayGlucoseForUnit() below), mirroring faBolusCore.GlucoseUnit.format(mgdl:) exactly:
    // mgdl → the plain integer string (unchanged); mmol → 1-decimal (D-05), never a second inline
    // "/ 18.0182" — GlucoseUnitTest.mc pins this against the same expected strings as the Swift funnel.
    function formatMgdl(v as Lang.Number) as Lang.String {
        return displayGlucoseForUnit(v, glucoseUnit);
    }

    // Pure variant of formatMgdl()/displayGlucose(), independent of the instance's loaded
    // glucoseUnit — for contexts (FaBolusGlanceView's (:glance) surface) that read Storage directly
    // rather than depending on AppState.loadPrefs() having run first (see FaBolusGlanceView.mc's own
    // "reads Storage directly" note). Both call sites route through this ONE conversion so the math
    // is never duplicated.
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
    var defaultMode as Lang.String = "carbs";
    var unitsValue as Lang.Float = 0.0;
    var carbsValue as Lang.Number = 0;
    // AB4 (Addendum B): per-attempt choice to include a STALE CGM reading in the correction. Off by
    // default and cleared by reset() before every compose, so it is NEVER sticky and NEVER a default —
    // set true only when the wearer explicitly picks "include" in the three-way stale prompt this attempt.
    var includeStaleBg as Lang.Boolean = false;
    var stepU as Lang.Float = 0.05;       // bolus increment (from phone settings)
    var stepC as Lang.Number = 5;         // carb increment (from phone settings)
    const MAX_CARBS = 200;

    // Delivery
    var deliverUnits as Lang.Float = 0.0; // captured when entering the hold screen
    var holdProgress as Lang.Float = 0.0; // 0..1 for the hold-to-deliver ring
    var pendingRequestId as Lang.String? = null;
    var status as Lang.String? = null;    // delivering/delivered/failed/...
    var message as Lang.String? = null;
    // Whether the phone has been seen bolusing since this request started, so a lost/late
    // terminal echo can be recovered from the connection state (see handle()).
    var sawPhoneBolusing as Lang.Boolean = false;

    function reset() as Void {
        mode = defaultMode; unitsValue = 0.0; carbsValue = 0;
        pendingRequestId = null; status = null; message = null; sawPhoneBolusing = false;
        includeStaleBg = false;   // AB4: the stale-BG include choice is per-attempt — never carried over
    }

    // C2 §2.3 / P15 §2.3 — the SINGLE bolus send funnel. Extracted verbatim from HoldView.deliver() so
    // BOTH confirm surfaces send through the identical path with NO duplicated or divergent delivery
    // semantics:
    //   • HoldView (tap/hold confirm, no passcode)      → sendBolusNow(null)
    //   • PasscodeEntryView (passcode confirm, §2.3)     → sendBolusNow(enteredCode)
    // It mints the reqId, sets pendingRequestId, resets the lost-echo tracker, checks reachability, sets
    // status="delivering", and calls the RemoteComm builder — exactly as before. `code` is threaded to the
    // builder, which adds "bolusPasscode" to the wire only when non-null. The WATCH NEVER verifies or
    // persists the code — the phone is the sole authority and denies a wrong/absent one.
    //
    // Returns false ONLY when the P15 §2.3 / G4 policy-disabled hard guard blocked the send WITHOUT
    // sending anything (read-only ON or Garmin bolusing OFF pushed while confirming) — the caller must
    // then de-arm its own view-local confirm state. Returns true when a request was sent OR a terminal
    // status was set (outOfRange), i.e. the confirm surface is done and status now owns the screen.
    function sendBolusNow(code as Lang.String?) as Lang.Boolean {
        if (bolusPolicyDisabled()) { return false; }
        var reqId = RemoteComm.newRequestId();
        pendingRequestId = reqId;
        sawPhoneBolusing = false;   // reset the lost-echo recovery tracker for this request
        if (!RemoteComm.phoneReachable()) {
            status = "outOfRange"; message = "iPhone unreachable"; return true;
        }
        status = "delivering";
        // Carbs mode: send carbsGrams (+ bg + this watch's estimate) so the phone is the single
        // calculator and can run the divergence guard. Units mode: send the units as before.
        if (mode.equals("carbs")) {
            // AB4 (Addendum B): fresh → the reading; stale → included only on the explicit per-attempt
            // "include" choice, else nil-dropped (carbs-only). bgForBolus() encapsulates that decision.
            // Option B: also forward the include-stale INTENT (includeStaleBg — the same per-attempt flag,
            // cleared by reset()) so the host can honor an acknowledged-stale correction instead of failing
            // closed to carbs-only. The builder omits it entirely unless true (never sent on units mode).
            var bg = bgForBolus();
            RemoteComm.send(RemoteComm.bolusRequestCarbs(carbsValue, bg, deliverUnits, reqId, code, includeStaleBg));
        } else {
            RemoteComm.send(RemoteComm.bolusRequest(deliverUnits, reqId, code));
        }
        return true;
    }

    // G5 (Garmin half): a one-time, plain-language notice shown the first time the wearer opens the
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

    // C2 §2.3 (Garmin half): a SEPARATE one-time notice, shown the FIRST time a passcode is actually
    // required, explaining that a 4-digit passcode set in faBolus on the phone now confirms a bolus
    // (replacing the tap/hold). The plan's "prompt at pairing time" has no on-watch equivalent — pairing
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
    // (audit C-01). Keep it in lockstep with that Swift/Java source. The key correctness point:
    //   • food = carbs / carbRatio
    //   • fromBG = (glucose - target) / isf   (SIGNED — a below-target BG is negative and REDUCES the dose)
    //   • fromIOB = -iob (only when iob > 0)   — IOB offsets a BG correction, never a bare carb dose
    //   • at/above target: add (fromBG + fromIOB) only if that sum is positive
    //   • below target: apply (fromBG + fromIOB) if it keeps the total positive, else floor total at 0
    // The old code floored the *correction* at 0 before combining, which dropped every below-target
    // reduction and over-recommended. Units mode is a manual fixed dose (no correction / IOB).
    // GA-04: the oracle's BolusCalcUnits.doublePrecision — BigDecimal.setScale(2, HALF_UP): round to two
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
    // "carbs" branch so `recommendedUnits()` (SG task #93, below) can read the SAME calculator total
    // regardless of the CURRENT mode, without a second, independently-drifting copy of this logic.
    // computeUnits() and recommendedUnits() each apply their own identical final rounding/clamp step.
    // 0.0 when the carb ratio hasn't arrived from the phone (FB-01 — do NOT silently assume 10 g/U;
    // that is an unverified guess that could misdose. `carbCalcAvailable()`/`sgDisplaysNumericDose()`
    // tell "genuinely zero" apart from "not available yet").
    function carbCorrectionTotal() as Lang.Float {
        if (carbRatio <= 0.0) { return 0.0; }
        // GA-04: round EACH component to two decimals (half-up) before combining — exactly as the
        // oracle-backed host does. Combining unrounded components then rounding only the total drifted
        // by one 0.05 U pump increment on ~1.5% of inputs, and the host's 0.10 U tolerance accepted it,
        // so the delivered dose could differ from the number shown on the hold screen.
        var fromCarbs = dp2(carbsValue.toFloat() / carbRatio);
        var fromBG = 0.0;
        // AB4 (Addendum B): a stale BG is dropped from the correction (carbs-only) UNLESS the wearer
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

    // ---- Insulin Stacking Guard (SG1 + SG3a, task #93) ----
    // Hand-port of faBolusCore.StackingGuard (Packages/faBolusCore/Sources/faBolusCore/StackingGuard.swift).
    // Mirrors controllerDisclosureLine()'s/-IsCaution()'s exact shape and doc contract immediately above:
    // these are DISCLOSURE facts, never therapy — NEVER affect delivery. `computeUnits()`/`deliverUnits`
    // are only ever READ here, never written or changed by anything below.
    //
    // The comparison baseline is `recommendedUnits()`: the SAME carbs+correction math computeUnits()
    // already runs (both are wrist-side PREVIEWS the phone re-derives with the oracle-backed calculator
    // and divergence-guards before delivery — see computeUnits()'s doc comment above), read via the
    // shared `carbCorrectionTotal()` helper so this is not a second, drifting recompute.
    //
    // On THIS watch the override signal is only ever live in "units" mode: Carbs mode has no separate
    // manual-units step (deliverUnits == computeUnits() == recommendedUnits() there by construction, so
    // SG never fires in Carbs mode); Units mode lets the wearer pick ANY amount, via the same +/- stepper,
    // independent of the carb-based suggestion — exactly the override SG discloses.
    //
    // §13 owner-confirmable, lock-backed cut-points below default IDENTICALLY to StackingGuard.swift's
    // OSAllocatedUnfairLock-backed statics (1.5 / 2.0). Monkey C's single-threaded VM needs no lock — a
    // bare module var is the platform-appropriate mirror of that same idiom. NOT clinical constants.
    var sgConfirmExtraOverrideRatio as Lang.Float = 1.5;
    var sgReenterOverrideRatio as Lang.Float = 2.0;

    // The pump-calculator's carb+correction suggestion, computed regardless of the CURRENT mode (see
    // the SG block above) — SG's comparison baseline. Same final rounding/clamp as computeUnits() so
    // entered vs. recommended compare at the same precision. 0.0 when the carb ratio hasn't synced yet
    // (mirrors carbCorrectionTotal()'s own FB-01 guard) — pair with sgDisplaysNumericDose() to tell
    // "genuinely zero" apart from "not available yet".
    function recommendedUnits() as Lang.Float {
        var total = carbCorrectionTotal();
        total = Math.round(total * 20.0) / 20.0;
        if (total < 0.0) { total = 0.0; }
        if (total > maxUnits) { total = maxUnits; }
        return total;
    }

    // §13 Rule-1 mirror: a numeric dose may only be CITED once the pump's real calculator settings (its
    // carb ratio) have synced — never sized off a placeholder guess.
    function sgDisplaysNumericDose() as Lang.Boolean {
        return carbRatio > 0.0;
    }

    // SG1 — hand-port of StackingGuard.calcOverride, keyed on the value that will actually be delivered
    // right now (computeUnits()). "" when it must not fire. DISPLAY-ONLY — never gates, changes, or
    // delays the Deliver button.
    function sgCalcOverrideLine() as Lang.String {
        if (!sgDisplaysNumericDose()) { return ""; }
        var entered = computeUnits();
        if (entered <= 0.0) { return ""; }
        if (glucose == null) { return ""; }
        var g = glucose as Lang.Number;
        if (g <= targetBg) { return ""; }
        var recommended = recommendedUnits();
        // Full-override branch — BEFORE any ratio, mirroring StackingGuard.swift: a nonzero entered
        // dose against a zero recommendation discloses without ever computing entered/recommended.
        if (recommended == 0.0) {
            return "You're entering " + entered.format("%.2f") + " U — the pump's calculator did not suggest a dose.";
        }
        if (entered <= recommended) { return ""; }
        return "You're entering more than the pump's calculator suggested.";
    }

    // SG3a — hand-port of StackingGuard.escalation: composes SG1 + the max-bolus proximity signal (SG2)
    // into ONE message ("" when SG1 wouldn't fire). DISPLAY-ONLY. NO new confirm step exists on this
    // watch for ANY tier — the SG3a friction ceiling here IS the existing single HoldView tap/hold
    // (never a second dialog, never a re-type); see BolusView.mc's render call site.
    function sgDisclosureLine() as Lang.String {
        var sg1 = sgCalcOverrideLine();
        if (sg1.equals("")) { return ""; }
        var entered = computeUnits();
        var recommended = recommendedUnits();
        if (recommended == 0.0) {
            return "You're entering " + entered.format("%.2f")
                 + " U with no calculator suggestion to compare against — please re-enter to confirm.";
        }
        var atOrAboveMax = (maxUnits > 0.0) && (entered >= maxUnits);
        var ratio = entered / recommended;
        if (ratio >= sgReenterOverrideRatio) {
            return "This dose is far above what the pump's calculator suggested — please re-enter to confirm.";
        }
        if (ratio >= sgConfirmExtraOverrideRatio || atOrAboveMax) {
            return "This dose is well above what the pump's calculator suggested — please confirm before delivering.";
        }
        return sg1;
    }

    // True when sgDisclosureLine() is at the confirmExtra/reenter tier (color it as a caution, like
    // S1's lockout line); false for the disclose tier or "". Pairs with sgDisclosureLine() the way
    // controllerDisclosureIsCaution() pairs with controllerDisclosureLine().
    function sgDisclosureIsCaution() as Lang.Boolean {
        var line = sgDisclosureLine();
        if (line.equals("")) { return false; }
        return !line.equals(sgCalcOverrideLine());
    }

    function valueLabel() as Lang.String {
        if (mode.equals("units")) { return unitsValue.format("%.2f") + " U"; }
        return carbsValue.toString() + " g";
    }

    // FB-01: a carb bolus can only be estimated on the wrist once the pump's carb ratio has synced from
    // the phone. Units mode never needs it. When false the UI shows "calculator unavailable" and blocks
    // the bolus (we do NOT fall back to an assumed 10 g/U).
    function carbCalcAvailable() as Lang.Boolean {
        return !mode.equals("carbs") || carbRatio > 0.0;
    }

    // Route an inbound phone message.
    function handle(data as Lang.Dictionary) as Void {
        var kind = data["kind"] as Lang.String?;
        if (kind == null) { return; }
        if (kind.equals("statusRead")) {
            // Guard the assignment (audit): a partial statusRead that omits bgMgdl must NOT null out the
            // last-known glucose (which would blank the value + disable correction dosing). Keep last.
            // GA-09: every field is range/finite-validated before it mutates state; a bad value returns
            // null and the last good reading is kept (see numRange/fltRange/validTrend/strCap).
            var bg = numRange(data["bgMgdl"], 0, 600); if (bg != null) { glucose = bg; }
            var t = validTrend(data["trend"]); if (t != null) { trend = t; }
            var i = fltRange(data["units"], 0.0, 100.0); if (i != null) { iob = i; }
            var cr = fltRange(data["carbRatio"], 1.0, 300.0); if (cr != null) { carbRatio = cr; }
            var isfv = numRange(data["isf"], 1, 1000); if (isfv != null) { isf = isfv; }
            var tb = numRange(data["targetBg"], 40, 400); if (tb != null) { targetBg = tb; }
            var mx = fltRange(data["maxBolusUnits"], 0.0, 100.0); if (mx != null) { maxUnits = mx; }
            var rv = fltRange(data["reservoirUnits"], 0.0, 1000.0); if (rv != null) { reservoir = rv; }
            var bt = numRange(data["batteryPercent"], 0, 100); if (bt != null) { battery = bt; }
            var cn = strCap(data["message"], 120); if (cn != null) { connection = cn; }
            // GA-03 / round-2: the AUTHORITATIVE terminal outcome is the phone's bolusStatus echo (by
            // requestId), handled below — including the FB-02 "unknown" status when the pump outcome is
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
            // Group A (defect A1). Prefer the phone's IMMUTABLE source epoch: an age is computed when
            // the phone composes the message, so by the time it lands here it already understates the
            // reading's true age. Fall back to the age only for a host too old to send an epoch.
            //
            // A reading with NEITHER an epoch nor an age has an UNKNOWN age, and unknown must mean
            // stale. It previously meant "now" — which is exactly A1: a value labelled "1 minute old"
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
            var sm = numRange(data["glucoseStaleMinutes"], 1, 720); if (sm != null) { staleSec = sm * 60; }
            var hd = numRange(data["glucoseHideDelayMinutes"], 0, 1440);
            hideDelaySec = (hd != null) ? hd * 60 : null;
            // GA-08: persist the staleness policy so the glance / complication (separate launch contexts)
            // and a cold restart honor it before the next statusRead arrives.
            Storage.setValue("staleSec", staleSec);
            if (hideDelaySec != null) { Storage.setValue("hideDelaySec", hideDelaySec); }
            else { Storage.deleteValue("hideDelaySec"); }
            // E5: parse history and its per-point epochs in LOCKSTEP so the two arrays are guaranteed
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
            var al = data["alerts"]; if (al instanceof Lang.Array) { alerts = sanitizeAlerts(al); }
            var ro = data["remotesReadOnly"]; if (ro instanceof Lang.Boolean) { readOnly = ro; }
            // P13 capability channel: whether a remote dismiss clears on the pump (Mobi) or only snoozes
            // locally (t:slim) — drives the alert confirm verb. Strict guard: a non-boolean is ignored.
            var sd = data["supportsRemoteAlertDismiss"]; if (sd instanceof Lang.Boolean) { supportsRemoteAlertDismiss = sd; }
            // P12 group D: the host's semantic bolus availability + reason token (see hostCanBolus).
            var cb = data["canBolus"]; if (cb instanceof Lang.Boolean) { hostCanBolus = cb; }
            var cbr = data["bolusBlockReason"]; if (cbr instanceof Lang.String) { hostBolusBlockReason = strCap(cbr, 40); }
            // P15 §2.3: whether bolusing from this Garmin is enabled on the phone (default OFF). Persist so a
            // cold launch stays fail-closed on the last-known value. Also the passcode-required flag (drives
            // confirm). Strict guards: a non-boolean is ignored (keeps the last / safe default).
            var gbe2 = data["garminBolusEnabled"];
            if (gbe2 instanceof Lang.Boolean) { garminBolusEnabled = gbe2; Storage.setValue("garminBolusEnabled", garminBolusEnabled); }
            var bpr = data["bolusPasscodeRequired"];
            // C2 §2.3: persist like garminBolusEnabled so a cold launch / background context knows a
            // passcode is required before the first statusRead (loadPrefs restores it). Strict guard: a
            // non-boolean is ignored (keeps the last / safe default). The watch only COLLECTS the code and
            // sends it; the phone verifies + persists nothing here beyond this required flag.
            if (bpr instanceof Lang.Boolean) { bolusPasscodeRequired = bpr; Storage.setValue("bolusPasscodeRequired", bolusPasscodeRequired); }
            // B2 (S1 + O3): the pump's controller identity + Control-IQ runtime on/off, for the LOCAL
            // auto-correction disclosure. FROZEN token set (CONTROLLER_VARIANTS = the schema
            // `controllerVariant` enum) — an unknown/garbage variant is ignored (keeps the last / safe
            // "none"). controlIQEnabled is strict-guarded like the other capability booleans. Display-
            // only: nothing here feeds a dose (C3), so no persistence is needed.
            var cvr = data["controllerVariant"];
            if (cvr instanceof Lang.String && containsStr(CONTROLLER_VARIANTS, cvr as Lang.String)) { controllerVariant = cvr; }
            var ciqe = data["controlIQEnabled"];
            if (ciqe instanceof Lang.Boolean) { controlIQEnabled = ciqe; }
            var bm = data["bolusMode"] as Lang.String?;
            if (bm != null && (bm.equals("units") || bm.equals("carbs"))) { defaultMode = bm; }
            var bi = fltRange(data["bolusIncrement"], 0.01, 5.0); if (bi != null) { stepU = bi; }
            var ci = numRange(data["carbIncrement"], 1, 100); if (ci != null) { stepC = ci; }
            var so = data["screenOrder"];
            if (so instanceof Lang.Array) {
                screenOrder = sanitizeOrder(so);
                Storage.setValue("screenOrder", screenOrder);
            }
            var ds = data["defaultScreen"] as Lang.String?;
            if (ds != null && contains(screenOrder, ds)) {
                defaultScreen = ds;
                Storage.setValue("defaultScreen", ds);
            }
            ensureValidDefault();
            var detOrderRaw = data["detailsOrder"];
            if (detOrderRaw instanceof Lang.Array) {
                var detOrderSan = sanitizeAgainst(detOrderRaw, ALL_DETAILS);
                if (detOrderSan.size() > 0) { detailsOrder = detOrderSan; Storage.setValue("detailsOrder", detailsOrder); }
            }
            var chartRaw = data["watchChartRanges"];
            if (chartRaw instanceof Lang.Array) {
                var chartSan = sanitizeRanges(chartRaw);
                if (chartSan.size() > 0) { chartRanges = chartSan; Storage.setValue("watchChartRanges", chartRanges); ensureValidPlotHours(); }
            }
            var cdisp = data["garminComplicationDisplay"];
            if (cdisp instanceof Lang.String && ((cdisp as Lang.String).equals("numericColor") || (cdisp as Lang.String).equals("stringTrend"))) {
                complicationDisplay = cdisp; Storage.setValue("complicationDisplay", complicationDisplay);
            }
            // P15 E4b: the clock screen's analog-vs-digital choice is now PHONE-DRIVEN, replacing the old
            // on-watch tap toggle. Persist under the SAME "clockAnalog" Storage key ClockView.analog()
            // reads, so a cold launch keeps the last phone-pushed value. Strict guard (mirrors
            // remotesReadOnly / garminBolusEnabled): a non-boolean is ignored, leaving the last persisted
            // value (or ClockView's digital default when never set) untouched.
            var ca = data["clockAnalog"];
            if (ca instanceof Lang.Boolean) { Storage.setValue("clockAnalog", ca); }
            // P-mmol / D-04: display-unit token mirrored from the phone (RemoteCommand.
            // glucoseDisplayUnit, additive-optional). Strict guard (mirrors clockAnalog/
            // garminComplicationDisplay above): only a recognized "mgdl"|"mmol" token is adopted +
            // persisted; an absent/unrecognized token is ignored, keeping the last persisted value —
            // which fails closed to "mgdl" on a fresh install / older phone build that never sends it
            // (T-04-02). The canonical glucose/isf/targetBg Numbers are never touched here — only the
            // label this token selects.
            var gu = data["glucoseDisplayUnit"];
            if (gu instanceof Lang.String && isValidUnitToken(gu as Lang.String)) {
                glucoseUnit = gu;
                Storage.setValue("glucoseDisplayUnit", glucoseUnit);
            }
        } else if (kind.equals("bolusStatus")) {
            var rid = strCap(data["requestId"], 64);
            if (pendingRequestId != null && rid != null && rid.equals(pendingRequestId)) {
                // GA-09: only adopt a recognized status token, and cap the message length.
                var st = data["status"];
                if (st instanceof Lang.String && containsStr(STATUS_TOKENS, st as Lang.String)) { status = st; }
                message = data.hasKey("message") ? strCap(data["message"], 160) : null;
                // Reflect the actual delivered amount from the outcome echo so "Last bolus" shows the
                // just-delivered value immediately (e.g. 0.05), not the previous bolus.
                if (status != null && (status.equals("delivered") || status.equals("cancelled"))) {
                    var du = fltRange(data["deliveredUnits"], 0.0, 100.0); if (du != null) { lastBolus = du; }
                }
            }
        }
    }
    const STATUS_TOKENS = ["delivering", "delivered", "cancelled", "cancelling", "failed", "unknown"];

    function isNum(v) as Lang.Boolean {
        return v instanceof Lang.Number || v instanceof Lang.Float || v instanceof Lang.Double;
    }
    function numOrNull(v) as Lang.Number? { return isNum(v) ? v.toNumber() : null; }
    function flt(v) as Lang.Float? { return isNum(v) ? v.toFloat() : null; }

    // GA-09: inbound-payload validation. A malformed / hostile phone message must not poison global
    // state — every physiological field is bounds- and finiteness-checked, strings are length-capped,
    // and nested arrays are size-capped with per-element validation. A rejected field returns null so
    // the caller KEEPS the last good value rather than adopting garbage.
    function isFiniteNum(v) as Lang.Boolean {
        if (!isNum(v)) { return false; }
        return v == v && v < 1.0e12 && v > -1.0e12;   // v==v rejects NaN; the bounds reject ±Inf / absurd
    }
    function numRange(v, lo as Lang.Number, hi as Lang.Number) as Lang.Number? {
        if (!isFiniteNum(v)) { return null; }
        var n = v.toNumber();
        return (n < lo || n > hi) ? null : n;
    }
    function fltRange(v, lo as Lang.Float, hi as Lang.Float) as Lang.Float? {
        if (!isFiniteNum(v)) { return null; }
        var f = v.toFloat();
        return (f < lo || f > hi) ? null : f;
    }
    function strCap(v, max as Lang.Number) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        var s = v as Lang.String;
        return (s.length() > max) ? s.substring(0, max) : s;
    }
    const TREND_TOKENS = ["flat", "up", "down", "upup", "downdown", "up45", "down45", ""];
    function validTrend(v) as Lang.String? {
        if (!(v instanceof Lang.String)) { return null; }
        return containsStr(TREND_TOKENS, v as Lang.String) ? v : null;
    }
    // Keep the newest ≤288 finite readings in [0,600]; drop everything else.
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
    // E5: keep the newest ≤288 (mg/dL, epoch) PAIRS where BOTH the reading is finite in [0,600] AND
    // the epoch is a finite Number > 0. Sanitizing as PAIRS (never independently) is the whole point:
    // an out-of-range reading drops its epoch too, so a surviving reading can never shift onto the
    // wrong timestamp. Callers pass equal-length raw arrays. Returns [historyOut, epochsOut], always
    // of equal size (the aligned-pair invariant). Reuses numRange/isFiniteNum.
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
    function sanitizeAlerts(arr as Lang.Array) as Lang.Array {
        var out = [];
        var lim = (arr.size() > 50) ? 50 : arr.size();
        for (var k = 0; k < lim; k += 1) {
            var e = arr[k];
            if (e instanceof Lang.Dictionary
                && isNum(e["id"]) && isNum(e["kind"]) && (e["title"] instanceof Lang.String)) {
                out.add({ "id" => e["id"], "kind" => e["kind"], "title" => strCap(e["title"], 80) });
            }
        }
        return out;
    }

    // Alert identity = kind + "-" + id. This is the (kind, id) pair the dismiss path already keys on
    // (see AlertConfirmDelegate / RemoteComm.dismissAlert) — NOT a new schema field. It's the stable
    // handle the notifier uses to tell a genuinely NEW alert from a re-fetch of one already surfaced.
    function alertIdentity(a as Lang.Dictionary) as Lang.String {
        return a["kind"].toString() + "-" + a["id"].toString();
    }

    // The set of alert identities the wearer has already been notified about, persisted (as an Array of
    // identity strings) so it survives background↔foreground transitions and a cold launch — a NEW
    // alert is one whose identity isn't in this set. GA: a plain count comparison missed an alarm that
    // replaced another at the same count and re-fired on every reshuffle; identity tracking fixes both.
    const KEY_SEEN_ALERTS = "seenAlerts";
    function loadSeenAlerts() as Lang.Array {
        var s = Storage.getValue(KEY_SEEN_ALERTS);
        return (s instanceof Lang.Array) ? s : [];
    }
    function saveSeenAlerts(seen as Lang.Array) as Void {
        Storage.setValue(KEY_SEEN_ALERTS, seen);
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
