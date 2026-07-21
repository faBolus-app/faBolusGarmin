using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

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

    // One labeled row per detail-field id (from the phone-mirrored AppState.detailsOrder), or null
    // for an unknown id. Mirrors the phone Details card / Apple-Watch Details page.
    private function detailRow(id as Lang.String) as Lang.String? {
        if (id.equals("iob")) { return "Active Insulin: " + f2(AppState.iob) + " U"; }
        if (id.equals("reservoir")) { return "Reservoir: " + f2(AppState.reservoir) + " U"; }
        if (id.equals("battery")) { return "Battery: " + n0(AppState.battery) + "%"; }
        if (id.equals("cgm")) { return "CGM: " + (AppState.glucose != null ? AppState.glucose.toString() + " mg/dL" : "--"); }
        if (id.equals("lastBolus")) { return "Last bolus: " + f2(AppState.lastBolus) + " U"; }
        if (id.equals("carbRatio")) { return "Carb ratio: " + (AppState.carbRatio > 0.0 ? AppState.carbRatio.format("%.0f") + " g/U" : "--"); }
        if (id.equals("isf")) { return "ISF: " + (AppState.isf > 0 ? AppState.isf.toString() + " mg/dL/U" : "--"); }
        if (id.equals("target")) { return "Target: " + (AppState.targetBg > 0 ? AppState.targetBg.toString() + " mg/dL" : "--"); }
        if (id.equals("maxBolus")) { return "Max bolus: " + f2(AppState.maxUnits) + " U"; }
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
