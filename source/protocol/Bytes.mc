using Toybox.Lang;

// Endian-aware numeric/byte conversions. Port of the little-endian helpers in PumpX2Kit
// `Bytes` (upstream com.jwoglom.pumpx2.pump.messages.helpers.Bytes). All multi-byte pump cargo
// values are little-endian. Reads return Long where the value can exceed the signed 32-bit
// Number range (uint32/uint64); writes accept Number or Long.
module Bytes {

    // ---- combining / slicing ----

    // Concatenates an Array of ByteArrays into one ByteArray.
    function combine(parts as Lang.Array<Lang.ByteArray>) as Lang.ByteArray {
        var out = []b;
        for (var i = 0; i < parts.size(); i++) {
            out.addAll(parts[i]);
        }
        return out;
    }

    // A zero-filled ByteArray of the given size.
    function empty(size as Lang.Number) as Lang.ByteArray {
        return new [size]b;
    }

    // ---- writes (little-endian) ----

    // Low two bytes of `v`, little-endian (Swift `firstTwoBytesLittleEndian`).
    function toUint16(v as Lang.Number or Lang.Long) as Lang.ByteArray {
        return [(v & 0xFF).toNumber(), ((v >> 8) & 0xFF).toNumber()]b;
    }

    // 4-byte little-endian (Swift `toUint32`). Works for Number or Long, incl. high-bit-set values.
    function toUint32(v as Lang.Number or Lang.Long) as Lang.ByteArray {
        return [
            (v & 0xFF).toNumber(),
            ((v >> 8) & 0xFF).toNumber(),
            ((v >> 16) & 0xFF).toNumber(),
            ((v >> 24) & 0xFF).toNumber(),
        ]b;
    }

    // 8-byte little-endian (Swift `toUint64`).
    function toUint64(v as Lang.Long) as Lang.ByteArray {
        var out = new [8]b;
        for (var k = 0; k < 8; k++) {
            out[k] = ((v >> (8 * k)) & 0xFF).toNumber();
        }
        return out;
    }

    // ---- reads (little-endian) ----

    // Unsigned 16-bit at offset i.
    function readUint16(raw as Lang.ByteArray, i as Lang.Number) as Lang.Number {
        return ((raw[i + 1] & 0xFF) << 8) | (raw[i] & 0xFF);
    }

    // Unsigned 32-bit at offset i, as a Long (0 .. 2^32-1).
    function readUint32(raw as Lang.ByteArray, i as Lang.Number) as Lang.Long {
        return (raw[i] & 0xFF).toLong()
            | ((raw[i + 1] & 0xFF).toLong() << 8)
            | ((raw[i + 2] & 0xFF).toLong() << 16)
            | ((raw[i + 3] & 0xFF).toLong() << 24);
    }

    // Unsigned 64-bit at offset i, as a Long.
    function readUint64(raw as Lang.ByteArray, i as Lang.Number) as Lang.Long {
        var v = 0l;
        for (var k = 0; k < 8; k++) {
            v = v | ((raw[i + k] & 0xFF).toLong() << (8 * k));
        }
        return v;
    }

    // ASCII string -> ByteArray (each char's low byte). Pump pairing codes are ASCII.
    function fromAscii(s as Lang.String) as Lang.ByteArray {
        var chars = s.toCharArray();
        var out = new [chars.size()]b;
        for (var i = 0; i < chars.size(); i++) {
            out[i] = chars[i].toNumber() & 0xFF;
        }
        return out;
    }
}

// Hex encode/decode used by tests and debug logging.
module Hex {
    const DIGITS = "0123456789abcdef";

    // Lowercase hex string of a ByteArray.
    function encode(bytes as Lang.ByteArray) as Lang.String {
        var s = "";
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] & 0xFF;
            s += DIGITS.substring(b >> 4, (b >> 4) + 1);
            s += DIGITS.substring(b & 0xF, (b & 0xF) + 1);
        }
        return s;
    }

    // Parses an even-length lowercase/uppercase hex string into a ByteArray.
    function decode(hex as Lang.String) as Lang.ByteArray {
        var chars = hex.toLower().toCharArray();
        var out = new [chars.size() / 2]b;
        for (var i = 0; i < out.size(); i++) {
            out[i] = (nibble(chars[2 * i]) << 4) | nibble(chars[2 * i + 1]);
        }
        return out;
    }

    function nibble(c as Lang.Char) as Lang.Number {
        var v = c.toNumber(); // code point
        if (v >= 0x30 && v <= 0x39) { return v - 0x30; }      // 0-9
        if (v >= 0x61 && v <= 0x66) { return v - 0x61 + 10; } // a-f
        if (v >= 0x41 && v <= 0x46) { return v - 0x41 + 10; } // A-F
        return 0;
    }
}
