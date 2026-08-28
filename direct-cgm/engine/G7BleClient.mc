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
    // Characteristic-kind tags for the pure cccdValueFor() mapping (BLE-H2). CHAR_CTRL is an
    // INDICATE characteristic (needs CCCD 0x0002); _comm/_back are NOTIFY (CCCD 0x0001). Declared at
    // module scope so the static cccdValueFor() and G7CccdTest can reference them without an instance.
    const KIND_CTRL = 0;
    const KIND_COMM = 1;
    const KIND_BACK = 2;

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
        private var _seq as CccdSequencer or Null = null; // BLE-H1 one-op-in-flight CCCD sequencer

        function initialize() { BleDelegate.initialize(); }

        // BLE-H2: the CCCD value must match the characteristic PROPERTY. An indicate characteristic
        // needs [0x02,0x00]; a notify characteristic needs [0x01,0x00]. CHAR_CTRL is Write/Indicate
        // (glucose is parsed from _ctrl), so it gets the indicate bit; _comm/_back are notify.
        // Pure + static so G7CccdTest can assert the mapping byte-for-byte without a Btle stack.
        static function cccdValueFor(kind as Lang.Number) as Lang.ByteArray {
            if (kind == KIND_CTRL) { return [0x02, 0x00]b; } // indicate
            return [0x01, 0x00]b;                            // notify (CHAR_COMM / CHAR_BACK)
        }

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

        // BLE-L1: do NOT scan on a non-success profile register (mirror PumpBleClient). Surface the
        // status as an error instead of blindly scanning.
        function onProfileRegister(uuid as Btle.Uuid, s as Btle.Status) as Void {
            if (s != Btle.STATUS_SUCCESS) {
                status = "register-status-" + s.format("%d");
                return;
            }
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

        // BLE-H1/H2: enable the CCCD subscriptions through a SERIALIZED one-op-in-flight queue
        // (CIQ GATT allows only one operation in flight). Each CCCD write carries the per-
        // characteristic value from cccdValueFor() (indicate for _ctrl, notify for _comm/_back).
        // These are LOCAL descriptor writes only — the client never writes the sensor auth/control
        // VALUE characteristics, so it stays passive and cannot disconnect the official Dexcom app.
        private function subscribe() as Void {
            if (_device == null) { return; }
            var svc = _device.getService(_svcUuid);
            if (svc == null) { return; }
            // Deterministic order: control (indicate) first, then backfill + comm (notify).
            var specs = [
                { :uuid => _ctrl, :kind => KIND_CTRL },
                { :uuid => _back, :kind => KIND_BACK },
                { :uuid => _comm, :kind => KIND_COMM },
            ];
            var ops = [];
            for (var i = 0; i < specs.size(); i += 1) {
                var spec = specs[i] as Lang.Dictionary;
                var ch = svc.getCharacteristic(spec[:uuid] as Btle.Uuid);
                if (ch == null) { continue; }
                var cccd = ch.getDescriptor(Btle.cccdUuid());
                if (cccd == null) { continue; }
                ops.add({ :cccd => cccd, :value => cccdValueFor(spec[:kind] as Lang.Number) });
            }
            if (ops.size() == 0) {
                status = "no-characteristics";
                return;
            }
            _seq = new CccdSequencer(ops);
            status = "subscribing";
            drive();
        }

        // Issue the head CCCD write, if any. Called on subscribe() and after each onDescriptorWrite
        // ack — so exactly one descriptor write is in flight at a time.
        private function drive() as Void {
            if (_seq == null) { return; }
            var op = _seq.next();
            if (op == null) {
                if (_seq.isReady()) { status = "ready"; }
                return;
            }
            var cccd = (op as Lang.Dictionary)[:cccd] as Btle.Descriptor;
            cccd.requestWrite((op as Lang.Dictionary)[:value] as Lang.ByteArray);
        }

        // BLE-H1: the ack that chains the serialized CCCD writes. Advance to the next op on success;
        // on a non-success status surface it and stop (no further writes).
        function onDescriptorWrite(descriptor as Btle.Descriptor, s as Btle.Status) as Void {
            if (_seq == null) { return; }
            if (s != Btle.STATUS_SUCCESS) {
                status = "cccd-status-" + s.format("%d");
                return;
            }
            _seq.ack();
            drive();
        }

        // BLE-L1 teardown (CGM twin of BLE-L3): stop scanning + release the BLE delegate on stop so
        // the client leaves no BLE resources held. Best-effort; guards nulls.
        function close() as Void {
            _seq = null;
            try {
                Btle.setScanState(Btle.SCAN_STATE_OFF);
            } catch (e) {
            }
            try {
                // The SDK types setDelegate() as non-null, but passing null is the runtime idiom for
                // releasing the delegate; cast to satisfy the typechecker.
                Btle.setDelegate(null as Btle.BleDelegate);
            } catch (e) {
            }
            status = "stopped";
        }

        // Alias for close() — teardown entry point.
        function stop() as Void {
            close();
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
