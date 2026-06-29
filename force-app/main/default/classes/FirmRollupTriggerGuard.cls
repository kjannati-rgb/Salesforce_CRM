/**
 * FSS — recursion guard + emergency kill-switch for the rollup triggers.
 * isSuppressed() is true while the service is mid-recompute (re-entry) or when bypass is set.
 */
public class FirmRollupTriggerGuard {
    @TestVisible public static Boolean bypass = false;
    public static Boolean isSuppressed() {
        return bypass || FirmRollupService.isRunning;
    }
}
