using Toybox.Lang;
using Toybox.Test;

// Tests for the on-watch JPAKE resume coordinator (rounds 3-4). The handshake uses a random
// client nonce in production, so we inject a fixed nonce and cross-check every derived value
// against numbers computed by the cliparser oracle (hkdf / hmac-sha256) — the same primitives
// the coordinator relies on, already proven byte-exact in ParityTest.
module PumpX2 {
module ResumeTest {
    const DS = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899";
    const CLIENT_NONCE = "2122232425262728";
    const AUTHKEY = "445c7bfe07856083146b626f4c3fe910dfef95e56088d11e48070a0a3c3d65ee";
    const HASHDIGEST = "e79cd10a2396855c00763670c787b27df10d7d1a160ef3f3d18456d03b3c0274";
    const SERVER_HASH = "31c1259270a0aa508e9230bdf4b38b4504bd776309c08c97d9bb4fd6ff9c1130";

    // Jpake3SessionKeyResponse frame: [0x27,txId,len(0x12)] + appInstanceId(0000) +
    // serverNonce3(1112131415161718) + reserved(8 zeros) + crc(0000).
    const FRAME3 = "270012" + "0000" + "1112131415161718" + "0000000000000000" + "0000";
    // Jpake4KeyConfirmationResponse frame: [0x29,txId,len(0x32)] + appInstanceId(0000) +
    // serverNonce4(3132333435363738) + reserved(8) + serverHash(32) + crc(0000).
    const FRAME4 = "290032" + "0000" + "3132333435363738" + "0000000000000000" + SERVER_HASH + "0000";

    (:test)
    function resumeHandshakeDerivesOracleAuthKey(logger as Test.Logger) as Lang.Boolean {
        var coord = new ResumeCoordinator(Hex.decode(DS), 0, Hex.decode(CLIENT_NONCE));

        // start() -> Jpake3SessionKeyRequest (opcode 0x26, cargo = challengeParam 0 as 2 LE bytes)
        var req3 = coord.start();
        Test.assertEqualMessage(req3.opCode, 0x26, "req3 opcode");
        Test.assertEqualMessage(Hex.encode(req3.cargo), "0000", "req3 cargo");

        // Feed the server's round-3 response; expect authKey = HKDF(serverNonce3, derivedSecret)
        // and a round-4 request carrying HMAC256(clientNonce, authKey).
        var req4 = coord.handle(Hex.decode(FRAME3));
        Test.assertEqualMessage(Hex.encode(coord.authKey), AUTHKEY, "authKey == oracle hkdf");
        Test.assertMessage(req4 != null, "expected a round-4 request");
        Test.assertEqualMessage(req4.opCode, 0x28, "req4 opcode");
        var expectedCargo = "0000" + CLIENT_NONCE + "0000000000000000" + HASHDIGEST;
        Test.assertEqualMessage(Hex.encode(req4.cargo), expectedCargo, "req4 cargo (key confirmation)");

        // Feed the server's round-4 confirmation; expect it verifies and we reach PAIRED.
        var done = coord.handle(Hex.decode(FRAME4));
        Test.assertMessage(done == null, "paired handshake returns null");
        Test.assertEqualMessage(coord.step, ResumeCoordinator.STEP_PAIRED, "step == PAIRED");
        return true;
    }

    (:test)
    function resumeRejectsBadKeyConfirmation(logger as Test.Logger) as Lang.Boolean {
        var coord = new ResumeCoordinator(Hex.decode(DS), 0, Hex.decode(CLIENT_NONCE));
        coord.start();
        coord.handle(Hex.decode(FRAME3));
        // Corrupt the server hash (flip the last byte) -> verification must fail.
        var badHash = SERVER_HASH.substring(0, SERVER_HASH.length() - 2) + "00";
        var badFrame = "290032" + "0000" + "3132333435363738" + "0000000000000000" + badHash + "0000";
        var threw = false;
        try {
            coord.handle(Hex.decode(badFrame));
        } catch (e instanceof JpakeAuthException) {
            threw = true;
        }
        Test.assertMessage(threw, "expected JpakeAuthException on bad confirmation");
        Test.assertEqualMessage(coord.step, ResumeCoordinator.STEP_FAILED, "step == FAILED");
        return true;
    }
}

}
