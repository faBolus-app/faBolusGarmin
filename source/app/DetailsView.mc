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

    // Phase 09.15 T1-3/T1-4 (D-08, epoch-not-age convention) — elapsed minutes computed HERE at draw
    // time from an immutable source epoch, never transmitted as a pre-computed age (mirrors
    // ciqSuspendElapsedMinutes's identical pattern, kept as a separate generic helper so that
    // existing function stays byte-unchanged). Clamped to 0 for a clock-skew/future stamp.
    private function elapsedMinutesSince(epoch as Lang.Number?) as Lang.Number {
        if (epoch == null) { return 0; }
        var mins = (Time.now().value() - (epoch as Lang.Number)) / 60;
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
        // Phase 09.15 T1-3 (D-01/D-08, SP-5 fail-closed) — a PRINTED row (Garmin has no VoiceOver),
        // omitted entirely (never "--") unless an auto-correction has actually been seen — no recent
        // auto-correction is the common/expected case, not an error (matches ciqZone's convention).
        if (id.equals("autoCorrection")) {
            if (AppState.lastAutoCorrectionEpochSec != null) {
                var mins = elapsedMinutesSince(AppState.lastAutoCorrectionEpochSec);
                return "Auto-correction: " + mins.toString() + "m ago";
            }
            return null;
        }
        // Phase 09.15 T1-4 (D-01/D-08) — remote MARKER only (no on-watch/Garmin timeline). "CIQ" (not
        // the full "Control-IQ") to stay within the ~28-char DetailsView.detailRow budget at
        // FONT_XTINY, matching the ciqSuspend row's precedent. Never speculates WHY (D-06
        // guardrail #6).
        if (id.equals("couldNotDeliver")) {
            if (AppState.ciqLastCouldNotDeliverEpochSec != null) {
                var mins = elapsedMinutesSince(AppState.ciqLastCouldNotDeliverEpochSec);
                return "CIQ couldn't deliver (" + mins.toString() + "m)";
            }
            return null;
        }
        // Phase 09.15 T1-8 (D-03, D-09.4 TEXT-ONLY — no drawn bar) — the honest "% of your configured
        // max basal rate" text row, computed LOCALLY from AppState.basalRate/maxBasalUnitsPerHour
        // (D-08: never a pre-rendered percentage on the wire). Row omitted entirely (never "0%"/"--")
        // when the configured max is unknown/absent (D-03(v) fail-closed) — mirrors ciqZone's
        // row-absent convention. The label ALWAYS contains "Basal" and ALWAYS shows both the current
        // and configured max U/hr alongside the % (D-03(i)/(ii)) — this is faBolus's OWN construct,
        // Tandem ships no such gauge, NEVER a Control-IQ figure. "%.2f" (not "%.0f") to match the
        // Copywriting Contract's exact U/hr precision; typical values ("Basal 0.85/1.60 U/hr · 53%",
        // 26 chars) hold well within the ~28-char FONT_XTINY budget — only the extreme, unrealistic
        // edge of current==max==the pump's absolute ceiling (15.00 U/hr) reaches 27-29 chars, matching
        // the ciqSuspend row's own documented over-budget precedent above.
        if (id.equals("maxBasal")) {
            var fraction = AppState.maxBasalFraction();
            if (fraction == null) { return null; }
            var pct = (fraction * 100.0 + 0.5).toNumber();
            var maxV = AppState.maxBasalUnitsPerHour as Lang.Float;
            return "Basal " + AppState.basalRate.format("%.2f") + "/" + maxV.format("%.2f")
                 + " U/hr · " + pct.toString() + "%";
        }
        // Phase 09.15 T1-9 (D-01/D-08, D-09.5) — the compact single-line fact (mode + effect fact +
        // exercise timer, NO window text — D-09.5 explicit scope): "Sleep — AutoBolus off" /
        // "Exercise — ends 4:20", a PRINTED row (Garmin has no VoiceOver). Row omitted entirely
        // (never a "Normal mode" row) unless the pump's own live controlIQMode is genuinely
        // Sleep/Exercise AND (Exercise only) the timer is known — mirrors
        // AppState.ciqActivityCompactLine's own fail-closed guards exactly.
        if (id.equals("sleepExercise")) {
            return AppState.ciqActivityCompactLine();
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
