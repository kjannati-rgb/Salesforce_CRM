/**
 * Captures point-in-time Account Plan snapshots for QBR trend reporting (architecture §10).
 * One Plan_Snapshot__c per plan per day (idempotent upsert by External_Key), recording the headroom
 * roll-ups and cell composition so trend ("headroom won/lost since last QBR") can be charted and reported.
 * Callable from Apex, Flow (@InvocableMethod) and the PlanSnapshotSchedule scheduled job.
 */
public with sharing class PlanSnapshotService {

    private static final Set<String> GAP_STATES = new Set<String>{
        'White_Space', 'Candidate', 'Win_Back', 'No_Engagement'
    };

    @InvocableMethod(label='Capture Account Plan Snapshots'
                     description='Capture the latest headroom snapshot for the given plans')
    public static List<Integer> captureInvocable(List<Id> planIds) {
        Set<Id> ids = (planIds == null) ? new Set<Id>() : new Set<Id>(planIds);
        return new List<Integer>{ capture(ids, Date.today()) };
    }

    /** Snapshot every active plan as of today (the scheduled-job entry point). */
    public static Integer captureAllActive() {
        Set<Id> ids = new Set<Id>();
        for (Account_Plan__c p : [SELECT Id FROM Account_Plan__c WHERE Plan_Status__c = 'Active']) {
            ids.add(p.Id);
        }
        return capture(ids, Date.today());
    }

    /** @return number of snapshots written. */
    public static Integer capture(Set<Id> planIds, Date asOf) {
        if (planIds == null || planIds.isEmpty()) {
            return 0;
        }
        Map<Id, Account_Plan__c> plans = new Map<Id, Account_Plan__c>([
            SELECT Id, Plan_Tier__c, Segment__c, Total_ARR__c, Headroom__c, Family_Coverage_Pct__c
            FROM Account_Plan__c WHERE Id IN :planIds
        ]);
        if (plans.isEmpty()) {
            return 0;
        }

        Map<Id, Integer> ownedCells = new Map<Id, Integer>();
        Map<Id, Integer> whitespaceCells = new Map<Id, Integer>();
        for (Whitespace_Cell__c c : [
            SELECT Account_Plan__c, ARR__c, State__c
            FROM Whitespace_Cell__c WHERE Account_Plan__c IN :planIds
        ]) {
            if (c.ARR__c != null && c.ARR__c > 0) {
                ownedCells.put(c.Account_Plan__c,
                    (ownedCells.containsKey(c.Account_Plan__c) ? ownedCells.get(c.Account_Plan__c) : 0) + 1);
            }
            if (GAP_STATES.contains(c.State__c)) {
                whitespaceCells.put(c.Account_Plan__c,
                    (whitespaceCells.containsKey(c.Account_Plan__c) ? whitespaceCells.get(c.Account_Plan__c) : 0) + 1);
            }
        }

        String dayKey = String.valueOf(asOf);
        List<Plan_Snapshot__c> snapshots = new List<Plan_Snapshot__c>();
        for (Account_Plan__c p : plans.values()) {
            snapshots.add(new Plan_Snapshot__c(
                Account_Plan__c = p.Id,
                Snapshot_Date__c = asOf,
                Total_ARR__c = p.Total_ARR__c,
                Headroom__c = p.Headroom__c,
                Family_Coverage_Pct__c = p.Family_Coverage_Pct__c,
                Owned_ARR_Cells__c = ownedCells.containsKey(p.Id) ? ownedCells.get(p.Id) : 0,
                Whitespace_Cells__c = whitespaceCells.containsKey(p.Id) ? whitespaceCells.get(p.Id) : 0,
                Plan_Tier__c = p.Plan_Tier__c,
                Segment__c = p.Segment__c,
                External_Key__c = p.Id + '|' + dayKey));
        }
        upsert snapshots External_Key__c;
        return snapshots.size();
    }
}
