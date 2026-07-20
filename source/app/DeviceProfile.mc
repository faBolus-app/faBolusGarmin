using Toybox.System;
using Toybox.Lang;

// Single source of truth for what the current Garmin device can do, so no screen has to assume a
// specific device (e.g. the venu3s touchscreen). Everything is derived at runtime from
// System.getDeviceSettings(), which means supporting a new device is usually just adding its
// <iq:product> to manifest.xml — the screens adapt themselves here.
module DeviceProfile {

    // Touchscreen devices (venu3s, edge1040/1050, …) drive the UI with taps. Button-only devices
    // (fenix, Forerunner, Instinct, edge530/540, …) drive it with the physical buttons + a focus
    // cursor. Every interactive screen branches on this instead of assuming touch.
    function isTouch() as Lang.Boolean {
        var s = System.getDeviceSettings();
        return (s has :isTouchScreen) ? (s.isTouchScreen == true) : false;
    }

    function isButtons() as Lang.Boolean { return !isTouch(); }

    // Watch-face complications exist only on watches. Cycling computers (Edge) have no watch face,
    // so the BG complication (and its background refresh) is a no-op there. Note the complication
    // *resource* is also excluded for such devices in monkey.jungle.
    function hasComplications() as Lang.Boolean { return (Toybox has :Complications); }
}
