using Toybox.Application as App;
using Toybox.WatchUi as Ui;

// faBolus watch face (scaffold). A SEPARATE Connect IQ app (manifest type=watch-face), built via
// watchface.jungle — independent of the remote app in source/app/. It shows the time plus a BG
// slot; wire live glucose by subscribing to the faBolus public BG complication (see
// FaBolusFaceView). Build:
//   monkeyc -f watchface.jungle -o bin/faBolusFace.iq -y <dev_key.der> -e -r -w
class FaBolusFaceApp extends App.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() { return [ new FaBolusFaceView() ]; }
}
