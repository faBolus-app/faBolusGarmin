using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.Activity;

// BG data field. A SimpleDataField shows a label + one value in the activity's data layout.
//
// LIMITATION: a data field is a separate Connect IQ app with its own storage, and Connect IQ does
// NOT allow app type 'datafield' to hold the ComplicationSubscriber permission — so a data field
// CANNOT read the faBolus public BG complication (verified: monkeyc rejects ComplicationSubscriber
// for datafield). There is no supported cross-app channel for BG here, so this field always shows
// "--". Use the faBolus WATCH FACE (which can subscribe) or place the public faBolus BG complication
// directly on a complication-capable watch face instead. Kept as a labeled placeholder.
class FaBolusDataField extends Ui.SimpleDataField {
    function initialize() {
        SimpleDataField.initialize();
        label = "faBolus BG";
    }

    function compute(info as Activity.Info) {
        return "--";
    }
}
