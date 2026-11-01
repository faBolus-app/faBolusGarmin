using Toybox.Graphics as Gfx;
using Toybox.Lang;
using Toybox.Test;

// How values are written, ported from the old app's tests with their expectations, and how staleness
// shows, now judged from each value's measurement time.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module DisplayTest {
    const NOW = Support.NOW;

    (:test)
    function mgdlIsAPlainInteger(logger as Test.Logger) as Lang.Boolean {
        var spread = [54, 70, 100, 124, 180, 250, 400];
        for (var i = 0; i < spread.size(); i += 1) {
            var v = spread[i] as Lang.Number;
            Support.eq(Display.glucose(v, "mgdl"), v.toString());
        }
        return true;
    }

    (:test)
    function mmolMatchesThePhone(logger as Test.Logger) as Lang.Boolean {
        Support.eq(Display.glucose(54, "mmol"), "3.0");
        Support.eq(Display.glucose(70, "mmol"), "3.9");
        Support.eq(Display.glucose(100, "mmol"), "5.5");
        Support.eq(Display.glucose(124, "mmol"), "6.9");
        Support.eq(Display.glucose(180, "mmol"), "10.0");
        Support.eq(Display.glucose(250, "mmol"), "13.9");
        Support.eq(Display.glucose(400, "mmol"), "22.2");
        Support.eq(Display.glucoseUnit("mgdl"), "mg/dL");
        Support.eq(Display.glucoseUnit("mmol"), "mmol/L");
        Support.eq(Display.isfUnit("mmol"), "mmol/L/U");
        return true;
    }

    (:test)
    function rangeColorsAtTheEdges(logger as Test.Logger) as Lang.Boolean {
        Support.eq(Display.rangeColor(69), Gfx.COLOR_RED);
        Support.eq(Display.rangeColor(70), Gfx.COLOR_GREEN);
        Support.eq(Display.rangeColor(180), Gfx.COLOR_GREEN);
        Support.eq(Display.rangeColor(181), Gfx.COLOR_YELLOW);
        Support.eq(Display.rangeColor(250), Gfx.COLOR_YELLOW);
        Support.eq(Display.rangeColor(251), Gfx.COLOR_ORANGE);
        return true;
    }

    // The constants the watch keeps a copy of are the phone's, as contract/shared_constants.json records them.
    (:test)
    function sharedConstantsAreThePhones(logger as Test.Logger) as Lang.Boolean {
        var c = Support.fixture(Rez.JsonData.shared_constants);
        var bands = c["glucoseBands"] as Lang.Dictionary;
        Support.eq(Display.GLUCOSE_LOW, bands["low"] as Lang.Object?);
        Support.eq(Display.GLUCOSE_HIGH, bands["high"] as Lang.Object?);
        Support.eq(Display.GLUCOSE_VERY_HIGH, bands["veryHigh"] as Lang.Object?);
        var plausible = c["plausibleGlucose"] as Lang.Dictionary;
        Support.eq(Calculator.GLUCOSE_MIN, plausible["min"] as Lang.Object?);
        Support.eq(Calculator.GLUCOSE_MAX, plausible["max"] as Lang.Object?);
        return true;
    }

    // The complication's label: the reading and its arrow while current, "--" once stale.
    (:test)
    function complicationLabels(logger as Test.Logger) as Lang.Boolean {
        Support.eq(BgComplication.glucoseLabel("124", "^", true), "--");
        Support.eq(BgComplication.glucoseLabel("124", "^", false), "124 ^");
        Support.eq(BgComplication.glucoseLabel("124", "", false), "124");
        Support.eq(BgComplication.glucoseLabel(Display.glucose(124, "mmol"), "x", false), "6.9 x");
        Support.eq(BgComplication.arrowFor("up45"), "/");
        Support.eq(BgComplication.arrowFor("downdown"), "vv");
        Support.eq(BgComplication.arrowFor("bogus"), "");
        Support.eq(BgComplication.arrowFor(null), "");
        return true;
    }

    // The glucose complication: the number in mg/dL with its arrow while current; with mmol/L only the label,
    // because the complication's colour bands are mg/dL; nothing once stale.
    (:test)
    function theGlucoseComplicationNeverShowsAWrongUnitNumber(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var mgdl = BgComplication.glucoseEntry(NOW);
        Support.eq(mgdl[0] as Lang.Object?, 142);
        Support.eq(mgdl[1] as Lang.Object?, "142 /");
        Support.eq(mgdl[2] as Lang.Object?, "/");
        var config = Support.payloadOf(Rez.JsonData.fixture_config);
        var glucose = config["glucose"] as Lang.Dictionary;
        glucose["unit"] = "mmol";
        Test.assert(Prefs.accept(config, NOW));
        var mmol = BgComplication.glucoseEntry(NOW);
        Support.eq(mmol[0] as Lang.Object?, null);
        Support.eq(mmol[1] as Lang.Object?, "7.9 /");
        Support.eq(mmol[2] as Lang.Object?, null);
        var stale = BgComplication.glucoseEntry(NOW + 360 - 80 + 1);
        Support.eq(stale[0] as Lang.Object?, null);
        Support.eq(stale[1] as Lang.Object?, "--");
        return true;
    }

    // The slots show stale once their values are older than the phone's windows (IOB's own, the pump status
    // window for the rest), so a phone that went away shows on the face.
    (:test)
    function slotsGoStaleAfterThePhonesWindows(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        // Names on, as the user may set them.
        var named = Support.payloadOf(Rez.JsonData.fixture_config);
        var namedComplication = named["complication"] as Lang.Dictionary;
        namedComplication["labels"] = true;
        Test.assert(Prefs.accept(named, NOW));
        var fresh = BgComplication.slot("iob", NOW);
        Support.eq(fresh[1] as Lang.Object?, "IOB 1.25");
        Support.eq(fresh[2] as Lang.Object?, "U");
        Test.assert(Support.isSet(fresh[0] as Lang.Object?));
        // IOB was measured 20 s before the status; past the phone's 5 minutes it shows as unknown, not as
        // current, while the reservoir, measured 40 s before, still shows until 15 minutes.
        Support.eq(BgComplication.slot("iob", NOW + 300 - 20)[1] as Lang.Object?, "IOB 1.25");
        var later = BgComplication.slot("iob", NOW + 300 - 20 + 1);
        Support.eq(later[0] as Lang.Object?, null);
        Support.eq(later[1] as Lang.Object?, "--");
        Support.eq(BgComplication.slot("reservoir", NOW + 900 - 40)[1] as Lang.Object?, "Res 143");
        Support.eq(BgComplication.slot("reservoir", NOW + 900 - 40 + 1)[1] as Lang.Object?, "--");
        Support.eq(BgComplication.slot("battery", NOW)[1] as Lang.Object?, "Bat 72%");
        Support.eq(BgComplication.slot("reservoir", NOW)[1] as Lang.Object?, "Res 143");
        Support.eq(BgComplication.slot("reservoir", NOW)[0] as Lang.Object?, 143);
        Support.eq(BgComplication.slot("basal", NOW)[1] as Lang.Object?, "Basal 0.85");
        // With the names off, the default, the value alone.
        var config = Support.payloadOf(Rez.JsonData.fixture_config);
        var complication = config["complication"] as Lang.Dictionary;
        complication["labels"] = false;
        Test.assert(Prefs.accept(config, NOW));
        Support.eq(BgComplication.slot("iob", NOW)[1] as Lang.Object?, "1.25 U");
        Support.eq(BgComplication.slot("reservoir", NOW)[1] as Lang.Object?, "143 U");
        Support.eq(BgComplication.slot("battery", NOW)[1] as Lang.Object?, "72%");
        Support.eq(BgComplication.slot("basal", NOW)[1] as Lang.Object?, "0.85 U/h");
        // Unknown is "--", never zero.
        Support.fresh();
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_minimal), NOW);
        var unknown = BgComplication.slot("reservoir", NOW);
        Support.eq(unknown[0] as Lang.Object?, null);
        Support.eq(unknown[1] as Lang.Object?, "--");
        return true;
    }

    // Glucose goes grey after the stale window, by its measurement time, and is hidden after the delay.
    (:test)
    function glucoseStalenessIsFromItsMeasurementTime(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        // Measured 80 s before the status: stale 280 s after it arrived.
        Test.assert(!Glucose.stale(NOW + 280));
        Test.assert(Glucose.stale(NOW + 281));
        Test.assert(Glucose.trend(NOW + 281) == null);
        Test.assert(!Glucose.isHidden(NOW + 10000));
        Support.eq(Glucose.text(NOW + 10000), "142");
        var hide = Support.payloadOf(Rez.JsonData.fixture_config);
        var hg = hide["glucose"] as Lang.Dictionary;
        hg["hideDelayMinutes"] = 10;
        Prefs.accept(hide, NOW);
        Test.assert(!Glucose.isHidden(NOW + 880));
        Test.assert(Glucose.isHidden(NOW + 881));
        Support.eq(Glucose.text(NOW + 881), "--");
        return true;
    }

    // A watch clock behind the phone's doesn't make a reading look fresher: its age is the phone's view
    // plus the time since it arrived, never less.
    (:test)
    function clockSkewDoesntMakeAReadingFresher(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW);
        Support.eq(Status.ageOf("glucose", NOW - 3600), 80);
        Support.eq(Status.ageOf("glucose", NOW + 60), 140);
        return true;
    }

    (:test)
    function agesRead(logger as Test.Logger) as Lang.Boolean {
        Support.eq(Display.ago(null), "");
        Support.eq(Display.ago(30), "now");
        Support.eq(Display.ago(180), "3 min ago");
        Support.eq(Display.ago(3600), "1h ago");
        Support.eq(Display.ago(3840), "1h 4m ago");
        return true;
    }

    (:test)
    function detailsRowsAreEvenlySpaced(logger as Test.Logger) as Lang.Boolean {
        Test.assert((DetailsView.rowY(1, 0, 0.28, 0.80) - 0.54).abs() < 0.0005);
        Test.assert((DetailsView.rowY(3, 1, 0.0, 1.0) - 0.5).abs() < 0.0005);
        Test.assert((DetailsView.rowY(2, 1, 0.28, 0.80) - 0.80).abs() < 0.0005);
        return true;
    }

    (:test)
    function detailsRowsShowWhatTheStatusHas(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Support.eq(DetailsView.row("iob", NOW), "Active Insulin: 1.25 U");
        Support.eq(DetailsView.row("carbRatio", NOW), "Carb ratio: 7.5 g/U");
        Support.eq(DetailsView.row("battery", NOW), "Battery: 72%");
        Support.eq(DetailsView.row("maxBasal", NOW), "Basal 0.85/3.00 U/hr · 28%");
        Support.eq(DetailsView.row("iob", NOW + 1000), "Active Insulin: 1.25 U (old)");
        // The calculator's settings (read 20 s before the status) are old past the phone's 15-minute therapy
        // window, and the basal (40 s before) past its pump status window, as IOB is past its own.
        Support.eq(DetailsView.row("carbRatio", NOW + 880), "Carb ratio: 7.5 g/U");
        Support.eq(DetailsView.row("carbRatio", NOW + 881), "Carb ratio: 7.5 g/U (old)");
        Support.eq(DetailsView.row("isf", NOW + 1000), "ISF: 40 mg/dL/U (old)");
        Support.eq(DetailsView.row("target", NOW + 1000), "Target: 110 mg/dL (old)");
        Support.eq(DetailsView.row("maxBolus", NOW + 1000), "Max bolus: 25.00 U (old)");
        Support.eq(DetailsView.row("maxBasal", NOW + 1000), "Basal 0.85/3.00 U/hr · 28% (old)");
        // The golden status's auto-correction was 45 minutes before it was sent, and ages from there.
        Support.eq(DetailsView.row("autoCorrection", NOW), "Auto-correction: 45 min ago");
        Support.eq(DetailsView.row("autoCorrection", NOW + 900), "Auto-correction: 1h ago");
        Support.fresh();
        Support.eq(DetailsView.row("reservoir", NOW), "Reservoir: --");
        Support.eq(DetailsView.row("maxBasal", NOW), null);
        // None known: the row is left out, not shown as "--".
        Support.eq(DetailsView.row("autoCorrection", NOW), null);
        return true;
    }

    // An alert card offers Clear from what the latest status says, not from the copy it was opened with.
    (:test)
    function anAlertCardClearsOnlyWhatTheStatusStillOffers(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var low = Alerts.current("pump.alert.2") as Lang.Dictionary;
        var card = new AlertNoticeView(low);
        Test.assert(card.clearable());
        Test.assert(!(new AlertNoticeView(Alerts.current("app.pumpDisconnected") as Lang.Dictionary)).clearable());
        // The next status no longer lets a remote clear it.
        var p = Support.payloadOf(Rez.JsonData.fixture_status);
        var first = (p["alerts"] as Lang.Array)[0] as Lang.Dictionary;
        first["dismissable"] = false;
        Test.assert(Status.accept(p, NOW + 5));
        Test.assert(!card.clearable());
        // And once it's gone, there's nothing to clear.
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_minimal), NOW + 10));
        Support.eq(Alerts.current("pump.alert.2"), null);
        Test.assert(!card.clearable());
        return true;
    }

    (:test)
    function appVersionLabel(logger as Test.Logger) as Lang.Boolean {
        var expected = "App: " + AppVersion.NAME + " · " + AppRevision.SHORT + (AppRevision.DIRTY ? "+" : "");
        Support.eq(AppVersion.label(), expected);
        Support.eq(AppVersion.labelFor("0.0.0", "abcdef0", true), AppVersion.labelFor("0.0.0", "abcdef0", false) + "+");
        Test.assert(AppVersion.labelFor("100.200.300", "abcdef0", true).length() <= 28);
        return true;
    }

    (:test)
    function chartGridlines(logger as Test.Logger) as Lang.Boolean {
        Test.assert(Support.same(CgmView.gridlines(40, 300), [100, 200]));
        Test.assert(Support.same(CgmView.gridlines(50, 250), [100, 200]));
        Test.assert(Support.same(CgmView.gridlines(40, 150), [50, 100]));
        return true;
    }

    (:test)
    function clockText(logger as Test.Logger) as Lang.Boolean {
        Test.assert(Support.same(ClockView.digitalText(0, 5, false), ["12:05", "AM"]));
        Test.assert(Support.same(ClockView.digitalText(13, 0, false), ["1:00", "PM"]));
        Test.assert(Support.same(ClockView.digitalText(13, 0, true), ["13:00", ""]));
        return true;
    }
}
