# Unshipped: `Renewal_Email_Notification` path on the Opportunity master flow

Recorded 2026-08-16, when `force-app/main/default/flows/Opportunity.flow-meta.xml` was
re-synced from production (v33). The repo copy had drifted and carried wiring that has
**never existed in production**. Re-syncing removed it, so it is captured here rather than
left to git archaeology.

## What was removed

A scheduled path on `<start>` firing 15 minutes after `Created_Date__c`, plus the subflow
element it targeted:

```xml
<scheduledPaths>
    <name>Renewal_Email_Notification</name>
    <connector>
        <targetReference>Renewal_Email_Alert</targetReference>
    </connector>
    <label>Renewal Email Notification</label>
    <offsetNumber>15</offsetNumber>
    <offsetUnit>Minutes</offsetUnit>
    <recordField>Created_Date__c</recordField>
    ...
</scheduledPaths>
```

```xml
<subflows>
    <name>Renewal_Email_Alert</name>
    <label>Renewal Email Alert</label>
    <locationX>3306</locationX>
    <locationY>276</locationY>
    <flowName>EmailAlert_RenewalCreation</flowName>
    <inputAssignments>
        <name>recordId</name>
        <value>
            <elementReference>$Record</elementReference>
        </value>
    </inputAssignments>
</subflows>
```

Full pre-sync file: `git show 3915f76:force-app/main/default/flows/Opportunity.flow-meta.xml`

## The part that needs a decision

**`EmailAlert_RenewalCreation` is ACTIVE in production (v6)** — but production's master flow
does not call it, because the scheduled path above was never deployed. The subflow is live
and, as far as the master flow is concerned, orphaned.

Two readings, and they point opposite ways:

1. The wiring was intended and never shipped → the renewal notification has silently never
   fired from the master flow, and someone is waiting on an email that does not come.
2. The wiring was deliberately rolled back in production → the repo copy was the stale
   leftover, and removing it is simply correct.

Nobody should deploy this from the repo until that is settled. It was deliberately excluded
from the Data Team enrich alert work (see `ClaudeCode_Data_Team_Enrich_Alert_Runbook.md`),
which shipped only its own three changes on top of a fresh production retrieve.

Worth also checking whether anything *else* invokes `EmailAlert_RenewalCreation` in
production before concluding it is dead — this note only establishes that the Opportunity
master flow does not.
