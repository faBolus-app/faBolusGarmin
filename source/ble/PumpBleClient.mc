using Toybox.Lang;
using Toybox.BluetoothLowEnergy as Btle;
using Toybox.System;

// Direct BLE client for the Tandem pump. Port of PumpX2Kit `PumpBLEClient` against CIQ's
// Toybox.BluetoothLowEnergy. Lifecycle: registerProfile -> scan -> pairDevice -> requestBond ->
// (encrypted) subscribe (CCCD writes) -> ready. Inbound notifications are reassembled per
// characteristic and handed to onFrame; outbound messages are framed by Packetize and written
// as a serialized queue (BLE allows one operation in flight at a time).
//
// This is the Gate A gateway. It compiles against the CIQ API but MUST be validated on venu3s
// hardware with the bench pump — the simulator cannot exercise real BLE bonding/notifications.
//
// Callbacks (set by the owner via method(:fn)):
//   onReady()                          -> subscriptions established, ready for messages
//   onFrame(charEnum, frame)           -> a reassembled inbound frame on a characteristic
//   onStateChange(text)                -> human-readable lifecycle progress (for Gate A UI/log)
//   onErrorCb(text)                    -> a lifecycle/transport error
module PumpX2 {
class PumpBleClient extends Btle.BleDelegate {
    // Characteristics we register + subscribe to (subset of what the pump exposes).
    // AUTHORIZATION carries JPAKE; CONTROL/CONTROL_STREAM carry bolus; CURRENT_STATUS/HISTORY_LOG
    // carry reads. QUALIFYING_EVENTS is omitted to stay within CIQ profile limits.
    private var _subChars as Lang.Array<Lang.Number>;

    public var onReady as Lang.Method or Null;
    public var onFrame as Lang.Method or Null;
    public var onStateChange as Lang.Method or Null;
    public var onErrorCb as Lang.Method or Null;

    private var _device as Btle.Device or Null;
    private var _serviceUuid as Btle.Uuid;
    private var _charUuids as Lang.Dictionary;         // charEnum -> Uuid
    private var _reassemblers as Lang.Dictionary;      // charEnum -> PacketReassembler
    private var _txIds as TransactionId;

    private var _opQueue as Lang.Array<Lang.Dictionary>;
    private var _opInFlight as Lang.Boolean = false;
    private var _pendingSubscribes as Lang.Number = 0;
    private var _ready as Lang.Boolean = false;

    // Scan diagnostics (surfaced to the debug screen so we can see what the watch sees).
    private var _scanCount as Lang.Number = 0;
    private var _scanNames as Lang.String = "";

    function initialize() {
        BleDelegate.initialize();
        _subChars = [Ble.CHAR_CURRENT_STATUS, Ble.CHAR_AUTHORIZATION, Ble.CHAR_CONTROL, Ble.CHAR_CONTROL_STREAM, Ble.CHAR_HISTORY_LOG];
        _serviceUuid = Btle.stringToUuid(Ble.PUMP_SERVICE);
        _charUuids = {};
        _reassemblers = {};
        for (var i = 0; i < _subChars.size(); i++) {
            var ce = _subChars[i];
            _charUuids[ce] = Btle.stringToUuid(Ble.charUuid(ce));
            _reassemblers[ce] = new PacketReassembler();
        }
        _txIds = new TransactionId(0);
        _opQueue = [];
    }

    // Registers the delegate + pump profile. Scanning starts once onProfileRegister succeeds.
    function open() as Void {
        Btle.setDelegate(self);
        var chars = [];
        for (var i = 0; i < _subChars.size(); i++) {
            chars.add({ :uuid => _charUuids[_subChars[i]], :descriptors => [Btle.cccdUuid()] });
        }
        try {
            Btle.registerProfile({ :uuid => _serviceUuid, :characteristics => chars });
            _state("registering profile");
        } catch (e) {
            _error("registerProfile failed: " + e.getErrorMessage());
        }
    }

    // ---- BleDelegate callbacks ----

    function onProfileRegister(uuid as Btle.Uuid, status as Btle.Status) as Void {
        if (status != Btle.STATUS_SUCCESS) {
            _error("profile register status " + status.format("%d"));
            return;
        }
        _state("scanning");
        Btle.setScanState(Btle.SCAN_STATE_SCANNING);
    }

    function onScanResults(scanResults as Btle.Iterator) as Void {
        var r = scanResults.next();
        while (r != null) {
            var sr = r as Btle.ScanResult;
            _scanCount += 1;
            var nm = sr.getDeviceName();
            if (nm != null && nm.length() > 0 && _scanNames.find(nm) == null) {
                _scanNames = (_scanNames.length() == 0) ? nm : (_scanNames + "," + nm);
            }
            if (matchesPump(sr)) {
                Btle.setScanState(Btle.SCAN_STATE_OFF);
                _state("pairing " + (nm != null ? nm : "pump"));
                try {
                    _device = Btle.pairDevice(sr);
                } catch (e) {
                    _error("pairDevice failed");
                }
                return;
            }
            r = scanResults.next();
        }
        // No pump match yet — surface what we've seen so it's diagnosable from the watch.
        var msg = "scan " + _scanCount.format("%d");
        if (_scanNames.length() > 0) {
            msg = msg + ": " + _scanNames;
        } else {
            msg = msg + " (no name/FDFB)";
        }
        _state(msg);
    }

    function onScanStateChange(scanState as Btle.ScanState, status as Btle.Status) as Void {
        if (scanState == Btle.SCAN_STATE_SCANNING) {
            _state("scanning (active)");
        }
    }

    function onConnectedStateChanged(device as Btle.Device, state as Btle.ConnectionState) as Void {
        if (state == Btle.CONNECTION_STATE_CONNECTED) {
            _device = device;
            _state("connected; bonding");
            try {
                device.requestBond();
            } catch (e) {
                _error("requestBond failed: " + e.getErrorMessage());
            }
        } else {
            _ready = false;
            _state("disconnected");
        }
    }

    function onEncryptionStatus(device as Btle.Device, status as Btle.Status) as Void {
        if (status != Btle.STATUS_SUCCESS) {
            _error("encryption/bond status " + status.format("%d"));
            return;
        }
        _device = device;
        _state("bonded; subscribing");
        startSubscribing();
    }

    function onCharacteristicChanged(characteristic as Btle.Characteristic, value as Lang.ByteArray) as Void {
        var ce = charEnumOf(characteristic);
        if (ce == null) { return; }
        var ra = _reassemblers[ce];
        var frame = ra.ingest(value);
        if (frame != null && onFrame != null) {
            onFrame.invoke(ce, frame);
        }
    }

    function onCharacteristicWrite(characteristic as Btle.Characteristic, status as Btle.Status) as Void {
        opDone();
    }

    function onDescriptorWrite(descriptor as Btle.Descriptor, status as Btle.Status) as Void {
        if (_pendingSubscribes > 0) {
            _pendingSubscribes -= 1;
            if (_pendingSubscribes == 0 && !_ready) {
                _ready = true;
                _state("ready");
                if (onReady != null) { onReady.invoke(); }
            }
        }
        opDone();
    }

    // ---- sending ----

    // Frames `message` and enqueues its packets for serialized writing on its characteristic.
    // authKey/pumpTimeSinceReset/allowInsulin are passed through to Packetize for signed messages.
    function send(
        message as Message,
        authKey as Lang.ByteArray,
        pumpTimeSinceReset as Lang.Number or Lang.Long,
        allowInsulin as Lang.Boolean
    ) as Void {
        if (_device == null) { _error("send with no device"); return; }
        var ch = characteristicFor(message.characteristic);
        if (ch == null) { _error("no characteristic for message"); return; }
        var packets = Packetize.packetize(message, authKey, _txIds.nextThenIncrement(), pumpTimeSinceReset, allowInsulin, null);
        for (var i = 0; i < packets.size(); i++) {
            _opQueue.add({ :obj => ch, :value => packets[i].build(), :isDesc => false });
        }
        processNext();
    }

    // ---- internals ----

    private function startSubscribing() as Void {
        _pendingSubscribes = 0;
        for (var i = 0; i < _subChars.size(); i++) {
            var ch = characteristicFor(_subChars[i]);
            if (ch == null) { continue; }
            var cccd = ch.getDescriptor(Btle.cccdUuid());
            if (cccd == null) { continue; }
            _pendingSubscribes += 1;
            _opQueue.add({ :obj => cccd, :value => [0x01, 0x00]b, :isDesc => true });
        }
        if (_pendingSubscribes == 0) {
            _error("no subscribable characteristics found");
            return;
        }
        processNext();
    }

    private function processNext() as Void {
        if (_opInFlight || _opQueue.size() == 0) { return; }
        var op = _opQueue[0];
        _opInFlight = true;
        try {
            var value = op[:value] as Lang.ByteArray;
            if (op[:isDesc]) {
                (op[:obj] as Btle.Descriptor).requestWrite(value);
            } else {
                (op[:obj] as Btle.Characteristic).requestWrite(value, { :writeType => Btle.WRITE_TYPE_WITH_RESPONSE });
            }
        } catch (e) {
            _opInFlight = false;
            _error("write failed");
        }
    }

    private function opDone() as Void {
        if (_opQueue.size() > 0) { _opQueue = _opQueue.slice(1, null); }
        _opInFlight = false;
        processNext();
    }

    private function characteristicFor(charEnum as Lang.Number) as Btle.Characteristic or Null {
        if (_device == null) { return null; }
        var svc = _device.getService(_serviceUuid);
        if (svc == null) { return null; }
        return svc.getCharacteristic(_charUuids[charEnum] as Btle.Uuid);
    }

    private function charEnumOf(characteristic as Btle.Characteristic) as Lang.Number or Null {
        var u = characteristic.getUuid().toString();
        for (var i = 0; i < _subChars.size(); i++) {
            if (_charUuids[_subChars[i]].toString().equals(u)) {
                return _subChars[i];
            }
        }
        return null;
    }

    private function matchesPump(scanResult as Btle.ScanResult) as Lang.Boolean {
        // 1) An advertised service UUID containing the pump service (FDFB) or the Mobi TDU
        //    service (FDFA). Substring match tolerates 16-bit vs full-128-bit representations.
        var uuids = scanResult.getServiceUuids();
        var u = uuids.next();
        while (u != null) {
            var s = u.toString().toLower();
            if (s.find("fdfb") != null || s.find("fdfa") != null) { return true; }
            u = uuids.next();
        }
        // 2) Fall back to the advertised device name (Tandem / t:slim / Mobi).
        var nm = scanResult.getDeviceName();
        if (nm != null) {
            var n = nm.toLower();
            if (n.find("tandem") != null || n.find("tslim") != null
                || n.find("t:slim") != null || n.find("mobi") != null) {
                return true;
            }
        }
        return false;
    }

    private function _state(text as Lang.String) as Void {
        System.println("[ble] " + text);
        if (onStateChange != null) { onStateChange.invoke(text); }
    }

    private function _error(text as Lang.String) as Void {
        System.println("[ble][error] " + text);
        if (onErrorCb != null) { onErrorCb.invoke(text); }
    }
}

}
