using Toybox.Lang;
using Toybox.Cryptography;

// HMAC-SHA1, hand-rolled from CIQ's SHA-1 Hash primitive because
// Toybox.Cryptography.HashBasedMessageAuthenticationCode only supports HASH_SHA256.
// HMAC(K, m) = H((K' XOR opad) || H((K' XOR ipad) || m)), block size 64, digest 20 bytes.
// Used by Packetize for the 24-byte signed-message trailer. Validate bytes vs the oracle.
module PumpX2 {
module HmacSha1 {
    const BLOCK = 64;

    // SHA-1 digest (20 bytes) of `data`.
    function sha1(data as Lang.ByteArray) as Lang.ByteArray {
        var h = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA1});
        h.update(data);
        return h.digest();
    }

    // HMAC-SHA1 of `message` under `key`. Returns 20 bytes.
    function mac(key as Lang.ByteArray, message as Lang.ByteArray) as Lang.ByteArray {
        var k = key;
        if (k.size() > BLOCK) {
            k = sha1(k);
        }
        var ipad = new [BLOCK]b;
        var opad = new [BLOCK]b;
        for (var i = 0; i < BLOCK; i++) {
            var kb = (i < k.size()) ? (k[i] & 0xFF) : 0;
            ipad[i] = kb ^ 0x36;
            opad[i] = kb ^ 0x5c;
        }
        var innerInput = ipad;
        innerInput.addAll(message);
        var inner = sha1(innerInput);

        var outerInput = opad;
        outerInput.addAll(inner);
        return sha1(outerInput);
    }
}

}
