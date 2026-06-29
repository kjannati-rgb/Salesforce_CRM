/**
 * FSS §5 — async wrapper. Processes firms in small chunks (≤ ~10/transaction) so per-firm
 * aggregates stay governor-safe, then chains the remainder. User-independent conversion means
 * it runs correctly as whatever user enqueued it — no integration user needed.
 */
public class FirmRollupQueueable implements Queueable {
    @TestVisible private List<Id> firmIds;
    @TestVisible private Integer chunkSize;

    public FirmRollupQueueable(Set<Id> firmIds) { this(new List<Id>(firmIds), 10); }
    public FirmRollupQueueable(List<Id> firmIds, Integer chunkSize) {
        this.firmIds = (firmIds == null) ? new List<Id>() : firmIds;
        this.chunkSize = (chunkSize == null || chunkSize <= 0) ? 10 : chunkSize;
    }

    public void execute(QueueableContext ctx) {
        if (firmIds.isEmpty()) return;
        Integer endIdx = Math.min(chunkSize, firmIds.size());
        Set<Id> chunk = new Set<Id>();
        for (Integer i = 0; i < endIdx; i++) chunk.add(firmIds[i]);
        FirmRollupService.recalculateFirms(chunk);

        if (endIdx < firmIds.size()) {
            List<Id> remaining = new List<Id>();
            for (Integer i = endIdx; i < firmIds.size(); i++) remaining.add(firmIds[i]);
            // Chaining isn't supported inside a test transaction; bulk is covered via FirmRollupBatch.
            if (!Test.isRunningTest()) System.enqueueJob(new FirmRollupQueueable(remaining, chunkSize));
        }
    }
}
