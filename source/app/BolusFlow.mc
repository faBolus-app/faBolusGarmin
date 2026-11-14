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
    // The insulin for the food, milliunits, in place of carbs while carbs are off on the pump. Kept apart
    // from the grams, so carbs turned on or off while one is dialed never reads grams as units.
    var foodMU as Lang.Number = 0;
    // For this attempt only: the user chose to correct from a stale reading.
    var includeStale as Lang.Boolean = false;
    // For this attempt only: asked whether to correct from a reading of 70 or more, the user chose carbs only.
    var declineCorrection as Lang.Boolean = false;

    var _armedMU as Lang.Number = 0;
    var _armedAt as Lang.Number = 0;
    var _armedMode as Lang.String = "units";
    var _armedCarbs as Lang.Number = 0;
    // The armed dose's food was insulin units (carbs off), `_armedFoodMU` of it.
    var _armedInsulin as Lang.Boolean = false;
    var _armedFoodMU as Lang.Number = 0;
    var _armedGlucose as Lang.Number? = null;
    var _armedIncludeStale as Lang.Boolean = false;
    var _armedDecline as Lang.Boolean = false;
    // The user's answer to the correction question, in words for the confirm screen, or null when none
    // was asked: a mistapped row shows here before anything is sent.
    var _armedChoice as Lang.String? = null;
    // The answer the request sent carried, so the confirm screen still names it when the phone asks for a
    // confirmation and the same dose is armed again.
    var _sentChoice as Lang.String? = null;
    // The armed carb dose's split, [food, correction] in milliunits, or null; worked out when it was armed.
    var _armedSplit as Lang.Array<Lang.Number>? = null;
    // What the user confirmed, from the phone's answer to the request this dose was sent as before.
    var _armedConfirmed as Lang.Array = [];

    function reset() as Void {
        mode = Prefs.defaultMode();
        unitsMU = 0;
        carbs = 0;
        foodMU = 0;
        includeStale = false;
        declineCorrection = false;
        _armedAt = 0;
        _armedMU = 0;
        _armedConfirmed = [];
    }

    function toggleMode() as Void {
        mode = mode.equals("units") ? "carbs" : "units";
        includeStale = false;
        declineCorrection = false;
    }

    function adjust(direction as Lang.Number) as Void {
        if (mode.equals("units")) {
            unitsMU += direction * Prefs.unitsStep();
            if (unitsMU < 0) { unitsMU = 0; }
            var max = dialMax();
            if (unitsMU > max) { unitsMU = max; }
        } else if (Status.carbsOff()) {
            // Dialing one kind clears the other, so only what's dialed now can count.
            carbs = 0;
            foodMU += direction * Prefs.unitsStep();
            if (foodMU < 0) { foodMU = 0; }
            var top = dialMax();
            if (foodMU > top) { foodMU = top; }
        } else {
            foodMU = 0;
            carbs += direction * Prefs.carbStep();
            if (carbs < 0) { carbs = 0; }
            if (carbs > MAX_CARBS) { carbs = MAX_CARBS; }
        }
    }

    // Carbs turned on or off on the pump after the food was dialed as the other kind: it's dialed again,
    // never read as the new kind nor quietly dropped, as on the phone.
    function foodNeedsRedial() as Lang.Boolean { return Status.carbsOff() ? carbs > 0 : foodMU > 0; }

    // What the food entry holds: milliunits with carbs off, grams otherwise. Zero is a correction only.
    function foodAmount() as Lang.Number { return Status.carbsOff() ? foodMU : carbs; }

    // The lower of the remote limit and the pump's max bolus, whichever are known.
    function dialMax() as Lang.Number {
        var top = DIAL_MAX_MU;
        var max = Status.field("calculator", "maxBolusMU");
        if (max != null && max > 0) { top = max; }
        var limit = Status.remoteLimit();
        if (limit != null && (max == null || max <= 0 || limit < top)) { top = limit; }
        return top;
    }

    // MARK: Glucose and the calculator

    function glucoseStale(now as Lang.Number) as Lang.Boolean {
        var age = Status.ageOf("glucose", now);
        return age == null || age > Prefs.staleSeconds();
    }

    // The reading a calculator dose corrects from: a fresh one, or a stale one the user chose to include
    // this time. Null for carbs only.
    function correctionGlucose(now as Lang.Number) as Lang.Number? {
        var g = offeredGlucose(now);
        // Declining counts from 70 up, as on the phone; under it the reduction applies.
        if (g != null && declineCorrection && g >= Calculator.LOW_GLUCOSE) { return null; }
        return g;
    }

    // The reading a calculator dose would correct from before the user's answer to the correction question.
    function offeredGlucose(now as Lang.Number) as Lang.Number? {
        var g = Status.glucose();
        // One the pump flags corrects nothing: carbs only, as the phone composes it.
        if (g == null || Status.glucoseCaution() != null) { return null; }
        if (!glucoseStale(now)) { return g; }
        return includeStale ? g : null;
    }

    // Whether to ask "Add a correction?" / "Reduce the bolus?": a fresh reading of 70 or more whose
    // correction changes the dose to another dose, as on the phone. A stale reading the user chose to
    // include was a choice already; with no carbs, or a reduction to nothing, there's no choice.
    function correctionChoiceNeeded(now as Lang.Number) as Lang.Boolean { return correctionDoses(now) != null; }

    // The question's two doses in milliunits, with the correction then without, or null when it isn't asked.
    // Worked out once for a screen that draws both, as each is a full calculation.
    function correctionDoses(now as Lang.Number) as Lang.Array<Lang.Number>? {
        if (!mode.equals("carbs") || calculatorBlock(now) != null || glucoseStale(now)) { return null; }
        var g = Status.glucose();
        if (g == null || g < Calculator.LOW_GLUCOSE || Status.glucoseCaution() != null) { return null; }
        var with = estimateFrom(g);
        var without = estimateFrom(null);
        // Over the limit there's nothing to send either way; the screen says so instead.
        if (with > dialMax() || without > dialMax()) { return null; }
        if (with < Calculator.STEP_MU || without < Calculator.STEP_MU || with == without) { return null; }
        return [with, without];
    }

    // The reading is above the pump's target: the question is about adding a correction, not a reduction.
    function correctionAbove() as Lang.Boolean {
        var g = Status.glucose();
        var target = Status.field("calculator", "target");
        return g != null && target != null && g > target;
    }

    // The calculator's dose from `glucose` (null for carbs only), in milliunits; -1 when there isn't one.
    function estimateFrom(glucose as Lang.Number?) as Lang.Number {
        var ratio = Status.field("calculator", "carbRatioMg");
        var isf = Status.field("calculator", "isf");
        var target = Status.field("calculator", "target");
        var iob = Status.field("iob", "mU");
        if (ratio == null || isf == null || target == null || iob == null) { return -1; }
        // Carbs off: the food is insulin, with no carb ratio, as on the phone.
        if (Status.carbsOff()) { return Calculator.estimateFood(foodMU, glucose, isf, target, iob); }
        return Calculator.estimate(carbs, glucose, ratio, isf, target, iob);
    }

    // Why the dose is what it is, in a few words, or null. While the correction question is still to come,
    // that it will be asked: it would otherwise say the dose was lowered before asking whether to lower it.
    function message(now as Lang.Number) as Lang.String? {
        if (!mode.equals("carbs") || calculatorBlock(now) != null || overLimit(now)) { return null; }
        if (correctionChoiceNeeded(now)) { return correctionAbove() ? "Correction asked next" : "Reduction asked next"; }
        // No reading at all: the dose shown has no correction, which the number alone doesn't say.
        if (Status.glucose() == null) { return "No CGM: " + noCorrection(); }
        // One the pump flags: why, and carbs only.
        var caution = Status.glucoseCaution();
        if (caution != null) { return cautionText(caution); }
        // Stale and too old to include: carbs only, with no question.
        if (glucoseStale(now) && !staleChoiceNeeded(now)) { return "Stale CGM: " + noCorrection(); }
        var isf = Status.field("calculator", "isf");
        var target = Status.field("calculator", "target");
        var iob = Status.field("iob", "mU");
        if (isf == null || target == null || iob == null) { return null; }
        var key = Calculator.message(correctionGlucose(now), isf, target, iob, foodAmount(), estimate(now));
        return key != null ? Calculator.messageText(key) : null;
    }

    // Why the pump flags its reading, in a few words.
    function cautionTitle(caution as Lang.String) as Lang.String {
        if (caution.equals("low")) { return "CGM below range"; }
        if (caution.equals("high")) { return "CGM above range"; }
        if (caution.equals("sensor")) { return "CGM not ready"; }
        if (caution.equals("checkbg")) { return "CGM says check BG"; }
        if (caution.equals("autofilloff")) { return "Auto-fill off"; }
        if (caution.equals("notread")) { return "Checking CGM state"; }
        return "CGM can't be used";
    }

    // The dose screen's line for a flagged reading: why, and what the dose is. Out of range, check BG first.
    function cautionText(caution as Lang.String) as Lang.String {
        if (caution.equals("low") || caution.equals("high")) { return cautionTitle(caution) + ": check BG"; }
        if (caution.equals("checkbg")) { return "Check BG: " + noCorrection(); }
        if (caution.equals("notread")) { return cautionTitle(caution); }
        var title = cautionTitle(caution);
        // The catch-all's title is the longest: shorter here, on a line that spans the watch.
        if (title.equals("CGM can't be used")) { title = "CGM unusable"; }
        return title + ": " + noCorrection();
    }

    // A dose without the correction, in words: "carbs only", or with carbs off (no carbs in it) "no
    // correction", as on the phone.
    function noCorrection() as Lang.String { return Status.carbsOff() ? "no correction" : "carbs only"; }
    function noCorrectionTitle() as Lang.String { return Status.carbsOff() ? "No correction" : "Carbs only"; }

    // Why the calculator can't give a dose now, or null. "waiting": the pump's settings or IOB haven't
    // arrived fresh. "low"/"high": the CGM reads outside 20–600 mg/dL, and the phone refuses a calculated
    // dose then, so the watch says so before anything is sent.
    function calculatorBlock(now as Lang.Number) as Lang.String? {
        if (mode.equals("carbs") && foodNeedsRedial()) { return "redial"; }
        // The calculator's inputs count while younger than the phone's windows (CalcInputFreshness).
        if (Status.freshField("calculator", "carbRatioMg", Prefs.therapyStaleSeconds(), now) == null
            || Status.freshField("iob", "mU", Prefs.iobStaleSeconds(), now) == null) {
            return "waiting";
        }
        var g = offeredGlucose(now);
        if (g != null && !Calculator.correctable(g)) { return g < Calculator.GLUCOSE_MIN ? "low" : "high"; }
        return null;
    }

    // The calculator's dose in milliunits, rounded down as the phone rounds; -1 when there isn't one.
    function estimate(now as Lang.Number) as Lang.Number {
        if (calculatorBlock(now) != null) { return -1; }
        return estimateFrom(correctionGlucose(now));
    }

    // The stale-reading question applies: a calculator dose with a reading that's stale and may still be
    // included. One too old to include, or outside 20–600, leaves only carbs only: no question, the dose
    // screen says so instead.
    function staleChoiceNeeded(now as Lang.Number) as Lang.Boolean {
        return mode.equals("carbs") && Status.glucose() != null && glucoseStale(now) && staleIncludable(now)
            && Status.glucoseCaution() == null && !foodNeedsRedial();
    }

    // A stale reading may be included only while it's young enough that the phone would include it, and
    // within 20–600 mg/dL.
    function staleIncludable(now as Lang.Number) as Lang.Boolean {
        var g = Status.glucose();
        var age = Status.ageOf("glucose", now);
        return g != null && Calculator.correctable(g) && age != null && age <= Prefs.includableSeconds();
    }

    function dose(now as Lang.Number) as Lang.Number {
        return mode.equals("units") ? unitsMU : estimate(now);
    }

    // The calculator's dose is above the remote limit or the pump's max: the phone would refuse it, so it
    // isn't offered.
    function overLimit(now as Lang.Number) as Lang.Boolean { return dose(now) > dialMax(); }

    // Deliver does something now: it opens the stale-reading or correction question, or arms a dose. Not
    // with no dose, none the calculator can give, or one over the limit, so the button can say so.
    function canDeliver(now as Lang.Number) as Lang.Boolean {
        if (mode.equals("carbs")) {
            if (staleChoiceNeeded(now)) { return true; }
            if (calculatorBlock(now) != null) { return false; }
            if (correctionChoiceNeeded(now)) { return true; }
        }
        var d = dose(now);
        return d >= Calculator.STEP_MU && d <= dialMax();
    }

    // MARK: Starting

    // A new bolus may be started from the watch now.
    function canStart(now as Lang.Number) as Lang.Boolean { return startBlock(now) == null; }

    // Why not, as a short label for the button, or null.
    function startBlock(now as Lang.Number) as Lang.String? {
        if (Link.phoneTooOld()) { return "Update faBolus on phone"; }
        if (Link.watchTooOld()) { return "Update the watch app"; }
        if (!Link.reachable(now)) { return "Phone not connected"; }
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
        _armedInsulin = mode.equals("carbs") && Status.carbsOff();
        _armedFoodMU = foodMU;
        var offered = mode.equals("carbs") ? offeredGlucose(now) : null;
        _armedDecline = declineCorrection && offered != null && offered >= Calculator.LOW_GLUCOSE;
        // The reading the estimate used, or the one the user declined to correct from: the phone holds the
        // answer to that reading, and asks again if its own is another.
        _armedGlucose = _armedDecline ? offered : (mode.equals("carbs") ? correctionGlucose(now) : null);
        _armedIncludeStale = mode.equals("carbs") && includeStale && _armedGlucose != null;
        _armedChoice = null;
        if (correctionChoiceNeeded(now)) {
            var target = Status.field("calculator", "target");
            var above = offered != null && target != null && offered > target;
            // The words on the half the user chose, so the confirm screen matches it exactly.
            _armedChoice = _armedDecline ? (above ? noCorrectionTitle() : "Not reduced") : (above ? "Corrected" : "Reduced");
        }
        _armedConfirmed = [];
        _armedSplit = splitFor(_armedDecline ? null : _armedGlucose);
        return true;
    }

    function armedChoice() as Lang.String? { return _armedChoice; }

    // The armed dose's split for the confirm screen, [food, correction] in milliunits, or null for a units
    // dose: the correction the calculator's (less than zero for a reduction), the food's share the rest of
    // the dose, so the rounding down is in it and the two add up to the dose, as on the phone's review.
    function armedSplit() as Lang.Array<Lang.Number>? { return _armedSplit; }

    // A correction was part of the armed dose (one was computed from a reading).
    function armedCorrects() as Lang.Boolean { return _armedMode.equals("carbs") && !_armedDecline && _armedGlucose != null; }

    // The armed dose's split, from the reading it corrects from (null for none).
    function splitFor(glucose as Lang.Number?) as Lang.Array<Lang.Number>? {
        if (!_armedMode.equals("carbs")) { return null; }
        var doseMU = _armedMU;
        var ratio = Status.field("calculator", "carbRatioMg");
        var isf = Status.field("calculator", "isf");
        var target = Status.field("calculator", "target");
        var iob = Status.field("iob", "mU");
        if (ratio == null || isf == null || target == null || iob == null) { return null; }
        var p = _armedInsulin
            ? Calculator.foodParts(_armedFoodMU, glucose, isf, target, iob)
            : Calculator.parts(_armedCarbs, glucose, ratio, isf, target, iob);
        if (p == null) { return null; }
        var corrD = (p[1] - p[0]) * 1000.0d;
        // To the nearest milliunit: the parts are decimals of a hundredth, and truncating would lose one.
        var corr = (corrD >= 0.0d ? corrD + 0.5d : corrD - 0.5d).toNumber();
        // The whole correction as the calculator has it (a total floored at zero takes the carbs' share).
        var food = doseMU - corr;
        return [food < 0 ? 0 : food, corr];
    }

    // The phone asks the user to confirm something about the pump before this request's dose goes: the
    // same dose may be confirmed again, as a new request naming what was confirmed, while the first is
    // young enough that the user is still at it.
    function confirmable(now as Lang.Number) as Lang.Boolean {
        // One test at a time: a long chain of them stalls the compiler's type checker.
        if (_id == null || _msg == null || _confirm.size() == 0) { return false; }
        if (!_state.equals("failed") && !_state.equals("refused")) { return false; }
        var age = now - _sentAt;
        return age >= 0 && age <= ARM_SEC;
    }

    // Arms the refused request's dose again, with what the phone asked confirmed, for the user's 1 → 2 → 3.
    // False, arming nothing, when it can't be.
    function armConfirmed(now as Lang.Number) as Lang.Boolean {
        var msg = _msg;
        if (!confirmable(now) || msg == null) { return false; }
        var p = Wire.payload(msg);
        var sentMode = Wire.token(p, "mode", ["units", "carbs"]);
        if (sentMode == null) { return false; }
        var armedMU = sentMode.equals("units") ? Wire.int(p, "mU", 0, Wire.MAX_MU) : Wire.int(p, "estimateMU", 0, Wire.MAX_MU);
        if (armedMU == null || armedMU < Calculator.STEP_MU || armedMU > dialMax()) { return false; }
        // The dose on the dial is still this one, so the change check at the last tap compares like with like.
        if (!sentMode.equals(mode)) { return false; }
        _armedMU = armedMU;
        _armedAt = now;
        _armedMode = sentMode;
        var carbsG = Wire.int(p, "carbsG", 0, MAX_CARBS);
        _armedCarbs = carbsG != null ? carbsG : 0;
        var food = Wire.int(p, "foodMU", 0, Wire.MAX_MU);
        _armedInsulin = food != null;
        _armedFoodMU = food != null ? food : 0;
        // Carbs turned on or off since: the request's food means something else now.
        if (sentMode.equals("carbs") && _armedInsulin != Status.carbsOff()) {
            _armedAt = 0;
            return false;
        }
        _armedGlucose = Wire.int(p, "glucoseMgdl", 0, Wire.MAX_GLUCOSE);
        var stale = Wire.bool(p, "includeStaleGlucose");
        _armedIncludeStale = stale != null && stale;
        var decline = Wire.bool(p, "declineCorrection");
        _armedDecline = decline != null && decline;
        _armedConfirmed = _confirm;
        _armedChoice = _sentChoice;
        _armedSplit = splitFor(_armedDecline ? null : _armedGlucose);
        return true;
    }

    function armedConfirmed() as Lang.Array { return _armedConfirmed; }

    function armedDose() as Lang.Number { return _armedMU; }

    // Why the confirmed dose can't be sent now, or null. Checked as the confirm screen draws and again at
    // the last tap, so a dose confirmed against a state that has since moved is never sent.
    function armBlock(now as Lang.Number) as Lang.String? {
        if (_armedAt == 0 || _armedMU < Calculator.STEP_MU) { return "expired"; }
        if (!Prefs.bolusEnabled() || Prefs.readOnly()) { return "off"; }
        if (busy()) { return "busy"; }
        if (!Link.phoneLive(now)) { return "phone"; }
        if (!Status.canBolus()) { return "blocked"; }
        if (now - _armedAt > ARM_SEC) { return "expired"; }
        if (_armedMode.equals("carbs") && (_armedInsulin != Status.carbsOff() || dose(now) != _armedMU)) {
            return "changed";
        }
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
    // What the phone asked to be confirmed before this request's dose goes; empty when nothing.
    var _confirm as Lang.Array = [];

    // Sends the confirmed dose. False, with nothing sent, when it can't go (see armBlock).
    function send(now as Lang.Number) as Lang.Boolean {
        if (armBlock(now) != null) { return false; }
        var id = Link.newRequestId(now);
        // Stamped by the phone's clock, which the phone judges it on; the watch times its own resends and
        // waits by its own.
        var stamp = Status.phoneNow(now);
        var msg = _armedMode.equals("units")
            ? Wire.bolusUnits(id, stamp, _armedMU, _armedConfirmed)
            : Wire.bolusCalculator(id, stamp, _armedInsulin ? null : _armedCarbs, _armedInsulin ? _armedFoodMU : null,
                                   _armedMU, _armedGlucose, _armedIncludeStale, _armedConfirmed, _armedDecline);
        _id = id;
        _sentChoice = _armedChoice;
        _sentAt = now;
        _lastSendAt = now;
        _heardAt = now;
        _msg = msg;
        _requestedMU = _armedMU;
        _deliveredMU = null;
        _text = null;
        _cancelAt = 0;
        _confirm = [];
        _armedAt = 0;
        _armedConfirmed = [];
        if (Link.transmit(msg, new BolusListener(), now)) {
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
        // A clock stepped back would hold the resends and the wait below until it caught up.
        if (now < _lastSendAt) { _lastSendAt = now; }
        if (now < _sentAt) {
            _sentAt = now;
            _heardAt = now;
        }
        // Once the user cancels it, a request the phone hasn't acknowledged isn't sent again; the cancel
        // names it, so a copy already on its way is refused there.
        if (_state.equals("sending") && _cancelAt == 0 && now - _sentAt <= FRESH_SEC
            && now - _lastSendAt >= RESEND_SEC) {
            _lastSendAt = now;
            // Whatever the Bluetooth flag says, which can say no phone while the link works: a resend is
            // the same request, which the phone never delivers twice.
            Link.hand(msg, new BolusListener());
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
        // Only a request that wasn't delivered can be confirmed and sent again.
        var confirm = Wire.tokens(p, "confirm", Wire.CONFIRMATIONS);
        _confirm = (confirm != null && (token.equals("failed") || token.equals("refused"))) ? confirm : [];
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
    // A cancel went out for a bolus that's still going. Shown for CANCEL_SHOW_SEC: the watch hears nothing
    // back about a cancel, so past that the button offers Cancel again rather than say it's in hand. The
    // phone sends one request at a time and gives each 60 s: a cancel can wait that long behind a request
    // the pump hasn't answered, then for the bolus status when the phone has no bolus ID, then for its own
    // answer.
    const CANCEL_SHOW_SEC = 180;
    // Said under the headline once the cancel has gone CANCEL_SLOW_SEC with the bolus still going, as the
    // phone says it. The pump normally answers within a second or two.
    const CANCEL_SLOW_SEC = 5;
    const CANCEL_HINT = "No answer yet. To stop it now, use the pump.";
    function cancelSlow(now as Lang.Number) as Lang.Boolean {
        return cancelling(now) && now - _cancelAt >= CANCEL_SLOW_SEC;
    }
    function cancelling(now as Lang.Number) as Lang.Boolean {
        return _cancelAt != 0 && busy() && now - _cancelAt >= 0 && now - _cancelAt < CANCEL_SHOW_SEC;
    }

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
        // Never gated, not even on the Bluetooth flag: a cancel that can't go comes back as an error.
        var sent = Link.hand(Wire.cancel(Link.newRequestId(now), _id),
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
        _confirm = [];
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
        if (_confirm.size() > 0) { rec["confirm"] = _confirm; }
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
        var confirm = Wire.tokens(rec, "confirm", Wire.CONFIRMATIONS);
        _confirm = confirm != null ? confirm : [];
    }

    // What the request screen says.
    // A cancel in hand shows on the button ("Cancelling"), as on the main screen; the headline stays what the
    // bolus is doing.
    function headline(now as Lang.Number) as Lang.String {
        if (_state.equals("sending")) { return "Sending…"; }
        if (_state.equals("received") || _state.equals("accepted")) { return "Starting…"; }
        if (_state.equals("delivering")) { return "Delivering…"; }
        if (_state.equals("delivered")) { return "Delivered"; }
        if (_state.equals("stopped")) { return "Stopped"; }
        if (_state.equals("refused")) { return "Pump refused"; }
        if (confirmable(now)) { return "Confirm"; }
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
