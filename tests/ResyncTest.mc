using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Test;

// The watch gets back a config it missed, after its storage was wiped, and when it never had one; and a
// message from the other version is shown for what it is.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module ResyncTest {
    const NOW = Support.NOW;

    function revisionOfFixture() as Lang.String {
        return Wire.text(Support.payloadOf(Rez.JsonData.fixture_config), "revision", "?");
    }

    // The phone changed a preference while the message carrying it was lost: the next status names the
    // new revision, and the watch polls at once with its own, which makes the phone send the config.
    (:test)
    function aMissedChangeIsAskedForAtOnce(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Test.assert(!Inbound.configBehind());
        var newer = Support.status({ "configRevision" => "00000000000000aa" });
        Controller.phoneData(Support.message("status", newer));
        Test.assert(Inbound.configBehind());
        var poll = Support.lastSent() as Lang.Dictionary;
        Support.eq(poll["kind"] as Lang.Object?, "poll");
        Support.eq(Wire.payload(poll)["configRevision"] as Lang.Object?, revisionOfFixture());
        // The config arrives and the watch is level.
        var config = Support.payloadOf(Rez.JsonData.fixture_config);
        config["revision"] = "00000000000000aa";
        Controller.phoneData(Support.message("config", config));
        Support.eq(Prefs.revision(), "00000000000000aa");
        Test.assert(!Inbound.configBehind());
        return true;
    }

    // A config the watch can't read isn't asked for again on every status: at most once in BEHIND_SEC, so
    // the phone and the watch don't trade config and polls without end.
    (:test)
    function anUnreadableConfigIsntAskedForWithoutEnd(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var bad = Support.payloadOf(Rez.JsonData.fixture_config);
        bad["chartHours"] = [5];
        bad["revision"] = "00000000000000dd";
        var polls = 0;
        for (var i = 0; i < 20; i += 1) {
            var t = NOW + i;
            Controller.phoneData(Support.message("status", Support.status({ "sentAt" => t, "configRevision" => "00000000000000dd" })));
            Controller.phoneData(Support.message("config", bad));
        }
        var kinds = Support.sentKinds();
        for (var i = 0; i < kinds.size(); i += 1) {
            if (kinds[i].equals("poll")) { polls += 1; }
        }
        Support.eq(polls, 1);
        Test.assert(Inbound.configBehind());
        return true;
    }

    // Storage wiped: every preference is back to its default, bolusing off, and the next poll names no
    // revision, so the phone sends the config in full.
    (:test)
    function aWipedWatchAsksForTheConfig(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Prefs.save(Store.CONFIG);
        Status.save(Store.STATUS);
        Storage.clearValues();
        Status.clear();
        Prefs.clear();
        Status.load();
        Prefs.load(Status.revision());
        Support.eq(Prefs.revision(), null);
        Test.assert(!Prefs.bolusEnabled());
        Link.poll(NOW);
        var p = Wire.payload(Support.lastSent() as Lang.Dictionary);
        Test.assert(!p.hasKey("configRevision"));
        // A status alone then says the watch is behind.
        Controller.phoneData(Support.message("status", Support.payloadOf(Rez.JsonData.fixture_status)));
        Test.assert(Inbound.configBehind());
        return true;
    }

    // What one process saved, the other loads; the config matching the status's revision wins.
    (:test)
    function theBackgroundsCopyIsLoadedWhenNewer(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Status.save(Store.STATUS);
        Prefs.save(Store.CONFIG);
        Test.assert(Status.accept(Support.status({ "sentAt" => NOW + 300 }), NOW + 300));
        Status.save(Store.BG_STATUS);
        Status.clear();
        Status.load();
        Support.eq(Status.sentAt(), NOW + 300);
        var config = Support.payloadOf(Rez.JsonData.fixture_config);
        config["revision"] = "00000000000000bb";
        Test.assert(Prefs.accept(config, NOW - 100));
        Prefs.save(Store.BG_CONFIG);
        Prefs.clear();
        // The status names the app's copy, though the background's arrived later.
        Prefs.load(revisionOfFixture());
        Support.eq(Prefs.revision(), revisionOfFixture());
        Prefs.load("00000000000000bb");
        Support.eq(Prefs.revision(), "00000000000000bb");
        return true;
    }

    // A config that doesn't read is dropped whole: the watch never mixes two configs.
    (:test)
    function aBadConfigChangesNothing(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var bad = Support.payloadOf(Rez.JsonData.fixture_config);
        bad["chartHours"] = [5];
        bad["revision"] = "00000000000000cc";
        Test.assert(!Prefs.accept(bad, NOW));
        Support.eq(Prefs.revision(), revisionOfFixture());
        return true;
    }

    // The first launch of this version clears what the old one stored, once.
    (:test)
    function theFirstLaunchClearsTheOldStorage(logger as Test.Logger) as Lang.Boolean {
        Storage.clearValues();
        Storage.setValue("screenOrder", ["glance"]);
        Storage.setValue("bg", 120);
        Store.migrate();
        Support.eq(Storage.getValue("screenOrder"), null);
        Support.eq(Storage.getValue("bg"), null);
        Storage.setValue(Store.ALERTS_SEEN, ["a"]);
        Store.migrate();
        Test.assert(Support.same(Storage.getValue(Store.ALERTS_SEEN) as Lang.Object?, ["a"]));
        return true;
    }

    // A message from the old phone app changes nothing, isn't answered, and the watch says to update the
    // phone app.
    (:test)
    function aVersionOneMessageIsShownNotRead(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Support.eq(Wire.kindOf(Support.fixture(Rez.JsonData.fixture_v1_statusRead_from_phone)), Wire.LEGACY);
        Support.eq(Wire.kindOf(Support.fixture(Rez.JsonData.fixture_v1_bolusStatus_from_phone)), Wire.LEGACY);
        var before = Status.sentAt();
        BolusFlow._id = "1793534390-7-118220";
        BolusFlow._msg = {};
        BolusFlow._state = "sending";
        Controller.phoneData(Support.fixture(Rez.JsonData.fixture_v1_statusRead_from_phone));
        Controller.phoneData(Support.fixture(Rez.JsonData.fixture_v1_bolusStatus_from_phone));
        Support.eq(Status.sentAt(), before);
        Support.eq(Status.glucose(), 142);
        Support.eq(BolusFlow.state(), "sending");
        Support.eq(Link.testSent.size(), 0);
        Test.assert(Link.phoneTooOld());
        Support.eq(BolusFlow.startBlock(NOW), "Update faBolus on phone");
        Support.eq(Display.linkLine(NOW), "Update faBolus on phone");
        // A version 2 message clears it.
        Controller.phoneData(Support.message("status", Support.payloadOf(Rez.JsonData.fixture_status)));
        Test.assert(!Link.phoneTooOld());
        return true;
    }

    // A newer version gets no reply either; the watch says to update itself.
    (:test)
    function aNewerVersionIsShown(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        Controller.phoneData({ "version" => 3, "kind" => "status", "payload" => {} });
        Test.assert(Link.watchTooOld());
        Support.eq(Link.testSent.size(), 0);
        Support.eq(Status.glucose(), 142);
        return true;
    }

    // Garbage, and a version 2 message whose kind the phone doesn't send, change nothing.
    (:test)
    function unreadableMessagesChangeNothing(logger as Test.Logger) as Lang.Boolean {
        Support.connected();
        var inputs = [null, "status", [1, 2], {}, { "version" => 2, "kind" => "poll", "payload" => {} },
                      { "version" => 2, "kind" => "status" }, { "version" => "2", "kind" => "status", "payload" => {} },
                      { "version" => 2, "kind" => "status", "payload" => { "sentAt" => 5 } }];
        for (var i = 0; i < inputs.size(); i += 1) {
            Controller.phoneData(inputs[i] as Lang.Object?);
        }
        Support.eq(Status.sentAt(), NOW);
        Support.eq(Status.glucose(), 142);
        Test.assert(!Link.phoneTooOld());
        Test.assert(!Link.watchTooOld());
        return true;
    }
}
