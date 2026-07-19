using Toybox.Lang;

// Empty-cargo CURRENT_STATUS reads (unsigned). Port of the read-path request messages from
// PumpX2Kit `Requests/`. Each is just an opcode on the CURRENT_STATUS characteristic with no
// cargo; the response opcode is opcode+1. Opcodes verified byte-exact against the oracle.

module PumpX2 {
class EmptyCurrentStatusRequest extends Message {
    function initialize(opcode as Lang.Number) {
        Message.initialize();
        me.opCode = opcode;
        me.characteristic = Ble.CHAR_CURRENT_STATUS;
        me.msgType = MsgType.REQUEST;
        // cargo stays empty
    }
}

class ApiVersionRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x20); }
}

class ControlIQIOBRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x6C); }
}
class NonControlIQIOBRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x26); }
}
class InsulinStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x24); }
}
class CurrentBatteryV2Request extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x90); }
}
class CurrentBasalStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x28); }
}
class HomeScreenMirrorRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x38); }
}
class PumpVersionRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x54); }
}
class TimeSinceResetRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x36); }
}
class CurrentBolusStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x2C); }
}
class LastBolusStatusV2Request extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0xA4); }
}
class ControlIQInfoV2Request extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0xB2); }
}
class LastBGRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x32); }
}
class PumpGlobalsRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x56); }
}
class PumpSettingsRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x52); }
}
class BolusCalcDataSnapshotRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x72); }
}
class AlertStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x44); }
}
class AlarmStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x46); }
}
class MalfunctionStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x76); }
}
class HistoryLogStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x3A); }
}
class CGMAlertStatusRequest extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0x4A); }
}

// CurrentEGVGuiDataV2 (CGM reading) request — read-path, empty cargo. Opcode 0xC0.
class CurrentEgvGuiDataV2Request extends EmptyCurrentStatusRequest {
    function initialize() { EmptyCurrentStatusRequest.initialize(0xC0); }
}

}
