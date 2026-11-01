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

    // The complication's label: the reading and its arrow while current; once stale, " old" in the numeric
    // slot, which can't show "--", and "--" in string mode.
    (:test)
    function complicationLabels(logger as Test.Logger) as Lang.Boolean {
        Support.eq(BgComplication.glucoseLabel("124", "^", true, true), "--");
        Support.eq(BgComplication.glucoseLabel("124", "^", false, true), "124^");
        Support.eq(BgComplication.glucoseLabel("124", "^", true, false), "124 old");
        Support.eq(BgComplication.glucoseLabel("124", "^", false, false), "124^");
        Support.eq(BgComplication.glucoseLabel(Display.glucose(124, "mmol"), "^", true, false), "6.9 old");
        Support.eq(BgComplication.arrowFor("up45"), "/");
        Support.eq(BgComplication.arrowFor(null), "");
        return true;
    }

    // The slots show stale fifteen minutes after their values were measured, so a phone that went away
    // shows on the face.
    (:test)
    function slotsGoStaleAfterFifteenMinutes(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var fresh = BgComplication.slot("iob", NOW);
        Support.eq(fresh[1] as Lang.Object?, "1.25 U");
        Test.assert(Support.isSet(fresh[0] as Lang.Object?));
        // IOB was measured 20 s before the status; 15 minutes later it's old.
        var later = BgComplication.slot("iob", NOW + 900 - 20 + 1);
        Support.eq(later[1] as Lang.Object?, "1.25 U old");
        Support.eq(BgComplication.slot("battery", NOW)[1] as Lang.Object?, "72%");
        Support.eq(BgComplication.slot("reservoir", NOW)[1] as Lang.Object?, "143.50 U");
        Support.eq(BgComplication.slot("basal", NOW)[1] as Lang.Object?, "0.85 U/hr");
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
        Support.fresh();
        Support.eq(DetailsView.row("reservoir", NOW), "Reservoir: --");
        Support.eq(DetailsView.row("maxBasal", NOW), null);
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
        Test.assert(Support.same(ClockView.digitalText(0, 5, false), ["12:05", " AM"]));
        Test.assert(Support.same(ClockView.digitalText(13, 0, false), ["1:00", " PM"]));
        Test.assert(Support.same(ClockView.digitalText(13, 0, true), ["13:00", ""]));
        return true;
    }
}
