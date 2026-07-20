using Toybox.WatchUi as Ui;
using Toybox.Application.Storage;
using Toybox.Time;
using Toybox.Lang;
using Toybox.Activity;

// BG data field. A SimpleDataField shows a label + one value in the activity's data layout, so this
// renders natively on whatever screen/device the user places it on (watch or Edge).
//
// Data source: a data field is a separate app with its own storage, so it can't read the remote
// app's BG directly. The intended feed is the faBolus PUBLIC BG complication — subscribe to it and
// cache the value into this app's Storage under "bg"/"bgEpoch". That hook is stubbed (see the TODO);
// until it's wired the field shows "--".
class FaBolusDataField extends Ui.SimpleDataField {
    function initialize() {
        SimpleDataField.initialize();
        label = "faBolus BG";
    }

    // TODO(data-field contributor): subscribe to the faBolus public BG complication and cache the
    // reading into Storage. Connect IQ exposes Complications.getComplications() /
    // Complications.subscribeToUpdates(id) + registerComplicationChangeCallback(cb) for consumers;
    // the faBolus complication is published public from source/app/BgComplication.mc.
    function compute(info as Activity.Info) {
        var bg = Storage.getValue("bg");
        var ep = Storage.getValue("bgEpoch");
        var epNum = (ep == null) ? 0 : ep;
        var stale = (bg == null) || (epNum <= 0) || ((Time.now().value() - epNum) > 360);
        return stale ? "--" : bg.toString();
    }
}
