using Toybox.Lang;
using Toybox.Cryptography;

// Raised when the JPAKE resume handshake gets an unexpected frame or key confirmation fails.
module PumpX2 {
class JpakeAuthException extends Lang.Exception {
    var reason as Lang.String;
    function initialize(reason as Lang.String) {
        Exception.initialize();
        me.reason = reason;
    }
    function getErrorMessage() as Lang.String or Null {
        return "JPAKE resume: " + reason;
    }
}

// On-watch JPAKE "quick-pair" resume coordinator (rounds 3-4 only). Port of the resume branch of
// PumpX2Kit `PairingCoordinator` + `JpakeAuth`. Given a derived secret from a prior full pairing
// (done off-device — see the plan), this completes authentication using only HKDF + HMAC-SHA256,
// both of which CIQ provides. No EC-JPAKE, no 6-digit code.
//
// Flow (client-initiated, over the AUTHORIZATION characteristic):
//   start()  -> send Jpake3SessionKeyRequest
//   handle(Jpake3SessionKeyResponse 0x27): serverNonce3 = payload[0..8];
//       authKey = HKDF(serverNonce3, derivedSecret); send Jpake4KeyConfirmationRequest with
//       hashDigest = HMAC256(clientNonce, authKey)
//   handle(Jpake4KeyConfirmationResponse 0x29): verify HMAC256(serverNonce4, authKey) == serverHash
//       -> paired; authKey is the per-command signing key Packetize uses.
class ResumeCoordinator {
    enum {
        STEP_IDLE,
        STEP_SENT3,
        STEP_SENT4,
        STEP_PAIRED,
        STEP_FAILED,
    }

    const OP_JPAKE3_RESPONSE = 0x27;
    const OP_JPAKE4_RESPONSE = 0x29;

    var step as Lang.Number = STEP_IDLE;
    var authKey as Lang.ByteArray = []b;
    var serverNonce as Lang.ByteArray = []b;

    private var _derivedSecret as Lang.ByteArray;
    private var _appInstanceId as Lang.Number;
    private var _clientNonce as Lang.ByteArray;
    // Optional fixed client nonce for deterministic tests; null -> random 8 bytes at runtime.
    private var _fixedNonce as Lang.ByteArray or Null;

    function initialize(derivedSecret as Lang.ByteArray, appInstanceId as Lang.Number, fixedNonce as Lang.ByteArray or Null) {
        _derivedSecret = derivedSecret;
        _appInstanceId = appInstanceId;
        _fixedNonce = fixedNonce;
        _clientNonce = []b;
    }

    // Begins the handshake; returns the first request to send (Jpake3SessionKeyRequest).
    function start() as Message {
        step = STEP_SENT3;
        return new Jpake3SessionKeyRequest(0);
    }

    // Feeds a reassembled inbound frame [opcode, txId, len, cargo..., crc0, crc1]. Returns the
    // next request Message to send, or null when the handshake completes (check step/authKey).
    // Throws JpakeAuthException on an unexpected frame or failed key confirmation.
    function handle(frame as Lang.ByteArray) as Message or Null {
        if (frame.size() < 5) {
            step = STEP_FAILED;
            throw new JpakeAuthException("malformed frame");
        }
        var opcode = frame[0] & 0xFF;
        var challenge = frameChallenge(frame); // cargo minus the 2-byte appInstanceId prefix

        if (step == STEP_SENT3 && opcode == OP_JPAKE3_RESPONSE) {
            serverNonce = challenge.slice(0, 8);
            authKey = Hkdf.derive(serverNonce, _derivedSecret);
            _clientNonce = (_fixedNonce != null) ? _fixedNonce : Cryptography.randomBytes(8);
            var hashDigest = HmacSha256.mac(authKey, _clientNonce);
            step = STEP_SENT4;
            return new Jpake4KeyConfirmationRequest(_appInstanceId, _clientNonce, new [8]b, hashDigest);
        } else if (step == STEP_SENT4 && opcode == OP_JPAKE4_RESPONSE) {
            var serverNonce4 = challenge.slice(0, 8);
            var serverHash = challenge.slice(16, 48);
            var expected = HmacSha256.mac(authKey, serverNonce4);
            if (!bytesEqual(expected, serverHash)) {
                step = STEP_FAILED;
                throw new JpakeAuthException("key confirmation failed");
            }
            step = STEP_PAIRED;
            return null;
        }

        step = STEP_FAILED;
        throw new JpakeAuthException("unexpected response opcode " + opcode.format("%d"));
    }

    // cargo = frame[3 .. 3+len]; challenge = cargo after the 2-byte appInstanceId prefix.
    private function frameChallenge(frame as Lang.ByteArray) as Lang.ByteArray {
        var len = frame[2] & 0xFF;
        var end = 3 + len;
        var maxEnd = frame.size() - 2; // exclude 2-byte CRC
        if (end > maxEnd) { end = maxEnd; }
        if (end < 5) { return []b; }
        return frame.slice(5, end); // skip [opcode,txId,len] (3) + appInstanceId (2)
    }

    // Constant-time compare (BLE-L2), used at :86 for the JPAKE key-confirmation MAC. Length is
    // not secret, so an early length return is allowed; but for equal-length inputs accumulate a
    // bitwise diff over ALL bytes with NO boolean early-return inside the loop, so the compare's
    // running time does not reveal WHERE the two MACs first differ (timing side-channel). Public
    // so ConstantTimeCompareTest can assert position-independence directly.
    public function bytesEqual(a as Lang.ByteArray, b as Lang.ByteArray) as Lang.Boolean {
        if (a.size() != b.size()) { return false; }
        var diff = 0;
        for (var i = 0; i < a.size(); i++) {
            diff |= (a[i] ^ b[i]) & 0xFF;
        }
        return diff == 0;
    }
}

}
