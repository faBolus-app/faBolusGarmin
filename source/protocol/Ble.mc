using Toybox.Lang;

// Pump BLE GATT identifiers and MTU. Port of PumpX2Kit `ServiceUUID` / `Characteristic`.
module Ble {
    // Tandem TIP service (primary messaging service) and TDU service (Mobi).
    const PUMP_SERVICE = "0000FDFB-0000-1000-8000-00805F9B34FB";
    const TDU_SERVICE  = "0000FDFA-0000-1000-8000-00805F9B34FB";

    // MTU the Tandem app negotiates (upstream requests 185). CIQ does not expose requestMtu, so
    // framing must not assume this; kept for reference.
    const PREFERRED_MTU = 185;

    // Characteristic identity (enum) — used for chunk sizing and routing.
    enum {
        CHAR_CURRENT_STATUS,
        CHAR_QUALIFYING_EVENTS,
        CHAR_HISTORY_LOG,
        CHAR_AUTHORIZATION,
        CHAR_CONTROL,
        CHAR_CONTROL_STREAM,
    }

    // Characteristic UUID strings, indexed by the CHAR_* enum above.
    const CHAR_UUIDS = [
        "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9", // CURRENT_STATUS
        "7B83FFF7-9F77-4E5C-8064-AAE2C24838B9", // QUALIFYING_EVENTS
        "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9", // HISTORY_LOG
        "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9", // AUTHORIZATION
        "7B83FFFC-9F77-4E5C-8064-AAE2C24838B9", // CONTROL
        "7B83FFFD-9F77-4E5C-8064-AAE2C24838B9", // CONTROL_STREAM
    ] as Lang.Array<Lang.String>;

    function charUuid(characteristic as Lang.Number) as Lang.String {
        return CHAR_UUIDS[characteristic];
    }
}
