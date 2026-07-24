using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Lang;

// Publishes the current blood glucose to complication index 0 (see
// resources-complications/complications/complications.xml). Publishes a NUMERIC :value (matching the
// complication's numeric <range>, so Face It can range-color it) with the trend in the :unit slot as a
// Latin-safe arrow (from the phone's direction token; Unicode arrow glyphs fail to render on many faces).
// LIMITATION (audit): a numeric/ranged complication cannot render "--", so when a reading goes stale we
// drop the arrow but the last NUMBER still shows (and keeps its range color). The complication also
// refreshes only while the app is foreground (15 s) or via throttled background temporal events (≥5 min,
// system-coalesced), and not at all while the phone/BLE is unreachable — so it can lag the CGM and does
// NOT itself flag staleness. The in-app screens (and the "value + trend" string display mode) are the
// staleness-aware surfaces.
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
    // whose Connect IQ level (< 4.1) lacks the Complications module (e.g. Forerunner 245, CIQ 3.3) —
    // referencing an absent module is a compile error, so those builds get the no-op stub below via
    // `<device>.excludeAnnotations = complications` in the jungle.
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
        // range floor). Stale keeps the last numeric value but drops the arrow (numeric can't render "--").
        try {
            // GA-08: in "stringTrend" mode the surface is the STRING shortLabel — it carries the value +
            // Latin trend arrow, and "--" when stale (the one place we can honestly show staleness, since
            // the numeric :value can't render "--"). In "numericColor" mode the label keeps the last number
            // and we attach range breakpoints for the face to color by.
            var stringMode = AppState.complicationDisplay.equals("stringTrend");
            var label;
            if (stringMode) {
                label = stale ? "--" : (value.toString() + arrow);
            } else {
                label = stale ? value.toString() : (value.toString() + arrow);
            }
            var params = { :value => value, :unit => (stale ? "" : arrow), :shortLabel => label };
            if (!stringMode) {
                params[:ranges] = [0, 70, 180, 250, 400];   // glucose range breakpoints (mg/dL)
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
