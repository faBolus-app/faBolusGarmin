using Toybox.Lang;

// CONTROL-characteristic notification messages. Port of PumpX2Kit / pumpx2
// DismissNotificationRequest. Signed, non-insulin. Cargo (6 bytes):
//   notificationId (uint32 LE) + notificationTypeId (1) + executeExtraAction (1).
// NotificationType ids: ALERT=1, ALARM=2, CGM_ALERT=3, REMINDER=4, MALFUNCTION=5.
// Opcode 0xB8. Verified byte-exact vs oracle.
module PumpX2 {
    class DismissNotificationRequest extends Message {
        function initialize(notificationId as Lang.Number or Lang.Long, notificationTypeId as Lang.Number, executeExtraAction as Lang.Boolean) {
            Message.initialize();
            opCode = 0xB8;
            characteristic = Ble.CHAR_CONTROL;
            msgType = MsgType.REQUEST;
            signed = true;
            var c = Bytes.toUint32(notificationId);
            c.add(notificationTypeId & 0xFF);
            c.add(executeExtraAction ? 1 : 0);
            cargo = c;
        }
    }
}
