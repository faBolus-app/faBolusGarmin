using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.Activity;

// BG data field. A SimpleDataField shows a label + one value in the activity's data layout.
//
// LIMITATION (structural, not transient): a data field is a separate Connect IQ app, and Connect IQ
// does NOT allow app type 'datafield' to hold the ComplicationSubscriber permission — so this field
// CANNOT read the faBolus public BG complication (verified: monkeyc rejects ComplicationSubscriber
// for datafield), and there is no other supported cross-app BG channel here. It therefore can NEVER
// receive a reading, on ANY of its target devices.
//
// P16 §1.3 (fail-graceful): surface an explicit "N/A" — an unavailable indicator — rather than a bare
// "--". Everywhere the app CAN show BG (glance, in-app screens, the complication string), a bare "--"
// is the honest STALENESS/no-reading marker: a working surface that just has no fresh value right now.
// Showing that same "--" on a surface that can never get data reads as "working, between readings" — a
// lie. "N/A" says the capability is unavailable HERE. Use the faBolus WATCH FACE (which CAN subscribe),
// or drop the public faBolus BG complication onto a complication-capable watch face instead.
class FaBolusDataField extends Ui.SimpleDataField {
    function initialize() {
        SimpleDataField.initialize();
        label = "faBolus BG";
    }

    // Structurally cannot receive BG on this app type (see above) → an explicit unavailable indicator,
    // never a bare "--" that would read as a real (fresh/between-readings) value.
    function compute(info as Activity.Info) {
        return "N/A";
    }
}
