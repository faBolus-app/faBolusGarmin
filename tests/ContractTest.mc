using Toybox.Lang;
using Toybox.Test;

// Every golden fixture, as the phone's Swift wrote it: the ones the phone sends read into the values they
// carry, and the ones the watch sends are built exactly. contract/ is faBolus's at contract/PIN.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module ContractTest {
    const NOW = Support.NOW;

    (:test)
    function statusReads(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status), NOW));
        Support.eq(Status.sentAt(), NOW);
        Support.eq(Status.pumpLink(), "connected");
        Support.eq(Status.glucose(), 142);
        Support.eq(Status.trend(), "up45");
        Test.assert(!Status.glucoseFromBackup());
        Support.eq(Status.ageOf("glucose", NOW), 80);
        Support.eq(Status.field("iob", "mU"), 1250);
        Support.eq(Status.ageOf("iob", NOW), 20);
        Support.eq(Status.field("reservoir", "mU"), 143500);
        Support.eq(Status.field("battery", "percent"), 72);
        Test.assert(!Status.charging());
        Test.assert(!Status.basalSuspended());
        Support.eq(Status.field("basal", "mUPerHour"), 850);
        Support.eq(Status.field("lastBolus", "mU"), 3200);
        Support.eq(Status.field("calculator", "carbRatioMg"), 7500);
        Support.eq(Status.field("calculator", "isf"), 40);
        Support.eq(Status.field("calculator", "target"), 110);
        Support.eq(Status.field("calculator", "maxBolusMU"), 25000);
        Test.assert(Status.controlIQEnabled());
        Support.eq(Status.field("maxBasal", "mUPerHour"), 3000);
        Support.eq(Status.ageOf("lastAutoCorrection", NOW), 2700);
        Test.assert(Status.canBolus());
        Support.eq(Status.blockReason(), null);
        Support.eq(Status.remoteLimit(), 10000);
        Support.eq(Status.activeBolus(), null);
        var alerts = Status.alerts();
        Support.eq(alerts.size(), 2);
        var first = alerts[0] as Lang.Dictionary;
        Support.eq(first["id"] as Lang.Object?, "pump.alert.2");
        Test.assert(Alerts.dismissable(first));
        Test.assert(!Alerts.dismissable(alerts[1] as Lang.Dictionary));
        Support.eq(Status.revision(), Wire.text(Support.payloadOf(Rez.JsonData.fixture_config), "revision", ""));
        return true;
    }

    (:test)
    function minimalStatusReads(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_minimal), NOW));
        Support.eq(Status.pumpLink(), "connecting");
        Support.eq(Status.glucose(), null);
        Support.eq(Status.ageOf("glucose", NOW), null);
        Test.assert(!Status.canBolus());
        Support.eq(Status.blockReason(), "pumpNotConnected");
        Support.eq(Status.alerts().size(), 0);
        return true;
    }

    (:test)
    function deliveringStatusReads(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(Status.accept(Support.payloadOf(Rez.JsonData.fixture_status_delivering), NOW));
        Support.eq(Status.glucose(), 38);
        Test.assert(Status.glucoseFromBackup());
        Support.eq(Status.trend(), null);
        Support.eq(Status.ageOf("glucose", NOW), 900);
        Test.assert(Status.basalSuspended());
        Support.eq(Status.blockReason(), "bolusInProgress");
        var active = Status.activeBolus() as Lang.Dictionary;
        Support.eq(active["requestedMU"] as Lang.Object?, 4000);
        Support.eq(active["deliveredMU"] as Lang.Object?, 1250);
        Support.eq(active["startedAt"] as Lang.Object?, NOW - 30);
        // A bolus the pump is delivering can always be cancelled from the watch.
        Test.assert(BolusFlow.canCancel());
        return true;
    }

    (:test)
    function configReads(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        var p = Support.payloadOf(Rez.JsonData.fixture_config);
        Test.assert(Prefs.accept(p, NOW));
        Support.eq(Prefs.revision(), Wire.text(p, "revision", "?"));
        Test.assert(Prefs.bolusEnabled());
        Test.assert(!Prefs.readOnly());
        Support.eq(Prefs.defaultMode(), "carbs");
        Support.eq(Prefs.unitsStep(), 50);
        Support.eq(Prefs.carbStep(), 5);
        Test.assert(Support.same(Prefs.screenOrder(), ["glance", "alerts", "history", "details"]));
        Support.eq(Prefs.defaultScreen(), "glance");
        Test.assert(Support.same(Prefs.details(),
                                 ["iob", "reservoir", "battery", "cgm", "lastBolus", "carbRatio", "isf", "target", "maxBolus"]));
        Test.assert(Support.same(Prefs.chartHours(), [3, 6, 12, 24]));
        Support.eq(Prefs.complicationDisplay(), "numericColor");
        Test.assert(Support.same(Prefs.complicationSlots(), ["iob", "reservoir", "battery"]));
        Test.assert(!Prefs.clockAnalog());
        Support.eq(Prefs.glucoseUnit(), "mgdl");
        Support.eq(Prefs.staleSeconds(), 360);
        Support.eq(Prefs.hideDelaySeconds(), null);
        Support.eq(Prefs.plotFloor(), 40);
        Support.eq(Prefs.plotCeiling(), 300);
        return true;
    }

    (:test)
    function historyReads(logger as Test.Logger) as Lang.Boolean {
        Support.fresh();
        Test.assert(History.accept(Support.payloadOf(Rez.JsonData.fixture_history)));
        Support.eq(History.times().size(), 6);
        Support.eq(History.values()[5] as Lang.Object?, 142);
        Support.eq(History.times()[5] as Lang.Object?, NOW - 1500 + 5 * 300);
        return true;
    }

    // The outcomes, applied to the request they name; a later message that would move it back is ignored.
    (:test)
    function outcomesRead(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow._id = "1793534390-7-118220";
        BolusFlow._msg = {};
        BolusFlow._state = "sending";
        Test.assert(BolusFlow.onOutcome(Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_delivering), NOW));
        Support.eq(BolusFlow.state(), "delivering");
        Support.eq(BolusFlow.requestedMU(), 4000);
        Test.assert(BolusFlow.onOutcome(Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_delivered), NOW));
        Support.eq(BolusFlow.state(), "delivered");
        Support.eq(BolusFlow.deliveredMU(), 4000);
        Test.assert(!BolusFlow.onOutcome(Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_delivering), NOW));
        Support.eq(BolusFlow.state(), "delivered");
        // The failure names another request.
        Test.assert(!BolusFlow.onOutcome(Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_failed), NOW));
        BolusFlow._id = "1793534390-8-120004";
        BolusFlow._state = "sending";
        Test.assert(BolusFlow.onOutcome(Support.payloadOf(Rez.JsonData.fixture_bolusOutcome_failed), NOW));
        Support.eq(BolusFlow.state(), "failed");
        Support.eq(BolusFlow.text(), "Remote control is turned off — remotes are read-only.");
        Support.eq(BolusFlow.headline(), "Not delivered");
        return true;
    }

    (:test)
    function dismissResultReads(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Alerts._dismissId = "1793534395-r3-119001";
        Support.eq(Alerts.shown().size(), 2);
        Test.assert(Alerts.onDismissResult(Support.payloadOf(Rez.JsonData.fixture_dismissResult)));
        Support.eq(Alerts.shown().size(), 1);
        Support.eq(Alerts.idOf(Alerts.shown()[0] as Lang.Dictionary), "app.pumpDisconnected");
        // The next status is the authority again.
        Alerts.onStatus();
        Support.eq(Alerts.shown().size(), 2);
        return true;
    }

    (:test)
    function incompatibleReads(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Support.eq(Inbound.handle(Support.fixture(Rez.JsonData.fixture_incompatible), NOW), Wire.INCOMPATIBLE);
        Test.assert(Link.watchTooOld());
        Support.eq(BolusFlow.startBlock(NOW), "Update the watch app");
        return true;
    }

    // What the watch sends, exactly as the fixtures the phone's tests decode.
    (:test)
    function watchMessagesAreTheFixtures(logger as Test.Logger) as Lang.Boolean {
        var revision = Wire.text(Support.payloadOf(Rez.JsonData.fixture_config), "revision", "?");
        Test.assert(Support.same(Wire.poll(revision, "1793534390-7-118220", true, false),
                                 Support.fixture(Rez.JsonData.fixture_poll)));
        Test.assert(Support.same(Wire.poll(null, null, false, true), Support.fixture(Rez.JsonData.fixture_poll_empty)));
        Test.assert(Support.same(Wire.bolusUnits("1793534390-7-118220", NOW - 10, 4000),
                                 Support.fixture(Rez.JsonData.fixture_bolus_units)));
        Test.assert(Support.same(Wire.bolusCarbs("1793534390-9-118999", NOW - 10, 45, 6000, 142, false),
                                 Support.fixture(Rez.JsonData.fixture_bolus_carbs)));
        Test.assert(Support.same(Wire.bolusCarbs("1793534390-10-119500", NOW - 10, 30, 4000, 160, true),
                                 Support.fixture(Rez.JsonData.fixture_bolus_carbs_stale)));
        Test.assert(Support.same(Wire.cancel("1793534399-11-121000", "1793534390-7-118220"),
                                 Support.fixture(Rez.JsonData.fixture_cancel)));
        Test.assert(Support.same(Wire.dismiss("1793534395-r3-119001", "pump.alert.2"),
                                 Support.fixture(Rez.JsonData.fixture_dismiss)));
        // And a change to any field is caught.
        Test.assert(!Support.same(Wire.bolusUnits("1793534390-7-118220", NOW - 10, 4050),
                                  Support.fixture(Rez.JsonData.fixture_bolus_units)));
        return true;
    }

    // The calculator on the golden status gives the dose the golden carb request carries, which the
    // phone's own tests accept.
    (:test)
    function theCarbFixtureIsWhatTheCalculatorSays(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "carbs";
        BolusFlow.carbs = 45;
        Support.eq(BolusFlow.estimate(NOW), 6000);
        var est = Wire.int(Support.payloadOf(Rez.JsonData.fixture_bolus_carbs), "estimateMU", 0, 100000);
        Support.eq(est, 6000);
        return true;
    }

    // A whole bolus through the flow: the message sent carries the dose dialed, the send time and the
    // request ID the phone will answer to.
    (:test)
    function aConfirmedBolusSendsTheRequest(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        BolusFlow.mode = "units";
        BolusFlow.unitsMU = 4000;
        Test.assert(BolusFlow.arm(NOW));
        Test.assert(BolusFlow.send(NOW));
        var sent = Support.lastSent() as Lang.Dictionary;
        Support.eq(sent["kind"] as Lang.Object?, "bolus");
        var p = Wire.payload(sent);
        Support.eq(p["mode"] as Lang.Object?, "units");
        Support.eq(p["mU"] as Lang.Object?, 4000);
        Support.eq(p["sentAt"] as Lang.Object?, NOW);
        Support.eq(p["requestId"] as Lang.Object?, BolusFlow.requestId());
        Support.eq(BolusFlow.state(), "sending");
        // Same keys as the fixture.
        Support.eq(p.size(), Support.payloadOf(Rez.JsonData.fixture_bolus_units).size());
        return true;
    }
}
