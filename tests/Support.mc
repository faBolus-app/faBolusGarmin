using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Test;
using Toybox.WatchUi as Ui;

// What the tests share: the contract's golden fixtures, a deep comparison, and a clean slate.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module Support {
    // The fixtures' time (RemoteProtocol.GoldenFixtures.now): 2026-11-01 12:00 UTC.
    const NOW = 1793534400;

    function fixture(id as Lang.ResourceId) as Lang.Dictionary {
        var v = Ui.loadResource(id);
        return (v instanceof Lang.Dictionary) ? v : {};
    }

    function payloadOf(id as Lang.ResourceId) as Lang.Dictionary { return Wire.payload(fixture(id)); }

    // Asserts `actual` equals `expected` as JSON, saying both when it doesn't.
    function eq(actual as Lang.Object?, expected as Lang.Object?) as Void {
        eqm(actual, expected, "");
    }

    function eqm(actual as Lang.Object?, expected as Lang.Object?, label as Lang.String) as Void {
        Test.assertMessage(same(actual, expected), label + " got " + show(actual) + ", expected " + show(expected));
    }

    function show(v as Lang.Object?) as Lang.String { return (v == null) ? "null" : v.toString(); }

    function isSet(v as Lang.Object?) as Lang.Boolean { return v != null; }

    // Equal as JSON: the same keys with equal values, the same elements in order.
    function same(a as Lang.Object?, b as Lang.Object?) as Lang.Boolean {
        if (a == null || b == null) { return a == null && b == null; }
        if (a instanceof Lang.Dictionary) {
            if (!(b instanceof Lang.Dictionary) || a.size() != b.size()) { return false; }
            var keys = a.keys();
            for (var i = 0; i < keys.size(); i += 1) {
                var k = keys[i];
                if (!b.hasKey(k) || !same(a[k] as Lang.Object?, b[k] as Lang.Object?)) { return false; }
            }
            return true;
        }
        if (a instanceof Lang.Array) {
            if (!(b instanceof Lang.Array) || a.size() != b.size()) { return false; }
            for (var i = 0; i < a.size(); i += 1) {
                if (!same(a[i] as Lang.Object?, b[i] as Lang.Object?)) { return false; }
            }
            return true;
        }
        if (a instanceof Lang.String) { return b instanceof Lang.String && a.equals(b); }
        if (a instanceof Lang.Boolean) { return b instanceof Lang.Boolean && a == b; }
        if (a instanceof Lang.Number || a instanceof Lang.Long) {
            return (b instanceof Lang.Number || b instanceof Lang.Long) && a.toLong() == (b as Lang.Number or Lang.Long).toLong();
        }
        return a.equals(b);
    }

    // Everything the app holds, as after a fresh install, with the phone connected and transmits recorded.
    function fresh() as Void {
        Storage.clearValues();
        Status.clear();
        Prefs.clear();
        History.reset();
        BolusFlow.forget();
        BolusFlow.reset();
        Alerts.reset();
        Link.reset();
        Controller.reset();
        Link.testReachable = true;
        Link.testSuppressTransmit = true;
    }

    // The golden config and status, received at NOW, with the phone heard from.
    function connected() as Void {
        fresh();
        Prefs.accept(payloadOf(Rez.JsonData.fixture_config), NOW);
        Status.accept(payloadOf(Rez.JsonData.fixture_status), NOW);
        Link.heard(NOW);
    }

    // The last message the watch handed to the transport, or null.
    function lastSent() as Lang.Dictionary? {
        var sent = Link.testSent;
        if (sent.size() == 0) { return null; }
        var m = sent[sent.size() - 1];
        return (m instanceof Lang.Dictionary) ? m : null;
    }

    function sentKinds() as Lang.Array<Lang.String> {
        var out = [] as Lang.Array<Lang.String>;
        for (var i = 0; i < Link.testSent.size(); i += 1) {
            var m = Link.testSent[i];
            if (m instanceof Lang.Dictionary) { out.add(Wire.text(m, "kind", "?")); }
        }
        return out;
    }

    // A status payload: the golden one with these fields replaced.
    function status(changes as Lang.Dictionary) as Lang.Dictionary {
        var p = payloadOf(Rez.JsonData.fixture_status);
        var keys = changes.keys();
        for (var i = 0; i < keys.size(); i += 1) { p[keys[i]] = changes[keys[i]]; }
        return p;
    }

    function message(kind as Lang.String, payload as Lang.Dictionary) as Lang.Dictionary {
        return { "version" => 2, "kind" => kind, "payload" => payload };
    }

    function outcome(id as Lang.String, token as Lang.String) as Lang.Dictionary {
        return { "requestId" => id, "outcome" => token, "sentAt" => NOW };
    }
}
