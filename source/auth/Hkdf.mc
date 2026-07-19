using Toybox.Lang;

// HKDF-SHA256 as implemented upstream (`Hkdf.build`): extract with salt = nonce,
// IKM = keyMaterial, empty info, output length 32:
//   PRK = HMAC-SHA256(key = nonce, data = keyMaterial)
//   out = HMAC-SHA256(key = PRK,   data = [0x01])
// An empty nonce becomes 32 zero bytes as the salt (matches upstream newSecretKeySpec).
// Port of PumpX2Kit `Crypto.hkdf`. Used to derive the per-session auth key:
//   authKey = HKDF(serverNonce, derivedSecret).
module Hkdf {
    function derive(nonce as Lang.ByteArray, keyMaterial as Lang.ByteArray) as Lang.ByteArray {
        var salt = nonce;
        if (salt.size() == 0) {
            salt = new [32]b;
        }
        var prk = HmacSha256.mac(salt, keyMaterial);
        return HmacSha256.mac(prk, [0x01]b);
    }
}
