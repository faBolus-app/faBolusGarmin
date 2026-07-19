using Toybox.Lang;

// HISTORY_LOG request messages. Port of PumpX2Kit `HistoryLogRequests`.

// Requests a run of history-log records starting at `startLog`. Cargo is 5 bytes:
// startLog (uint32 LE) + numberOfLogs (1 byte). Opcode 0x3C. Verified byte-exact vs oracle.
class HistoryLogRequest extends Message {
    function initialize(startLog as Lang.Number or Lang.Long, numberOfLogs as Lang.Number) {
        Message.initialize();
        me.opCode = 0x3C;
        me.characteristic = Ble.CHAR_CURRENT_STATUS;
        me.msgType = MsgType.REQUEST;
        var c = Bytes.toUint32(startLog);
        c.add(numberOfLogs & 0xFF);
        me.cargo = c;
    }
}
