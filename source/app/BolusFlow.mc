using Toybox.Application.Storage;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.WatchUi as Ui;

// A bolus from the watch: what's being dialed, the dose confirmed with 1 → 2 → 3, and the request sent.
//
// The phone is the authority. It checks the request, recomputes a calculator dose and delivers, and it
// tells the watch where the request stands. The watch only shows that, and keeps the request until it
// is settled so a lost message is asked for again: the request (with its ID and send time) is kept in
// storage, resent unchanged until the phone acknowledges it, and named in every poll while it's open.
// The phone never delivers a request ID twice.
module BolusFlow {
    // The phone refuses a request sent longer ago than this; resending stops then.
    const FRESH_SEC = 120;
    const RESEND_SEC = 10;
    // With no word from the phone this long after sending, the watch says it has no answer. It never says
    // the bolus wasn't delivered: the phone may have it and its answers may be what was lost.
    const NO_ANSWER_SEC = 150;
    // Every poll names an open request and the phone answers each one it knows, so this long without a
    // word about it means the phone doesn't have it (it may have relaunched before answering).
    const QUIET_SEC = 60;
    // A request still open after this is no longer named in polls; an unknown outcome is the phone's to
    // announce from then on.
    const AWAIT_MAX_SEC = 1800;
    // A confirm older than this must be started again.
    const ARM_SEC = 120;
    const MAX_CARBS = 200;
    // The dial's top when neither a remote limit nor the pump's max is known. Not a dose limit: the phone
    // and the pump check every dose.
    const DIAL_MAX_MU = 25000;

    // Where a request stands: the phone's outcome tokens, plus two of the watch's own.
    // "sending": sent, nothing heard yet. "notSent": the phone wasn't reachable, so nothing went out.
    // "noAnswer": nothing heard long after sending; it may have been delivered.

    // MARK: Entry

    var mode as Lang.String = "carbs";
    var unitsMU as Lang.Number = 0;
    var carbs as Lang.Number = 0;
    // For this attempt only: the user chose to correct from a stale reading.
    var includeStale as Lang.Boolean = false;

    var _armedMU as Lang.Number = 0;
    var _armedAt as Lang.Number = 0;
    var _armedMode as Lang.String = "units";
    var _armedCarbs as Lang.Number = 0;
    var _armedGlucose as Lang.Number? = null;
    var _armedIncludeStale as Lang.Boolean = false;

    function reset() as Void {
        mode = Prefs.defaultMode();
        unitsMU = 0;
        carbs = 0;
        includeStale = false;
        _armedAt = 0;
        _armedMU = 0;
    }

    function toggleMode() as Void {
        mode = mode.equals("units") ? "carbs" : "units";
        includeStale = false;
    }

    function adjust(direction as Lang.Number) as Void {
        if (mode.equals("units")) {
            unitsMU += direction * Prefs.unitsStep();
            if (unitsMU < 0) { unitsMU = 0; }
            var max = dialMax();
            if (unitsMU > max) { unitsMU = max; }
        } else {
            carbs += direction * Prefs.carbStep();
            if (carbs < 0) { carbs = 0; }
            if (carbs > MAX_CARBS) { carbs = MAX_CARBS; }
        }
    }

    function dialMax() as Lang.Number {
        var limit = Status.remoteLimit();
        if (limit != null) { return limit; }
        var max = Status.field("calculator", "maxBolusMU");
        return (max != null && max > 0) ? max : DIAL_MAX_MU;
    }

    // MARK: Glucose and the calculator

    function glucoseStale(now as Lang.Number) as Lang.Boolean {
        var age = Status.ageOf("glucose", now);
        return age == null || age > Prefs.staleSeconds();
    }

    // The reading a calculator dose corrects from: a fresh one, or a stale one the user chose to include
    // this time. Null for carbs only.
    function correctionGlucose(now as Lang.Number) as Lang.Number? {
        var g = Status.glucose();
        if (g == null) { return null; }
        if (!glucoseStale(now)) { return g; }
        return includeStale ? g : null;
    }

    // Why the calculator can't give a dose now, or null. "waiting": the pump's settings or IOB haven't
    // arrived fresh. "low"/"high": the CGM reads outside 40–400 mg/dL, and the phone refuses a calculated
    // dose then, so the watch says so before anything is sent.
    function calculatorBlock(now as Lang.Number) as Lang.String? {
        // The calculator's inputs count while younger than the phone's windows (CalcInputFreshness).
        if (Status.freshField("calculator", "carbRatioMg", Prefs.therapyStaleSeconds(), now) == null
            || Status.freshField("iob", "mU", Prefs.iobStaleSeconds(), now) == null) {
            return "waiting";
        }
        var g = correctionGlucose(now);
        if (g != null && !Calculator.plausible(g)) { return g < Calculator.GLUCOSE_MIN ? "low" : "high"; }
        return null;
    }

    // The calculator's dose in milliunits, rounded down as the phone rounds; -1 when there isn't one.
    function estimate(now as Lang.Number) as Lang.Number {
        if (calculatorBlock(now) != null) { return -1; }
        var ratio = Status.field("calculator", "carbRatioMg");
        var isf = Status.field("calculator", "isf");
        var target = Status.field("calculator", "target");
        var iob = Status.field("iob", "mU");
        if (ratio == null || isf == null || target == null || iob == null) { return -1; }
        return Calculator.estimate(carbs, correctionGlucose(now), ratio, isf, target, iob);
    }

    // The stale-reading question applies: a calculator dose with a reading that's stale. A reading outside
    // 40–400 can only be left out.
    function staleChoiceNeeded(now as Lang.Number) as Lang.Boolean {
        return mode.equals("carbs") && Status.glucose() != null && glucoseStale(now);
    }

    function staleIncludable() as Lang.Boolean {
        var g = Status.glucose();
        return g != null && Calculator.plausible(g);
    }

    function dose(now as Lang.Number) as Lang.Number {
        return mode.equals("units") ? unitsMU : estimate(now);
    }

    // The calculator's dose is above the remote limit or the pump's max: the phone would refuse it, so it
    // isn't offered.
    function overLimit(now as Lang.Number) as Lang.Boolean { return dose(now) > dialMax(); }

    // MARK: Starting

    // A new bolus may be started from the watch now.
    function canStart(now as Lang.Number) as Lang.Boolean { return startBlock(now) == null; }

    // Why not, as a short label for the button, or null.
    function startBlock(now as Lang.Number) as Lang.String? {
        if (Link.phoneTooOld()) { return "Update faBolus on phone"; }
        if (Link.watchTooOld()) { return "Update the watch app"; }
        if (!Link.reachable()) { return "Phone not connected"; }
        if (!Link.phoneLive(now)) { return "No reply from faBolus"; }
        if (!Prefs.bolusEnabled()) { return "Bolusing off (phone)"; }
        if (Prefs.readOnly()) { return "Read-only"; }
        if (busy()) { return "Bolus in progress"; }
        if (!Status.canBolus()) { return blockText(Status.blockReason()); }
        return null;
    }

    function blockText(reason as Lang.String?) as Lang.String {
        if (reason == null) { return ""; }
        if (reason.equals("pumpNotConnected")) { return "Pump not connected"; }
        if (reason.equals("bolusInProgress")) { return "Bolus in progress"; }
        if (reason.equals("cartridgeNotReady")) { return "Cartridge not ready"; }
        if (reason.equals("readOnly")) { return "Read-only"; }
        if (reason.equals("watchBolusOff")) { return "Bolusing off (phone)"; }
        if (reason.equals("pumpCannotBolus")) { return "Pump can't bolus"; }
        if (reason.equals("outcomeUnknown")) { return "Check last bolus"; }
        if (reason.equals("deliveryLocked")) { return "Delivery locked"; }
        if (reason.equals("noStatus")) { return "Waiting for phone"; }
        return "Unavailable";
    }

    // Takes the dose the user is about to confirm. False, arming nothing, when there's nothing to deliver
    // or it's over the limit.
    function arm(now as Lang.Number) as Lang.Boolean {
        var d = dose(now);
        if (d < Calculator.STEP_MU || d > dialMax()) {
            _armedAt = 0;
            return false;
        }
        _armedMU = d;
        _armedAt = now;
        _armedMode = mode;
        _armedCarbs = carbs;
        _armedGlucose = mode.equals("carbs") ? correctionGlucose(now) : null;
        _armedIncludeStale = mode.equals("carbs") && includeStale && _armedGlucose != null;
        return true;
    }

    function armedDose() as Lang.Number { return _armedMU; }

    // Why the confirmed dose can't be sent now, or null. Checked as the confirm screen draws and again at
    // the last tap, so a dose confirmed against a state that has since moved is never sent.
    function armBlock(now as Lang.Number) as Lang.String? {
        if (_armedAt == 0 || _armedMU < Calculator.STEP_MU) { return "expired"; }
        if (!Prefs.bolusEnabled() || Prefs.readOnly()) { return "off"; }
        if (busy()) { return "busy"; }
        if (!Link.phoneLive(now) || !Link.reachable()) { return "phone"; }
        if (!Status.canBolus()) { return "blocked"; }
        if (now - _armedAt > ARM_SEC) { return "expired"; }
        if (_armedMode.equals("carbs") && dose(now) != _armedMU) { return "changed"; }
        return null;
    }

    function armBlockText(reason as Lang.String?) as Lang.String {
        if (reason == null) { return ""; }
        if (reason.equals("off")) { return "Bolusing off"; }
        if (reason.equals("busy")) { return "Bolus pending"; }
        if (reason.equals("phone")) { return "No phone reply"; }
        if (reason.equals("blocked")) { return "Pump not ready"; }
        if (reason.equals("changed")) { return "Dose changed"; }
        return "Expired";
    }

    // MARK: The request

    var _id as Lang.String? = null;
    var _sentAt as Lang.Number = 0;
    var _lastSendAt as Lang.Number = 0;
    // When the phone last said anything about this request (the send time until it has).
    var _heardAt as Lang.Number = 0;
    var _msg as Lang.Dictionary? = null;
    var _state as Lang.String = "";
    var _requestedMU as Lang.Number? = null;
    var _deliveredMU as Lang.Number? = null;
    var _text as Lang.String? = null;
    var _cancelAt as Lang.Number = 0;

    // Sends the confirmed dose. False, with nothing sent, when it can't go (see armBlock).
    function send(now as Lang.Number) as Lang.Boolean {
        if (armBlock(now) != null) { return false; }
        var id = Link.newRequestId(now);
        var msg = _armedMode.equals("units")
            ? Wire.bolusUnits(id, now, _armedMU)
            : Wire.bolusCarbs(id, now, _armedCarbs, _armedMU, _armedGlucose, _armedIncludeStale);
        _id = id;
        _sentAt = now;
        _lastSendAt = now;
        _heardAt = now;
        _msg = msg;
        _requestedMU = _armedMU;
        _deliveredMU = null;
        _text = null;
        _cancelAt = 0;
        _armedAt = 0;
        if (Link.transmit(msg, new BolusListener())) {
            _state = "sending";
        } else {
            // Nothing went out: the phone isn't connected.
            _state = "notSent";
            _text = "Phone not connected. Nothing was sent.";
        }
        save();
        return true;
    }

    // Resends an unacknowledged request while the phone would still take it; says there's no answer once
    // it has waited long enough. True when something changed.
    function tick(now as Lang.Number) as Lang.Boolean {
        var msg = _msg;
        if (_id == null || msg == null) { return false; }
        if (_state.equals("sending") && now - _sentAt <= FRESH_SEC && now - _lastSendAt >= RESEND_SEC) {
            _lastSendAt = now;
            Link.transmit(msg, new BolusListener());
        }
        // Nothing heard after sending, or nothing more about this request partway (the phone went away, or
        // lost the request): the watch can't tell what happened. The poll keeps asking, and any answer
        // moves it on.
        var quiet = _state.equals("sending") || (busy() && now - _heardAt > QUIET_SEC);
        if (quiet && now - _sentAt > NO_ANSWER_SEC) {
            _state = "noAnswer";
            _text = "No answer from the phone. Check the pump before dosing again.";
            save();
            return true;
        }
        return false;
    }

    // The phone's word on a request. Applied only if it is this request and moves it forward, so a late or
    // repeated message changes nothing. True when it changed the state.
    function onOutcome(p as Lang.Dictionary, now as Lang.Number) as Lang.Boolean {
        var id = Wire.str(p, "requestId", Wire.MAX_ID);
        var token = Wire.token(p, "outcome", OUTCOMES);
        var mine = _id;
        if (id == null || token == null || mine == null || !id.equals(mine)) { return false; }
        // A repeat still says the phone has it.
        _heardAt = now;
        if (!canMove(_state, token)) { return false; }
        _state = token;
        var requested = Wire.int(p, "requestedMU", 0, Wire.MAX_MU);
        if (requested != null) { _requestedMU = requested; }
        _deliveredMU = Wire.int(p, "deliveredMU", 0, Wire.MAX_MU);
        _text = Wire.str(p, "message", 256);
        save();
        return true;
    }

    const OUTCOMES = ["received", "accepted", "delivering", "delivered", "stopped", "refused", "failed", "unknown"];

    // The phone's table (contract/README.md), with the watch's own states before the phone has answered.
    function canMove(from as Lang.String, to as Lang.String) as Lang.Boolean {
        if (from.equals("sending") || from.equals("noAnswer")) { return Wire.contains(OUTCOMES, to); }
        if (from.equals("received")) { return !to.equals("received"); }
        if (from.equals("accepted")) { return !to.equals("received") && !to.equals("accepted"); }
        if (from.equals("delivering")) { return to.equals("delivered") || to.equals("stopped") || to.equals("unknown"); }
        if (from.equals("unknown")) { return to.equals("delivered") || to.equals("stopped") || to.equals("failed"); }
        return false;
    }

    function isFinal(state as Lang.String) as Lang.Boolean {
        return state.equals("delivered") || state.equals("stopped") || state.equals("refused")
            || state.equals("failed") || state.equals("notSent");
    }

    // A request is being worked on: sent, and not yet settled or given up on. While it is, another can't
    // start from the watch. An unknown outcome, or no answer, doesn't block here: the phone blocks a new
    // bolus itself while an outcome is unknown, and a watch that stopped hearing from the phone mustn't be
    // stuck. Both are still asked about in polls.
    function busy() as Lang.Boolean {
        return _id != null && (_state.equals("sending") || _state.equals("received") || _state.equals("accepted")
            || _state.equals("delivering"));
    }

    // Open: not settled, so its outcome is still asked for.
    function open() as Lang.Boolean { return _id != null && !isFinal(_state); }

    function state() as Lang.String { return _state; }
    function requestId() as Lang.String? { return _id; }
    function requestedMU() as Lang.Number? { return _requestedMU; }
    function deliveredMU() as Lang.Number? { return _deliveredMU; }
    function text() as Lang.String? { return _text; }
    function cancelling() as Lang.Boolean { return _cancelAt != 0 && busy(); }

    // The request the next poll names, so the phone sends its outcome again.
    function awaitingId(now as Lang.Number) as Lang.String? {
        if (!open() || now - _sentAt > AWAIT_MAX_SEC) { return null; }
        return _id;
    }

    // A bolus can be cancelled from the watch whenever the pump is delivering one, or this watch's request
    // may be about to start. Never gated.
    function canCancel() as Lang.Boolean {
        if (Status.activeBolus() != null) { return true; }
        return busy();
    }

    function cancel(now as Lang.Number) as Lang.Boolean {
        var sent = Link.transmit(Wire.cancel(Link.newRequestId(now), _id),
                                 new SendListener(new Lang.Method(BolusFlow, :cancelFailed), now));
        if (sent) { _cancelAt = now; }
        return sent;
    }

    // The cancel sent at `at` failed after it was handed over: it isn't shown as in progress, and the user
    // is told to press again.
    function cancelFailed(at as Lang.Number) as Void {
        if (_cancelAt == 0 || _cancelAt != at) { return; }
        _cancelAt = 0;
        Toast.show("Cancel not sent — try again");
    }

    // Leaving the result screen forgets a settled request.
    function forgetIfSettled() as Void {
        if (_id != null && isFinal(_state)) { forget(); }
    }

    function forget() as Void {
        _id = null;
        _msg = null;
        _state = "";
        _sentAt = 0;
        _cancelAt = 0;
        _requestedMU = null;
        _deliveredMU = null;
        _text = null;
        Storage.deleteValue(Store.BOLUS);
    }

    function save() as Void {
        var id = _id;
        var msg = _msg;
        if (id == null || msg == null) { return; }
        var rec = { "id" => id, "sentAt" => _sentAt, "msg" => msg, "state" => _state } as Lang.Dictionary;
        var requested = _requestedMU;
        var delivered = _deliveredMU;
        var text = _text;
        if (requested != null) { rec["requestedMU"] = requested; }
        if (delivered != null) { rec["deliveredMU"] = delivered; }
        if (text != null) { rec["text"] = text; }
        Store.save(Store.BOLUS, rec);
    }

    // A request from before the app was last closed, so its outcome is still asked for. The phone gets a
    // full quiet window from `now` to answer about it.
    function load(now as Lang.Number) as Void {
        var rec = Store.record(Store.BOLUS);
        if (rec == null) { return; }
        var id = Wire.str(rec, "id", Wire.MAX_ID);
        var sentAt = Wire.int(rec, "sentAt", Wire.EPOCH_MIN, Wire.EPOCH_MAX);
        var msg = Wire.obj(rec, "msg");
        var state = Wire.str(rec, "state", 16);
        if (id == null || sentAt == null || msg == null || state == null) {
            Storage.deleteValue(Store.BOLUS);
            return;
        }
        _id = id;
        _sentAt = sentAt;
        _lastSendAt = sentAt;
        _heardAt = (now > sentAt) ? now : sentAt;
        _msg = msg;
        _state = state;
        _requestedMU = Wire.int(rec, "requestedMU", 0, Wire.MAX_MU);
        _deliveredMU = Wire.int(rec, "deliveredMU", 0, Wire.MAX_MU);
        _text = Wire.str(rec, "text", 256);
    }

    // What the request screen says.
    function headline() as Lang.String {
        if (cancelling()) { return "Cancelling…"; }
        if (_state.equals("sending")) { return "Sending…"; }
        if (_state.equals("received") || _state.equals("accepted")) { return "Starting…"; }
        if (_state.equals("delivering")) { return "Delivering…"; }
        if (_state.equals("delivered")) { return "Delivered"; }
        if (_state.equals("stopped")) { return "Stopped"; }
        if (_state.equals("refused")) { return "Pump refused"; }
        if (_state.equals("failed") || _state.equals("notSent")) { return "Not delivered"; }
        if (_state.equals("unknown")) { return "Outcome unknown"; }
        if (_state.equals("noAnswer")) { return "No answer"; }
        return "";
    }
}

// An error handing the bolus request over: it's resent on the next tick while the phone would still take it.
class BolusListener extends Comm.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() as Void {}
    function onError() as Void { Ui.requestUpdate(); }
}
