using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Timer;
using Toybox.Lang;

// Compact glance shown in the widget/glance carousel: "faBolus" + last-known BG. It reads the same
// persisted values the app/complication write (`bg` / `bgEpoch`), so it shows a reading without
// opening the app. Runs in the limited glance-memory context, so state (bg/bgEpoch/staleSec/the
// display-unit token) is read directly from Storage rather than depending on AppState's loaded
// instance fields (which may not be populated yet in this context — mirrors the existing staleSec
// pattern). P-mmol (Phase 4): the display-unit CONVERSION MATH itself still routes through
// AppState's pure displayGlucoseForUnit()/glucoseUnitLabelForToken() funnel (the token-parameterized
// siblings of displayGlucose()/glucoseUnitLabel()) rather than a second inline "/ 18.0182" — the one
// glucose-text site this phase's Anti-Pattern section calls out by name as having bypassed the
// funnel; fixed here without adding a fourth independent implementation.
// A reading older than 6 minutes shows "--".
(:glance)
class FaBolusGlanceView extends Ui.GlanceView {
    private var _timer as Timer.Timer?;

    function initialize() { GlanceView.initialize(); }

    // R3 (Phase 20): self-refresh while the glance is on screen, using the unused venu3s
    // glance.liveUpdates capability, mirroring ClockView.onShow/onHide/onTick. onUpdate re-reads Storage
    // (bg/bgEpoch/staleSec), so a periodic requestUpdate re-evaluates the value's STALENESS against the
    // clock — a visible glance no longer freezes between the ~5-min background temporal polls. Display
    // only; no dose path touched.
    function onShow() as Void {
        if (_timer == null) { _timer = new Timer.Timer(); }
        _timer.start(method(:onTick), 30000, true);   // 30 s, matching ClockView
        // R3: additionally kick ONE best-effort statusRead on appearance so the glance pulls a fresh value
        // (matching ClockView.onShow). Fully guarded — RemoteComm.send's existing phoneReachable()+try/catch
        // makes it a no-op when offline or if the glance runtime restricts Comm.transmit (degrade to
        // timer-only self-refresh, never a crash). NOT a new repeating radio wake — a single kick on show.
        RemoteComm.send(RemoteComm.statusRead(RemoteComm.newRoutineRequestId()));
    }

    // Stop the redraw timer when the glance is hidden (battery — no ticking off-screen).
    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function onTick() as Void { Ui.requestUpdate(); }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var vl = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.30, Gfx.FONT_TINY, "faBolus", vl);

        var bg = Storage.getValue("bg");
        var ep = Storage.getValue("bgEpoch");
        var epNum = (ep == null) ? 0 : ep;
        // GA-08: honor the phone-synced, persisted staleness window (not a hardcoded 6 min) so the glance
        // matches the in-app screens. Falls back to 360 s only until the first statusRead persists it.
        var ss = Storage.getValue("staleSec");
        var staleSec = (ss instanceof Lang.Number && ss > 0) ? ss : 360;
        var stale = (bg == null) || (epNum <= 0) || ((Time.now().value() - epNum) > staleSec);
        // P-mmol: the unit token is read directly from Storage (same reasoning as staleSec above),
        // guarded to a recognized "mgdl"|"mmol" token (fail-closed to mgdl otherwise/absent, D-04).
        var gu = Storage.getValue("glucoseDisplayUnit");
        var unitToken = (gu instanceof Lang.String && AppState.isValidUnitToken(gu as Lang.String)) ? gu : "mgdl";
        var text = stale ? "--" : (AppState.displayGlucoseForUnit(bg as Lang.Number, unitToken) + " " + AppState.glucoseUnitLabelForToken(unitToken));
        dc.setColor(stale ? Gfx.COLOR_LT_GRAY : 0x8AB4FF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.70, Gfx.FONT_MEDIUM, text, vl);
    }
}
