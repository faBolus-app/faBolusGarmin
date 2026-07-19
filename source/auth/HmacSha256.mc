using Toybox.Lang;
using Toybox.Cryptography;

// HMAC-SHA256 via CIQ's native HashBasedMessageAuthenticationCode (HASH_SHA256 is the only
// algorithm it supports — which is exactly what the pump auth uses). Port of PumpX2Kit
// `Crypto.hmacSha256`. Upstream's mod255 normalization is a no-op on bytes, so this is standard.
module HmacSha256 {
    // HMAC-SHA256(message) under `key`. Returns 32 bytes.
    function mac(key as Lang.ByteArray, message as Lang.ByteArray) as Lang.ByteArray {
        var h = new Cryptography.HashBasedMessageAuthenticationCode({
            :algorithm => Cryptography.HASH_SHA256,
            :key => key,
        });
        h.update(message);
        return h.digest();
    }
}
