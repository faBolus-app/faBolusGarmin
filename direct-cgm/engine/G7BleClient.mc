using Toybox.BluetoothLowEnergy as Btle;
using Toybox.Lang;
using Toybox.Timer;

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

        // Watchdog windows (BLE-M2, WR-01): mirror PumpBleClient's conservative deadlines so a scan
        // that never matches DXCM or a CCCD write that never acks transitions to the terminal
        // fail-closed path instead of hanging indefinitely (draining battery, no failover).
        const SCAN_WATCHDOG_MS = 30000; // no DXCM match within 30s -> terminal + scan OFF
        const OP_WATCHDOG_MS   = 10000; // an in-flight CCCD write not acked within 10s -> terminal

        // callback invoked with the parsed glucose dict from G7Message.parseGlucose.
        public var onGlucose as Lang.Method or Null = null;
        // WR-02: surfaced fail-closed error (the client previously exposed no error callback, so a
        // wedged sequencer was invisible beyond the status string).
        public var onError as Lang.Method or Null = null;
        public var status as Lang.String = "idle";

        private var _svcUuid as Btle.Uuid or Null;
        private var _ctrl as Btle.Uuid or Null;
        private var _back as Btle.Uuid or Null;
        private var _comm as Btle.Uuid or Null;
        private var _device as Btle.Device or Null = null;
        private var _seq as CccdSequencer or Null = null; // BLE-H1 one-op-in-flight CCCD sequencer

        // Watchdog timers (BLE-M2, WR-01): one for the scan phase, one armed per in-flight CCCD write.
        private var _scanTimer as Timer.Timer or Null = null;
        private var _opTimer as Timer.Timer or Null = null;

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
            _armScanWatchdog();
            Btle.setScanState(Btle.SCAN_STATE_SCANNING);
            status = "scanning";
        }

        function onScanResults(results as Btle.Iterator) as Void {
            var r = results.next();
            while (r != null) {
                var sr = r as Btle.ScanResult;
                if (matches(sr)) {
                    _clearScanWatchdog();
                    Btle.setScanState(Btle.SCAN_STATE_OFF);
                    // WR-05: wrap pairDevice (mirror PumpBleClient) — an exception from pairDevice
                    // (bonding state, already-connected, revoked) thrown out of this BLE delegate
                    // callback can crash the probe. Fail closed on throw instead.
                    try {
                        _device = Btle.pairDevice(sr);
                    } catch (e) {
                        _failClosed("pairDevice failed");
                        return;
                    }
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
                if (_seq.isReady()) {
                    _clearOpWatchdog();
                    status = "ready";
                }
                return;
            }
            var cccd = (op as Lang.Dictionary)[:cccd] as Btle.Descriptor;
            // WR-01: arm the per-op watchdog before issuing the write; cleared on its ack.
            _armOpWatchdog();
            cccd.requestWrite((op as Lang.Dictionary)[:value] as Lang.ByteArray);
        }

        // BLE-H1: the ack that chains the serialized CCCD writes. Advance to the next op on success;
        // on a non-success status (WR-02) fail closed — the old code left the sequencer _inFlight
        // forever with no teardown and no surfaced error.
        function onDescriptorWrite(descriptor as Btle.Descriptor, s as Btle.Status) as Void {
            if (_seq == null) { return; }
            _clearOpWatchdog();
            if (s != Btle.STATUS_SUCCESS) {
                _failClosed("cccd-status-" + s.format("%d"));
                return;
            }
            _seq.ack();
            drive();
        }

        // ---- watchdogs + fail-closed terminal path (BLE-M2 / WR-01 / WR-02) ----

        private function _armScanWatchdog() as Void {
            _clearScanWatchdog();
            _scanTimer = new Timer.Timer();
            _scanTimer.start(method(:onScanTimeout), SCAN_WATCHDOG_MS, false);
        }

        private function _clearScanWatchdog() as Void {
            if (_scanTimer != null) {
                _scanTimer.stop();
                _scanTimer = null;
            }
        }

        private function _armOpWatchdog() as Void {
            _clearOpWatchdog();
            _opTimer = new Timer.Timer();
            _opTimer.start(method(:onOpTimeout), OP_WATCHDOG_MS, false);
        }

        private function _clearOpWatchdog() as Void {
            if (_opTimer != null) {
                _opTimer.stop();
                _opTimer = null;
            }
        }

        // Scan deadline elapsed with no DXCM match -> fire the terminal path (scan OFF, fail closed).
        function onScanTimeout() as Void {
            _failClosed("scan timeout");
        }

        // In-flight CCCD write not acked within its window -> fire the terminal path.
        function onOpTimeout() as Void {
            _failClosed("cccd timeout");
        }

        // The single terminal path shared by a pairDevice throw, a CCCD-write failure, and both
        // watchdogs (mirror PumpBleClient._failClosed): stop timers, drop the sequencer so no further
        // writes issue, stop scanning, and surface the error. No indefinite scanning/in-flight state
        // survives this. Passive invariant preserved — only a local setScanState(OFF), no VALUE write.
        private function _failClosed(text as Lang.String) as Void {
            _clearScanWatchdog();
            _clearOpWatchdog();
            _seq = null;
            try {
                Btle.setScanState(Btle.SCAN_STATE_OFF);
            } catch (e) {
            }
            status = text;
            if (onError != null) { onError.invoke(text); }
        }

        // BLE-L1 teardown (CGM twin of BLE-L3): stop scanning + release the BLE delegate on stop so
        // the client leaves no BLE resources held. Best-effort; guards nulls.
        function close() as Void {
            _clearScanWatchdog();
            _clearOpWatchdog();
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
