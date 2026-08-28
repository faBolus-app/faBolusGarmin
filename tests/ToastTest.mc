using Toybox.Lang;
using Toybox.Test;

// Phase 20 (F2): the pure toast message-selection helper. The `WatchUi has :showToast` capability branch
// in Toast.show is not unit-drivable (compile-verified), but the message selection is pure and pinned here
// so the wording (and the honest no-auto-retry failure prompt) can't silently drift.
module ToastTest {
    (:test)
    function cancelFeedbackStrings(logger as Test.Logger) as Lang.Boolean {
        Test.assertEqualMessage(Toast.cancelFeedback(true), "Cancel sent", "dispatched -> Cancel sent");
        Test.assertEqualMessage(Toast.cancelFeedback(false), "Not sent — try again", "failed -> manual retry prompt");
        return true;
    }
}
