using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Lang;

// Publishes the current blood glucose to complication index 0 (see
// resources/complications/complications.xml). The value is a String like "124 ^" so Face It /
// CIQ faces render it verbatim; the trend is stored as a direction token (from the phone) and
// converted to a Latin-safe arrow here, since complication text can't rely on Unicode glyphs.
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

    // Publish the reading. Falls back to the persisted value/token/epoch when bg is null. A
    // reading older than 6 minutes is shown as "--" so a stale value is never displayed.
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

        var stale = (ep <= 0) || ((Time.now().value() - ep) > 360);
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
        // Step 2 — best-effort enrichment (trend arrow + optional color bands + label), in its OWN
        // try so a param a given watch rejects can't wipe the value written in step 1. numericColor
        // (default) adds the color :ranges; stringTrend omits them (no color). Stale keeps the last
        // numeric value but drops the arrow (a numeric complication can't render "--").
        try {
            var label = stale ? value.toString() : value.toString() + arrow;
            var params = { :value => value, :unit => (stale ? "" : arrow), :shortLabel => label };
            if (!AppState.complicationDisplay.equals("stringTrend")) {
                params[:ranges] = [0, 70, 180, 250, 400];   // glucose color bands (mg/dL)
            }
            Toybox.Complications.updateComplication(COMP_ID, params);
        } catch (e) {
            // Enrichment rejected on this firmware — the numeric value from step 1 still stands.
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
