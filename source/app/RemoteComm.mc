using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Application.Storage;
using Toybox.WatchUi as Ui;

// Phone↔remote command builder + transport. Mirrors the faBolus contract
// (faBolus/schema/command.schema.json, source of truth; Swift mirror in faBolusCore/RemoteCommand.swift).
// The schema keys this remote uses are pinned in ../../schema/remote-keys.txt and checked against the
// schema by scripts/check-schema-drift.sh in CI. Commands are sent to the iPhone host over the
// Connect IQ mobile SDK; the phone runs the confirm interlock and dispatches to the pump backend.
//
// (A direct-to-pump transport was prototyped behind a router here; it's paused and lives under
// direct-pump/. This is the shipping phone-relay version.)
module RemoteComm {
    (:background)
    const SCHEMA_VERSION = 1;

    // Builds a units-only bolus request dictionary matching the schema.
    // `sentAt` is the wall-clock send-time stamp (Unix seconds); the host refuses a delivery-authorizing
    // command that arrives too late (stale bolus = double-dose hazard). Time.now().value() is real
    // wall-clock — NOT System.getTimer() (monotonic device-uptime), which newRequestId() uses.
    //
    // C2 §2.3: `code` is the entered 4-digit bolus passcode, or null when no passcode was required. It is
    // added to the wire dict ("bolusPasscode") ONLY when non-null (same additive-field idiom as sentAt /
    // bgMgdl) — omitted entirely otherwise. The PHONE is the sole authority: it verifies the code and
    // denies the bolus if wrong/absent. The watch never verifies or persists it (see AppState.sendBolusNow).
    function bolusRequest(units as Lang.Float, requestId as Lang.String, code as Lang.String?) as Lang.Dictionary {
        var d = {
            "version" => SCHEMA_VERSION,
            "kind" => "bolusRequest",
            "requestId" => requestId,
            "units" => units,
            "sentAt" => Time.now().value()
        };
        if (code != null) { d["bolusPasscode"] = code; }
        return d;
    }

    // Builds a CARB bolus request: the phone (host) is the single calculator — it recomputes the dose
    // from carbsGrams and delivers. We include this watch's own estimate (remoteEstimateUnits) so the
    // phone can reject the bolus if the two diverge (stale-settings guard). bg omitted when stale/unknown.
    //
    // C2 §2.3: `code` is added ("bolusPasscode") only when non-null — see bolusRequest() above.
    //
    // AB4 (Addendum B Option B): `includeStale` is the EXPLICIT per-attempt intent that the wearer chose
    // to include a stale-but-real CGM reading in the correction (the three-way stale prompt's "include").
    // It is added to the wire dict ("includeStaleBG" => true) ONLY when true (same additive-field idiom as
    // bgMgdl / bolusPasscode) — omitted entirely otherwise, NEVER sent as false. The host fails closed on
    // its absence (carbs-only), so the flag is what lets the phone distinguish an acknowledged-stale dose
    // from a bg that merely happened to be stale. Only meaningful on the carb path (never units-mode).
    function bolusRequestCarbs(carbs as Lang.Number, bg as Lang.Number?, estimate as Lang.Float,
                               requestId as Lang.String, code as Lang.String?,
                               includeStale as Lang.Boolean) as Lang.Dictionary {
        var d = {
            "version" => SCHEMA_VERSION,
            "kind" => "bolusRequest",
            "requestId" => requestId,
            "carbsGrams" => carbs,
            "remoteEstimateUnits" => estimate,
            "sentAt" => Time.now().value()   // freshness stamp — see bolusRequest()
        };
        if (bg != null) { d["bgMgdl"] = bg; }
        if (code != null) { d["bolusPasscode"] = code; }
        if (includeStale) { d["includeStaleBG"] = true; }
        return d;
    }

    function cancelBolus(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "cancelBolus", "requestId" => requestId };
    }

    (:background)
    function statusRead(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "statusRead", "requestId" => requestId };
    }

    // statusRead that asks the phone to force a fresh CGM read before replying — sent when the bolus
    // screen opens so the estimate is off the newest value. (The phone also re-reads at delivery.)
    function statusReadFresh(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "statusRead", "requestId" => requestId, "forceGlucose" => true };
    }

    // Unit-test seam (mirrors testSuppressTransmit/testPhoneReachable above). Forces dismissAlert() to
    // throw before it builds its dict — used by tests/RelayResilienceTest.mc's Test 1 (Phase 22 retarget)
    // to prove pollTick's dismiss-retry try/catch (FaBolusApp.mc) never lets a throw skip
    // scheduleNextPoll(), the loop's only re-arm path (C5-01/CX-G-05). Never assigned outside the unit
    // suite; false is the shipping default, so dismissAlert()'s returned dict shape is UNCHANGED in
    // shipping use.
    var testDismissAlertThrows = false;

    // Clears a pump alert on the phone (which sends the signed dismiss to the pump).
    function dismissAlert(requestId as Lang.String, alertId as Lang.Number, alertKind as Lang.Number) as Lang.Dictionary {
        if (testDismissAlertThrows) { throw new Lang.Exception(); }
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "dismissAlert",
            "requestId" => requestId,
            "alertId" => alertId,
            "alertKind" => alertKind
        };
    }

    // Advanced-control requests (B5): ask the phone to suspend/resume insulin. The phone re-confirms
    // on-device and only honors them when advanced control is enabled for a Mobi — the watch never
    // triggers delivery changes unilaterally.
    function suspendPump(requestId as Lang.String) as Lang.Dictionary {
        return { "version" => SCHEMA_VERSION, "kind" => "suspendPump", "requestId" => requestId };
    }

    // resumePump is insulin-INCREASING (delivery-authorizing), so it carries the freshness stamp too.
    // suspendPump above is insulin-REDUCING and deliberately NOT gated — no stamp.
    function resumePump(requestId as Lang.String) as Lang.Dictionary {
        return {
            "version" => SCHEMA_VERSION,
            "kind" => "resumePump",
            "requestId" => requestId,
            "sentAt" => Time.now().value()
        };
    }

    // Unit-test seam (mirrors testSuppressTransmit below and FaBolusApp's documented test seams). The
    // venu3s simulator reports System.getDeviceSettings().phoneConnected == TRUE by default — an
    // environment-specific default (other sims/devices report false), so a test that must drive the
    // `!phoneReachable()` "iPhone unreachable"/outOfRange path can't rely on the sim's own default. A test
    // sets this to a Boolean to force phoneReachable()'s result deterministically; null — the shipping
    // default, NEVER assigned outside the unit suite — defers to the real device setting, so shipping
    // reachability is UNCHANGED. Only the SOURCE of the reachability bit is overridable (and only in tests);
    // every caller's gate/return/branch semantics are untouched.
    var testPhoneReachable as Lang.Boolean? = null;

    // True when the companion phone is reachable.
    function phoneReachable() as Lang.Boolean {
        if (testPhoneReachable != null) { return testPhoneReachable; }
        return System.getDeviceSettings().phoneConnected;
    }

    // Unit-test seam (mirrors FaBolusApp's documented scheduleCount() test seam). The
    // Connect IQ simulator has no phone companion, so a REAL Comm.transmit() during the unit suite pops a
    // modal "There is no data connection … connect an Android device to ADB" dialog for EVERY send the
    // tests drive (pollTick's statusRead, sendBolus, the cancel path) — and pollTick's re-armed poll timers
    // keep firing more until the sim is quit. Unit builds set this true once at startup (see
    // tests/TestEntryApp.mc) so send()/sendBolus() skip ONLY the physical radio call; the phoneReachable()
    // gate, the returned dispatched-Bool, and the try/catch are all UNCHANGED — the tests exercise the exact
    // same decision paths, just without the dialog. Always false in shipping (never assigned there).
    var testSuppressTransmit = false;

    // Sends a command dictionary to the paired phone app. No-ops safely offline; never crashes.
    //
    // VA-14: returns whether the command was DISPATCHED to the transport (true) or dropped because the
    // phone was unreachable / Comm.transmit threw synchronously (false). Routine callers (statusRead / HR
    // / cancel) ignore the return exactly as before — a returned-but-unused value is fine in Monkey C, so
    // this stays backward-compatible. AlertConfirmDelegate (VA-14) reads it so an offline alert-dismiss
    // isn't shown as cleared while the alert is still active on the pump. (For the bolus path use
    // sendBolus(), which also reports ASYNC transport failures via BolusCommListener.)
    function send(cmd as Lang.Dictionary) as Lang.Boolean {
        if (!phoneReachable()) { return false; }
        try {
            if (!testSuppressTransmit) { Comm.transmit(cmd, null, new CommListener()); }
            return true;
        } catch (e) {
            // swallow transport errors; the UI reflects reachability separately
            return false;
        }
    }

    // VA-12: the BOLUS-specific send — reports dispatch so sendBolusNow never leaves a stuck "delivering…".
    // Returns false (no bolus went out) when the phone is unreachable or Comm.transmit throws
    // synchronously. A LATE/ASYNC transport failure (reachable at transmit, the send fails afterward) is
    // surfaced by BolusCommListener.onError → AppState.noteBolusSendFailed(reqId) (reqId-guarded so a late
    // error for a superseded request is a no-op). Separate from the generic swallowing send() above, which
    // stays fire-and-forget for routine traffic.
    function sendBolus(cmd as Lang.Dictionary, reqId as Lang.String) as Lang.Boolean {
        if (!phoneReachable()) { return false; }
        try {
            if (!testSuppressTransmit) { Comm.transmit(cmd, null, new BolusCommListener(reqId)); }
            return true;
        } catch (e) {
            return false;
        }
    }

    // VA-17: a request id unique across a reboot / a background↔foreground process split / a
    // System.getTimer() rollover. The OLD id (getTimer() ms-since-boot + a per-process module counter)
    // collided across sessions — the host ledger keys on (peer, requestId), so a reused id could replay an
    // old outcome or report a duplicate. The core fix is the PERSISTED monotonic sequence: read the last
    // sequence from Storage (0 if absent — fresh install / first ever id), advance it, and persist it
    // BEFORE composing the id, so the very next mint (in ANY process, after ANY reboot) never reuses it.
    // Reading Storage every call keeps the two separate processes (foreground app + background service,
    // each starting _counter at 0) globally monotonic. Folding in the wall clock (Time.now().value()) and
    // the boot timer (System.getTimer()) is defense-in-depth. Schema: requestId is a string, minLength 1,
    // with NO maxLength/pattern (../../schema) — the longer composite is contract-safe.
    (:background)
    const KEY_REQ_SEQ = "reqSeq";
    (:background)
    var _counter = 0;
    (:background)
    function newRequestId() as Lang.String {
        var seq = Storage.getValue(KEY_REQ_SEQ);
        _counter = (seq instanceof Lang.Number) ? (seq as Lang.Number) + 1 : 1;
        Storage.setValue(KEY_REQ_SEQ, _counter);
        return Time.now().value().toString() + "-" + _counter.toString() + "-" + System.getTimer().toString();
    }

    // 19-03 (G-M1): the ROUTINE counterpart of newRequestId() above, for every hot-path mint that is
    // NOT dose-authorizing — statusRead / statusReadFresh (pollTick, every View.onShow, the background
    // temporal service) and dismissAlert (a wearer's confirm). Those fire far more often than a bolus
    // (every ~15s of foreground polling alone) and their ids are never ledgered by the host for
    // (peer,requestId) dose dedup — display/correlation-only. Doing newRequestId()'s Storage.get+set on
    // every one of those mints was pure hot-path flash churn with no dedup benefit, so this mint is a
    // module-level in-memory counter (seeded once per process at 0, like _counter above) with NO Storage
    // read and NO Storage write, folded with the wall clock + boot timer for cross-process uniqueness —
    // the SAME defense-in-depth folding newRequestId() uses. The "r" infix keeps a routine id's format
    // (`<wallSec>-r<n>-<timer>`) textually distinct from a durable id's (`<wallSec>-<n>-<timer>`), so
    // the two id spaces can never collide even minted in the same wall-clock second. The persisted
    // "reqSeq" sequence — and therefore VA-17's reboot invariant — stays reserved for newRequestId()
    // alone; RoutineRequestIdTest pins that this mint never reads/advances it.
    (:background)
    var _routineCounter = 0;
    (:background)
    function newRoutineRequestId() as Lang.String {
        _routineCounter += 1;
        return Time.now().value().toString() + "-r" + _routineCounter.toString() + "-" + System.getTimer().toString();
    }
}

// Minimal ConnectionListener (transmit requires one). Delivery status comes back via the
// separate phone→watch bolusStatus message, so these are no-ops.
class CommListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void {}
}

// VA-12: the BOLUS transmit listener. Unlike CommListener (routine traffic, no-op), an ASYNC transport
// error on a bolus send must not leave the wearer staring at a stuck "delivering…" — onError() flips the
// in-flight status to "failed" via AppState.noteBolusSendFailed(reqId), guarded by reqId so a late error
// for a superseded request is ignored, then requests a redraw. The authoritative terminal outcome still
// comes from the phone's bolusStatus echo (by requestId); this only handles the send never landing.
class BolusCommListener extends Comm.ConnectionListener {
    private var _reqId as Lang.String;
    function initialize(reqId as Lang.String) {
        ConnectionListener.initialize();
        _reqId = reqId;
    }
    function onComplete() as Void {}
    function onError() as Void {
        AppState.noteBolusSendFailed(_reqId);
        Ui.requestUpdate();
    }
}
