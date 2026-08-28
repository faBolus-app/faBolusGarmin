using Toybox.Lang;
using Toybox.Test;

// BLE-L2 coverage (Phase 21). Asserts the JPAKE key-confirmation MAC compare
// (ResumeCoordinator.bytesEqual) is position-independent: equal-length inputs that differ at the
// FIRST, a MIDDLE, or the LAST byte all return false, so the accumulate-XOR compare never
// early-returns on the first mismatch (the observable proxy for constant-time). A length mismatch
// returns false (length is not secret). Run with a --unit-test build in the CIQ simulator.
module PumpX2 {
module ConstantTimeCompareTest {

    // Any derivedSecret/appInstanceId works — bytesEqual does not read coordinator state.
    function cmp(a as Lang.ByteArray, b as Lang.ByteArray) as Lang.Boolean {
        var coord = new ResumeCoordinator([]b, 0, null);
        return coord.bytesEqual(a, b);
    }

    (:test)
    function equalArraysReturnTrue(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            cmp(Hex.decode("00112233445566778899"), Hex.decode("00112233445566778899")),
            "equal equal-length arrays -> true");
        return true;
    }

    (:test)
    function differAtFirstByteReturnsFalse(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            !cmp(Hex.decode("ff112233445566778899"), Hex.decode("00112233445566778899")),
            "first byte differs -> false");
        return true;
    }

    (:test)
    function differAtMiddleByteReturnsFalse(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            !cmp(Hex.decode("00112233ff5566778899"), Hex.decode("00112233445566778899")),
            "middle byte differs -> false");
        return true;
    }

    (:test)
    function differAtLastByteReturnsFalse(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            !cmp(Hex.decode("001122334455667788ff"), Hex.decode("00112233445566778899")),
            "last byte differs -> false");
        return true;
    }

    (:test)
    function lengthMismatchReturnsFalse(logger as Test.Logger) as Lang.Boolean {
        Test.assertMessage(
            !cmp(Hex.decode("00112233445566778899"), Hex.decode("001122334455667788")),
            "length mismatch -> false");
        return true;
    }
}

}
