using Toybox.Complications;
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
        try {
            if (AppState.complicationDisplay.equals("stringTrend")) {
                // Plain string "124 ^" (no range color). For faces that don't range-color.
                var text = stale ? "--" : (value.toString() + arrow);
                Complications.updateComplication(COMP_ID, { :value => text, :shortLabel => text });
            } else {
                // numericColor (default): numeric :value → Face It range-colors it via <range>; the
                // Latin trend arrow goes in :unit (appended after the value, e.g. "124 ^"). A String
                // value + :unit is the invalid combo that froze before — a real Number is required.
                // Stale: keep the last numeric value but drop the arrow (numeric complications can't
                // show "--").
                if (stale) {
                    Complications.updateComplication(COMP_ID, { :value => value, :unit => "", :shortLabel => value.toString() });
                } else {
                    Complications.updateComplication(COMP_ID, { :value => value, :unit => arrow, :shortLabel => value.toString() + arrow });
                }
            }
        } catch (e) {
            // Older firmware / complication not registered yet — ignore.
        }
    }

    function publishFromState() as Void {
        remember(AppState.glucose, AppState.trend, AppState.readingEpoch);
        publish(AppState.glucose, AppState.trend, AppState.readingEpoch);
    }
}
