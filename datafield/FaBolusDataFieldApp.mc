using Toybox.Application as App;
using Toybox.WatchUi as Ui;

// faBolus BG data field (scaffold). A SEPARATE Connect IQ app (manifest type=datafield), built via
// datafield.jungle — it shows glucose as a field on any run/ride activity screen (watches AND Edge
// cycling computers). Wire live BG by subscribing to the faBolus public BG complication (see the
// TODO in FaBolusDataField). Build:
//   monkeyc -f datafield.jungle -o bin/faBolusField.iq -y <dev_key.der> -e -r -w
class FaBolusDataFieldApp extends App.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() { return [ new FaBolusDataField() ]; }
}
