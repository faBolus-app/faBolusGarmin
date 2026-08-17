using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Time as Time;

// Secondary screen (swipe up from the glance): all the other relevant pump data from the phone.
// One metric per row, centered, generously spaced so nothing overlaps. "--" when unknown.
class DetailsView extends Ui.View {
    function initialize() { View.initialize(); }

    private function f2(v as Lang.Float) as Lang.String {
        return v < 0.0 ? "--" : v.format("%.2f");
    }
    private function n0(v as Lang.Number) as Lang.String {
        return v < 0 ? "--" : v.toString();
    }

    // Phase 09.15 T1-1 (D-01/D-08): Tandem's own zone word, capitalized exactly as the UI-SPEC
    // Copywriting Contract specifies — an explicit literal table (never a runtime case-transform),
    // so an out-of-set token can only ever fall through to "" and never render (D-06 guardrail #6).
    private function ciqZoneWord(token as Lang.String) as Lang.String {
        if (token.equals("increases")) { return "Increases"; }
        if (token.equals("decreases")) { return "Decreases"; }
        if (token.equals("maintains")) { return "Maintains"; }
        if (token.equals("stops")) { return "Stops"; }
        if (token.equals("delivers")) { return "Delivers"; }
        return "";
    }

    // Phase 09.15 T1-2 (D-08, epoch-not-age convention) — elapsed minutes computed HERE at draw time
    // from the immutable source epoch, never transmitted as a pre-computed age (mirrors
    // AppState.ageMinutes()'s identical pattern for the glucose reading). Clamped to 0 for a
    // clock-skew/future stamp rather than a negative elapsed time.
    private function ciqSuspendElapsedMinutes() as Lang.Number {
        var start = AppState.ciqSuspendStartEpochSec;
        if (start == null) { return 0; }
        var mins = (Time.now().value() - (start as Lang.Number)) / 60;
        return mins < 0 ? 0 : mins;
    }

    // One labeled row per detail-field id (from the phone-mirrored AppState.detailsOrder), or null
    // for an unknown id. Mirrors the phone Details card / Apple-Watch Details page.
    private function detailRow(id as Lang.String) as Lang.String? {
        if (id.equals("iob")) { return "Active Insulin: " + f2(AppState.iob) + " U"; }
        if (id.equals("reservoir")) { return "Reservoir: " + f2(AppState.reservoir) + " U"; }
        if (id.equals("battery")) { return "Battery: " + n0(AppState.battery) + "%"; }
        if (id.equals("cgm")) { return "CGM: " + (AppState.glucose != null ? AppState.displayGlucose() + " " + AppState.glucoseUnitLabel() : "--"); }
        if (id.equals("lastBolus")) { return "Last bolus: " + f2(AppState.lastBolus) + " U"; }
        if (id.equals("carbRatio")) { return "Carb ratio: " + (AppState.carbRatio > 0.0 ? AppState.carbRatio.format("%.0f") + " g/U" : "--"); }
        if (id.equals("isf")) { return "ISF: " + (AppState.isf > 0 ? AppState.formatMgdl(AppState.isf) + " " + AppState.isfUnitLabel() : "--"); }
        if (id.equals("target")) { return "Target: " + (AppState.targetBg > 0 ? AppState.formatMgdl(AppState.targetBg) + " " + AppState.glucoseUnitLabel() : "--"); }
        if (id.equals("maxBolus")) { return "Max bolus: " + f2(AppState.maxUnits) + " U"; }
        // Phase 09.15 T1-1 (D-01/D-08): a PRINTED word (Garmin has no VoiceOver, D-08 Garmin rule) —
        // row omitted entirely (never "--") unless Control-IQ is running and the zone is a known
        // token, never a stale/fabricated word (D-06 guardrail #5/#6).
        if (id.equals("ciqZone")) {
            if (AppState.controlIQEnabled && AppState.ciqZone != null) {
                var word = ciqZoneWord(AppState.ciqZone as Lang.String);
                return word.equals("") ? null : "Control-IQ: " + word;
            }
            return null;
        }
        // Phase 09.15 T1-2 (D-08/D-09.1, fail-closed cause-attribution) — a PRINTED row (Garmin has no
        // VoiceOver, D-08 Garmin rule), shown ONLY when the pump's OWN control-state has confirmed the
        // ACTIVE suspend is Control-IQ's. D-09.1 BINDING: Garmin has no generic deliverySuspended wire
        // signal to fall back to, so an absent/false attribution renders the row entirely ABSENT —
        // never a fabricated "Control-IQ paused" claim, and never a plain "Basal" row this watch never
        // had in the first place. "CIQ" (not the full "Control-IQ") to stay within the ~28-char
        // DetailsView.detailRow budget at FONT_XTINY — "Basal: Control-IQ paused (Nm)" runs 29-30+
        // chars, well past every other row's max (23); "Basal: CIQ paused (Nm)" holds at 22-23.
        if (id.equals("ciqSuspend")) {
            if (AppState.ciqSuspendedForLow != null && AppState.ciqSuspendedForLow &&
                AppState.ciqSuspendStartEpochSec != null) {
                var mins = ciqSuspendElapsedMinutes();
                return "Basal: CIQ paused (" + mins.toString() + "m)";
            }
            return null;
        }
        return null;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth(), h = dc.getHeight(), cx = w / 2;
        var vc = Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Gfx.FONT_XTINY,
                    AppState.connection.equals("") ? "Pump status" : AppState.connection, vc);

        // Rows in the central band (0.20..0.84) so the round edges never clip the text. Which rows +
        // order come from the phone (AppState.detailsOrder); the alerts summary is always appended.
        var alertCount = AppState.alerts.size();
        var rows = [];
        var order = AppState.detailsOrder;
        for (var i = 0; i < order.size(); i += 1) {
            var r = detailRow(order[i] as Lang.String);
            if (r != null) { rows.add(r); }
        }
        rows.add(alertCount > 0 ? ("Alerts: " + alertCount.toString()) : "No alerts");
        var top = 0.28, bottom = 0.80;
        var step = (bottom - top) / (rows.size() - 1);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var i = 0; i < rows.size(); i += 1) {
            dc.drawText(cx, h * (top + step * i), Gfx.FONT_XTINY, rows[i], vc);
        }
    }
}
