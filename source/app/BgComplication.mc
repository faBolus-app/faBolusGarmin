using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Lang;

// Publishes the current blood glucose to complication index 0 (see
// resources-complications/complications/complications.xml). Publishes a NUMERIC :value (matching the
// complication's numeric <range>, so Face It can range-color it) with the trend in the :unit slot as a
// Latin-safe arrow (from the phone's direction token; Unicode arrow glyphs fail to render on many faces).
// LIMITATION (audit): a numeric/ranged complication cannot render "--" in its numeric :value slot, so a
// stale reading keeps its last NUMBER there — the pure-numeric display is STRUCTURALLY unable to flag
// staleness (a stale glucose can look current). P16 §1.3 (fail-graceful): the shortLabel TEXT is the one
// complication sub-surface that can carry a marker, so staleness is made honest there in BOTH display
// modes (see shortLabelFor) — string-rendering faces can no longer show a stale reading as current.
// R2-18 (audit): when the reading is stale we ALSO drop the numeric :ranges breakpoints (see
// pushComplication), so a range-coloring face no longer paints the frozen last number with an in-range
// (or any) color cue — removing a SECOND misleading "current" signal on top of the raw number. The
// residual structural limit is now only a face that renders the bare numeric :value with no face-side
// coloring and ignores the shortLabel — unavoidable at the publisher and stays documented here. The
// complication also refreshes only while the app is
// foreground (15 s) or via throttled background temporal events (≥5 min, system-coalesced), and not at
// all while the phone/BLE is unreachable — so it can lag the CGM. The in-app screens remain the
// fully staleness-aware surfaces (grayed value + called-out age).
module BgComplication {
    const COMP_ID = 0;
    const KEY_BG = "bg";
    const KEY_TREND = "trend";   // direction token: flat/up/down/upup/downdown/up45/down45
    const KEY_EPOCH = "bgEpoch"; // unix sec the BG was taken (for 6-min staleness)

    // Latin/ASCII trend arrow published inside the VALUE string. Face It / published complication
    // strings must use Latin characters (A-Z, a-z, 0-9, punctuation) — Unicode arrow glyphs (↑ → …)
    // fail to render on many faces, which (together with the numeric-<range> bug) is why BG showed 0.
    function arrowFor(token as Lang.String?) as Lang.String {
        if (token == null) { return ""; }
        if (token.equals("up")) { return "^"; }
        if (token.equals("upup")) { return "^^"; }
        if (token.equals("up45")) { return "/"; }
        if (token.equals("down")) { return "v"; }
        if (token.equals("downdown")) { return "vv"; }
        if (token.equals("down45")) { return "\\"; }
        if (token.equals("flat")) { return "->"; }
        return "";
    }

    // P16 §1.3 (fail-graceful): compute the complication shortLabel string. This is the ONE complication
    // sub-surface that can carry text, so it is where staleness is made honest for string-rendering faces:
    //   • stringTrend  mode → "--" when stale (the value is replaced), else "<value><arrow>".
    //   • numericColor mode → keeps "<value>" so a face can still range-color the number, but appends an
    //     explicit " old" marker when stale so a string-rendering face cannot show a stale reading as
    //     current. (The pure-NUMERIC :value display remains structurally unable to convey staleness — see
    //     the LIMITATION note above — so the honest marker lives here, in the text label.)
    // C5-03 (V-Audit): `value` renders here via `AppState.formatMgdl` — the SAME mg/dL→mmol funnel every
    // other Garmin glucose surface uses — so this text sub-surface honors the phone's selected unit
    // (mgdl/mmol) instead of a raw `.toString()`. This makes `shortLabelFor` depend on the AppState
    // module's `glucoseUnit` (no longer purely a function of its own parameters, though it still has no
    // Complications-module dependency and remains unit-testable in the P6 harness — AppState.mc imports
    // only Lang/Graphics/Math/Time/System/Storage). The `value` PARAMETER passed in — and the numeric
    // `:value`/`:ranges` slots this label is paired with in pushComplication — stay raw mg/dL Numbers
    // throughout; only the rendered text changes. (The numeric slot itself cannot show a converted mmol
    // float: a `String` :value regresses the complication to its range floor — see the "MUST be a
    // Number" comment in pushComplication below — so unit conversion is fixable ONLY on this text half,
    // per C5-03's own finding.)
    function shortLabelFor(value as Lang.Number, arrow as Lang.String, stale as Lang.Boolean,
                           stringMode as Lang.Boolean) as Lang.String {
        var display = AppState.formatMgdl(value);
        if (stringMode) {
            return stale ? "--" : (display + arrow);
        }
        return stale ? (display + " old") : (display + arrow);
    }

    function remember(bg as Lang.Number?, token as Lang.String, epoch as Lang.Number) as Void {
        if (bg != null) { Storage.setValue(KEY_BG, bg); }
        Storage.setValue(KEY_TREND, token);
        if (epoch > 0) { Storage.setValue(KEY_EPOCH, epoch); }
    }

    // Publish the reading. Falls back to the persisted value/token/epoch when bg is null. When the
    // reading is stale (older than the phone-synced staleSec, default 6 min) the trend arrow is dropped;
    // the numeric value itself still shows (see the LIMITATION above — numeric complications can't do "--").
    function publish(bg as Lang.Number?, token as Lang.String?, epoch as Lang.Number) as Void {
        if (!(Toybox has :Complications)) { return; }
        var value = bg;
        var tok = token;
        var ep = epoch;
        if (value == null) {
            value = Storage.getValue(KEY_BG) as Lang.Number?;
            tok = Storage.getValue(KEY_TREND) as Lang.String?;
            var se = Storage.getValue(KEY_EPOCH); ep = (se == null) ? 0 : se;
        }
        if (value == null) { return; }

        var stale = (ep <= 0) || ((Time.now().value() - ep) > AppState.staleSec);
        var arrow = stale ? "" : arrowFor(tok);
        pushComplication(value, arrow, stale);
    }

    // Actual complication write. Split out and annotated so it can be compiled OUT for devices
    // whose Connect IQ level lacks the Complications module (module @since 4.2.0; e.g. Forerunner 245,
    // CIQ 3.3) — referencing an absent module is a compile error, so those builds get the no-op stub
    // below via `<device>.excludeAnnotations = complications` in the jungle.
    (:complications)
    function pushComplication(value as Lang.Number, arrow as Lang.String, stale as Lang.Boolean) as Void {
        // The complication resource declares a numeric <range>, so :value MUST be a Number (a String
        // value made faces fall back to the range floor 0 — the original "reads 0" bug).
        //
        // Step 1 — guaranteed minimal update: write ONLY the numeric value. This is the field every
        // firmware accepts, so the current BG always lands even if the richer params below are
        // rejected. Previously everything was one call, so a single unsupported param (:unit/:ranges/
        // :shortLabel on some firmware) threw and the silent catch left the complication at 0.
        try {
            Toybox.Complications.updateComplication(COMP_ID, { :value => value });
        } catch (e) {
            return;   // Complications not registered yet / unsupported — nothing further to try.
        }
        // Step 2 — enrichment: trend arrow + optional range breakpoints + label. Resolved against the
        // SDK's own type source (`Sdks/.../bin/api.mir`, `Complications.Data` typedef line ~8407):
        // the accepted keys are exactly :value, :unit (SINGULAR), :shortLabel, :ranges. `:units` (plural)
        // appears ONLY in a typo-ridden Core-Topics doc example and is NOT an SDK key — so no cascade is
        // needed. Unknown keys are ignored at runtime (not thrown); the ONLY documented throw is
        // OperationNotAllowedException, when COMP_ID isn't yet owned by this app. `:ranges` are numeric
        // breakpoints the CONSUMER (Face It / watch face) colors by — a publisher can't set the color
        // itself. The real "reads 0" fix is the NUMERIC :value in step 1 (a String value fell back to the
        // range floor). Stale keeps the last numeric value but drops the arrow (numeric can't render "--")
        // and, in numericColor mode, drops the :ranges color cue too (R2-18, below).
        try {
            // GA-08 / P16 §1.3: in "stringTrend" mode the surface is the STRING shortLabel — it carries
            // the value + Latin trend arrow, and "--" when stale. In "numericColor" mode the shortLabel
            // keeps the last number (so the face can range-color it) but appends an explicit stale marker,
            // and we attach range breakpoints for the face to color by ONLY while the reading is fresh
            // (R2-18: a stale number drops :ranges so it loses the misleading in-range color cue).
            // shortLabelFor makes staleness honest in BOTH modes; the numeric :value slot stays as the last
            // reading (a numeric complication cannot render "--" there — the documented structural limit).
            var stringMode = AppState.complicationDisplay.equals("stringTrend");
            var label = shortLabelFor(value, arrow, stale, stringMode);
            var params = { :value => value, :unit => (stale ? "" : arrow), :shortLabel => label };
            if (!stringMode && !stale) {
                // R2-18 (V-Audit): attach the glucose range breakpoints ONLY when the reading is fresh. When
                // stale we drop :ranges so a range-coloring face can no longer paint the frozen last number
                // with an in-range (or any) color cue — a misleading "current & in-range" signal on a value
                // that is actually old. The numeric :value slot still keeps the last reading (a numeric
                // complication can't render "--"), but the stale " old" shortLabel marker + the now-uncolored
                // number are the honest surfaces. Same canonical mg/dL bands as AppState.rangeColor.
                params[:ranges] = [0, AppState.GLUCOSE_LOW, AppState.GLUCOSE_HIGH, AppState.GLUCOSE_VERY_HIGH, 400];
            }
            Toybox.Complications.updateComplication(COMP_ID, params);
        } catch (e) {
            // OperationNotAllowedException (id not owned yet) — retry value-only so the number still lands.
            try { Toybox.Complications.updateComplication(COMP_ID, { :value => value }); } catch (e2) {}
        }
    }

    // No-op stub for devices without the Complications module (excludeAnnotations = complications).
    (:nocomplications)
    function pushComplication(value as Lang.Number, arrow as Lang.String, stale as Lang.Boolean) as Void {
    }

    function publishFromState() as Void {
        remember(AppState.glucose, AppState.trend, AppState.readingEpoch);
        publish(AppState.glucose, AppState.trend, AppState.readingEpoch);
    }
}
