using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi as Ui;

// The screens, in the order the phone sets, and the bolus flow's pushes.
module Nav {
    function viewFor(id as Lang.String) as [Ui.Views, Ui.InputDelegates] {
        if (id.equals("alerts")) { return [new AlertsListView(), new AlertsListDelegate()]; }
        if (id.equals("history")) { return [new CgmView(), new CgmDelegate()]; }
        if (id.equals("details")) { return [new DetailsView(), new DetailsDelegate()]; }
        if (id.equals("glucose")) { return [new MainView(false), new MainDelegate(false, "glucose")]; }
        if (id.equals("clock")) { return [new ClockView(), new ScreenDelegate("clock")]; }
        if (id.equals("bolusonly")) { return [new BolusOnlyView(), new BolusOnlyDelegate()]; }
        return [new MainView(true), new MainDelegate(true, "glance")];
    }

    function initialView() as [Ui.Views, Ui.InputDelegates] { return viewFor(Prefs.defaultScreen()); }

    function indexOf(id as Lang.String) as Lang.Number {
        var order = Prefs.screenOrder();
        for (var i = 0; i < order.size(); i += 1) {
            var o = order[i];
            if (o instanceof Lang.String && o.equals(id)) { return i; }
        }
        return -1;
    }

    // Next and previous in the order; at either end the swipe is swallowed.
    function goNext(current as Lang.String) as Lang.Boolean {
        var order = Prefs.screenOrder();
        var i = indexOf(current);
        if (i < 0 || i + 1 >= order.size()) { return true; }
        var vd = viewFor(order[i + 1] as Lang.String);
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_UP);
        return true;
    }

    function goPrev(current as Lang.String) as Lang.Boolean {
        var order = Prefs.screenOrder();
        var i = indexOf(current);
        if (i <= 0) { return true; }
        var vd = viewFor(order[i - 1] as Lang.String);
        Ui.switchToView(vd[0], vd[1], Ui.SLIDE_DOWN);
        return true;
    }

    // The bolus button. With a bolus to cancel it cancels; otherwise it opens entry when a bolus may start.
    function pressBolus() as Void { pressBolusAt(Status.now()); }

    // Separate from pressBolus so tests can drive the clock.
    function pressBolusAt(now as Lang.Number) as Void {
        if (BolusFlow.canCancel()) {
            Toast.show(BolusFlow.cancel(now) ? "Cancel sent" : "Not sent — try again");
            Ui.requestUpdate();
            return;
        }
        if (!BolusFlow.canStart(now)) {
            // The phone hasn't answered lately: ask it now rather than at the next poll, which can be two
            // minutes off, so the button opens as soon as it answers.
            if (!Link.phoneLive(now)) {
                Toast.show(Controller.checkPhone(now) ? "Checking phone…" : "Not sent — try again");
                Ui.requestUpdate();
            }
            return;
        }
        BolusFlow.forgetIfSettled();
        BolusFlow.reset();
        // The entry's dose and gate rest on what the phone says now: ask it at once, with a fresh CGM read.
        Controller.checkPhone(now);
        if (!introShown()) {
            Store.save(Store.INTRO_SHOWN, true);
            Ui.pushView(new BolusIntroView(), new BolusIntroDelegate(), Ui.SLIDE_LEFT);
            return;
        }
        var v = new BolusEntryView();
        Ui.pushView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
    }

    function introShown() as Lang.Boolean {
        var v = Storage.getValue(Store.INTRO_SHOWN);
        return v instanceof Lang.Boolean && v;
    }

    function continueToEntry() as Void {
        var v = new BolusEntryView();
        Ui.switchToView(v, new BolusEntryDelegate(v), Ui.SLIDE_LEFT);
    }

    // The 1 → 2 → 3 confirm (touch) or the two-button hold.
    function openConfirm(replace as Lang.Boolean) as Void {
        var v = new HoldView();
        var d = new HoldDelegate(v);
        if (replace) { Ui.switchToView(v, d, Ui.SLIDE_LEFT); } else { Ui.pushView(v, d, Ui.SLIDE_LEFT); }
    }

    // An alert's card, new or tapped in the list.
    function pushAlert(a as Lang.Dictionary) as Void {
        var v = new AlertNoticeView(a);
        Ui.pushView(v, new AlertCardDelegate(v), Ui.SLIDE_UP);
    }

    function isTouch() as Lang.Boolean {
        var s = System.getDeviceSettings();
        return (s has :isTouchScreen) ? (s.isTouchScreen == true) : false;
    }

    function inRect(x as Lang.Numeric, y as Lang.Numeric, r as Lang.Array<Lang.Numeric>) as Lang.Boolean {
        return x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3];
    }

    function screenSize() as [Lang.Number, Lang.Number] {
        var s = System.getDeviceSettings();
        return [s.screenWidth, s.screenHeight];
    }
}

module Toast {
    function show(text as Lang.String) as Void {
        if (Ui has :showToast) { Ui.showToast(text, null); }
    }
}

// Swipes between the screens, for a screen with nothing else to press.
class ScreenDelegate extends Ui.BehaviorDelegate {
    private var _id as Lang.String;
    function initialize(id as Lang.String) {
        BehaviorDelegate.initialize();
        _id = id;
    }
    function onNextPage() as Lang.Boolean { return Nav.goNext(_id); }
    function onPreviousPage() as Lang.Boolean { return Nav.goPrev(_id); }
}
