using Toybox.BluetoothLowEnergy as Btle;
using Toybox.Lang;

// Passive Dexcom G7 / ONE+ BLE client for the watch (Connect IQ), modeled on the paused
// direct-pump/engine/ble/PumpBleClient.mc. Lifecycle: registerProfile -> scan (name "DXCM") ->
// pairDevice -> subscribe to the control + backfill + communication notifications -> decode.
// It NEVER writes to the authentication or control value characteristics — the official Dexcom app
// owns the session; we only listen, so we don't disconnect it. Read-only failover.
//
// STATUS: paused / compile-verified only (see direct-cgm/DIRECT_CGM_STATUS.md). CIQ BLE can't be
// validated in the simulator; this needs an on-device test with a live G7.
module DirectCgm {
    class G7BleClient extends Btle.BleDelegate {
        const SERVICE   = "F8083532-849E-531C-C594-30F1F86A4EA5";
        const CHAR_COMM = "F8083533-849E-531C-C594-30F1F86A4EA5"; // Read/Notify
        const CHAR_CTRL = "F8083534-849E-531C-C594-30F1F86A4EA5"; // Write/Indicate — glucoseTx here
        const CHAR_BACK = "F8083536-849E-531C-C594-30F1F86A4EA5"; // Read/Write/Notify — backfill

        // callback invoked with the parsed glucose dict from G7Message.parseGlucose.
        public var onGlucose as Lang.Method or Null = null;
        public var status as Lang.String = "idle";

        private var _svcUuid as Btle.Uuid or Null;
        private var _ctrl as Btle.Uuid or Null;
        private var _back as Btle.Uuid or Null;
        private var _comm as Btle.Uuid or Null;
        private var _device as Btle.Device or Null = null;

        function initialize() { BleDelegate.initialize(); }

        function start() as Void {
            Btle.setDelegate(self);
            _svcUuid = Btle.stringToUuid(SERVICE);
            _ctrl = Btle.stringToUuid(CHAR_CTRL);
            _back = Btle.stringToUuid(CHAR_BACK);
            _comm = Btle.stringToUuid(CHAR_COMM);
            try {
                Btle.registerProfile({
                    :uuid => _svcUuid,
                    :characteristics => [
                        { :uuid => _ctrl, :descriptors => [Btle.cccdUuid()] },
                        { :uuid => _back, :descriptors => [Btle.cccdUuid()] },
                        { :uuid => _comm, :descriptors => [Btle.cccdUuid()] },
                    ]
                });
                status = "registering";
            } catch (e) {
                status = "register-failed";
            }
        }

        function onProfileRegister(uuid as Btle.Uuid, s as Btle.Status) as Void {
            Btle.setScanState(Btle.SCAN_STATE_SCANNING);
            status = "scanning";
        }

        function onScanResults(results as Btle.Iterator) as Void {
            var r = results.next();
            while (r != null) {
                var sr = r as Btle.ScanResult;
                if (matches(sr)) {
                    Btle.setScanState(Btle.SCAN_STATE_OFF);
                    _device = Btle.pairDevice(sr);
                    status = "connecting";
                    return;
                }
                r = results.next();
            }
        }

        // G7 advertises a device name beginning with "DXCM".
        private function matches(sr as Btle.ScanResult) as Lang.Boolean {
            var name = sr.getDeviceName();
            return (name != null) && (name.length() >= 4) && name.substring(0, 4).equals("DXCM");
        }

        function onConnectedStateChanged(device as Btle.Device, state as Btle.ConnectionState) as Void {
            if (state == Btle.CONNECTION_STATE_CONNECTED) {
                _device = device;
                status = "connected";
                subscribe();
            } else {
                status = "disconnected";
            }
        }

        // Enable notifications on the notify characteristics (a local CCCD write, not sensor auth).
        private function subscribe() as Void {
            if (_device == null) { return; }
            var svc = _device.getService(_svcUuid);
            if (svc == null) { return; }
            var uuids = [_ctrl, _back, _comm];
            for (var i = 0; i < uuids.size(); i += 1) {
                var ch = svc.getCharacteristic(uuids[i]);
                if (ch == null) { continue; }
                var cccd = ch.getDescriptor(Btle.cccdUuid());
                if (cccd != null) { cccd.requestWrite([0x01, 0x00]b); }
            }
        }

        function onCharacteristicChanged(characteristic as Btle.Characteristic, value as Lang.ByteArray) as Void {
            var uuid = characteristic.getUuid();
            if (uuid.equals(_ctrl)) {
                var m = G7Message.parseGlucose(value);
                if (m != null && m[:glucose] != null && m[:reliable] && onGlucose != null) {
                    onGlucose.invoke(m);
                }
            }
        }
    }
}
