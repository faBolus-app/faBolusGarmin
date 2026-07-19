using Toybox.Lang;
using Toybox.Test;

// Byte-exact parity tests against the cliparser oracle. Every ported outgoing message must
// serialize to the same packet bytes the upstream library produces (see tools/gen_golden.sh and
// tests/golden_vectors.txt). These are the tests that make the hand-port trustworthy — mirrors
// PumpX2Kit's OracleParityTests. Run with a --unit-test build in the CIQ simulator.
module ParityTest {
    // Shared signing constants — identical to gen_golden.sh / OracleParityTests so signed
    // packets match byte-for-byte.
    const PAIRING_CODE = "6VeDeRAL5DCigGw2";
    const PUMP_TIME = 461589180;
    // 32-byte key material used by the crypto vectors.
    const KM = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899";

    // Joins packet hex with commas, matching the oracle's packets array formatting.
    function packetsHex(packets as Lang.Array<Packet>) as Lang.String {
        var s = "";
        for (var i = 0; i < packets.size(); i++) {
            if (i > 0) { s += ","; }
            s += Hex.encode(packets[i].build());
        }
        return s;
    }

    function unsignedHex(msg as Message, txId as Lang.Number) as Lang.String {
        return packetsHex(Packetize.packetize(msg, []b, txId, 0, false, null));
    }

    function signedHex(msg as Message, txId as Lang.Number) as Lang.String {
        var key = Bytes.fromAscii(PAIRING_CODE);
        return packetsHex(Packetize.packetize(msg, key, txId, PUMP_TIME, true, null));
    }

    // ---- CRC-16 ----

    (:test)
    function crc16MatchesApiVersionFrame(logger as Test.Logger) as Lang.Boolean {
        // CRC-16 over the ApiVersionRequest frame header [0x20,0x00,0x00] must be [0x5a,0x4a].
        var crc = Crc16.calculate([0x20, 0x00, 0x00]b);
        Test.assertEqualMessage(crc[0], 0x5a, "crc lo");
        Test.assertEqualMessage(crc[1], 0x4a, "crc hi");
        return true;
    }

    // ---- ApiVersion + empty-cargo status reads ----

    (:test)
    function apiVersionRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(unsignedHex(new ApiVersionRequest(), 0), "00002000005a4a", "ApiVersionRequest");
        return true;
    }

    (:test)
    function emptyStatusReadsMatchOracle(logger as Test.Logger) as Lang.Boolean {
        // [message, expectedHex] at txId 11.
        var cases = [
            [new ControlIQIOBRequest(),        "000b6c0b006cfe"],
            [new NonControlIQIOBRequest(),     "000b260b000024"],
            [new InsulinStatusRequest(),       "000b240b00604a"],
            [new CurrentBatteryV2Request(),    "000b900b005f68"],
            [new CurrentBasalStatusRequest(),  "000b280b00013f"],
            [new HomeScreenMirrorRequest(),    "000b380b00627c"],
            [new PumpVersionRequest(),         "000b540b006892"],
            [new TimeSinceResetRequest(),      "000b360b006367"],
            [new CurrentBolusStatusRequest(),  "000b2c0b00c1e3"],
            [new LastBolusStatusV2Request(),   "000ba40b003a71"],
            [new ControlIQInfoV2Request(),     "000bb20b00f980"],
            [new LastBGRequest(),              "000b320b00a3bb"],
            [new PumpGlobalsRequest(),         "000b560b0008fc"],
            [new PumpSettingsRequest(),        "000b520b00c820"],
            [new BolusCalcDataSnapshotRequest(), "000b720b000ea6"],
            [new AlertStatusRequest(),         "000b440b000bd1"],
            [new AlarmStatusRequest(),         "000b460b006bbf"],
            [new MalfunctionStatusRequest(),   "000b760b00ce7a"],
            [new HistoryLogStatusRequest(),    "000b3a0b000212"],
            [new CGMAlertStatusRequest(),      "000b4a0b000aca"],
        ];
        for (var i = 0; i < cases.size(); i++) {
            var msg = cases[i][0] as Message;
            var expected = cases[i][1] as Lang.String;
            Test.assertEqualMessage(unsignedHex(msg, 11), expected, "status read " + i);
        }
        return true;
    }

    // ---- variable-cargo / multi-packet ----

    (:test)
    function historyLogRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(unsignedHex(new HistoryLogRequest(1000, 10), 8),
            "00083c0805e80300000a4eb5", "HistoryLogRequest");
        return true;
    }

    (:test)
    function centralChallengeRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var msg = new CentralChallengeRequest(0, Hex.decode("00112233445566778899"));
        Test.assertEqualMessage(unsignedHex(msg, 1), "000110010a000000112233445566773152", "CentralChallengeRequest");
        return true;
    }

    (:test)
    function pumpChallengeRequestMatchesOracleMultiPacket(logger as Test.Logger) as Lang.Boolean {
        var msg = new PumpChallengeRequest(0, Hex.decode("0102030405060708090a0b0c0d0e0f1011121314"));
        Test.assertEqualMessage(unsignedHex(msg, 2),
            "010212021600000102030405060708090a0b0c0d,00020e0f1011121314d5ec", "PumpChallengeRequest");
        return true;
    }

    (:test)
    function jpake4KeyConfirmationRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var msg = new Jpake4KeyConfirmationRequest(
            0,
            Hex.decode("0001020304050607"),
            Hex.decode("0000000000000000"),
            Hex.decode("6465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80818283"));
        Test.assertEqualMessage(unsignedHex(msg, 6),
            "0306280632000000010203040506070000000000,02060000006465666768696a6b6c6d6e6f707172,0106737475767778797a7b7c7d7e7f8081828324,000664",
            "Jpake4KeyConfirmationRequest");
        return true;
    }

    // ---- signed bolus flow ----

    (:test)
    function bolusPermissionRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(signedHex(new BolusPermissionRequest(), 0),
            "0000a20018bc4a831be223d1eae35cb8592e99e44467cbc8b836de2f2b1618", "BolusPermissionRequest");
        return true;
    }

    (:test)
    function cancelBolusRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(signedHex(new CancelBolusRequest(10650), 3),
            "0003a0031c9a290000bc4a831b4d6002a7da3b65cb852610656f19aa5343a80fcbcd6c", "CancelBolusRequest");
        return true;
    }

    (:test)
    function bolusPermissionReleaseRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(signedHex(new BolusPermissionReleaseRequest(10650), 4),
            "0004f0041c9a290000bc4a831b413c8c34275a8da78ef2ac757a419a28762d7715ed84", "BolusPermissionReleaseRequest");
        return true;
    }

    // The crown jewel: a 1.0u standard bolus initiate, signed, byte-exact vs the oracle.
    (:test)
    function initiateBolusRequestMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var msg = new InitiateBolusRequest(1000, 42, 1, 0, 0, 0, 0, 0);
        Test.assertEqualMessage(signedHex(msg, 9),
            "01099e093de80300002a0000000100000000000000000000000000000000000000000000000000000000,0009bc4a831bd14b869bef2b177bbf71e52b32723bda389e5227539c",
            "InitiateBolusRequest");
        return true;
    }

    // ---- packet reassembly round-trip ----

    (:test)
    function reassemblerRoundTripMultiPacket(logger as Test.Logger) as Lang.Boolean {
        // A multi-packet signed message reassembles to the concatenation of every packet's
        // internal cargo (the full framed message + CRC).
        var packets = Packetize.packetize(
            new InitiateBolusRequest(1000, 42, 1, 0, 0, 0, 0, 0),
            Bytes.fromAscii(PAIRING_CODE), 9, PUMP_TIME, true, null);
        var expected = []b;
        for (var i = 0; i < packets.size(); i++) {
            expected.addAll(packets[i].internalCargo);
        }
        var ra = new PacketReassembler();
        var frame = null;
        for (var i = 0; i < packets.size(); i++) {
            frame = ra.ingest(packets[i].build());
        }
        Test.assertMessage(frame != null, "expected a completed frame");
        Test.assertEqualMessage(Hex.encode(frame), Hex.encode(expected), "reassembled frame");
        return true;
    }

    // ---- auth primitives (HKDF / HMAC-SHA256) ----

    (:test)
    function hkdfMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var out = Hkdf.derive(Hex.decode("0011223344556677"), Hex.decode(KM));
        Test.assertEqualMessage(Hex.encode(out),
            "94b85a87b2aeaaf96bd55cf53002507cbe4061fad2341be666937b58f81aa3aa", "hkdf");
        return true;
    }

    (:test)
    function hkdfEmptyNonceMatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var out = Hkdf.derive([]b, Hex.decode(KM));
        Test.assertEqualMessage(Hex.encode(out),
            "d6d9ffd65369303bf0758077e60b4fce2afe2ea40f61d87a1afeb9db53ba65e9", "hkdf empty nonce");
        return true;
    }

    (:test)
    function hmacSha256MatchesOracle(logger as Test.Logger) as Lang.Boolean {
        var out = HmacSha256.mac(Hex.decode("0011223344556677"), Hex.decode("01"));
        Test.assertEqualMessage(Hex.encode(out),
            "1c0211b08a58d56bea687ee19fb928282138d3dbd14a6396e2fffd16d4b28bfe", "hmac-sha256");
        var out2 = HmacSha256.mac(Hex.decode(KM), Hex.decode("0001020304050607"));
        Test.assertEqualMessage(Hex.encode(out2),
            "ca0aa0ad0b63c6b030412df26aceb16a14fdac3d41df7a45d11b823d38563bc8", "hmac-sha256 b");
        return true;
    }
}
