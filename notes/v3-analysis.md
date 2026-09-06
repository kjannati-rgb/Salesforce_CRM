# v3 Analysis — `Create_Contact_from_User`

Source: `baseline/prod/flows/Create_Contact_from_User.flow-meta.xml` (prod v3, retrieved 2026-08-01). Confirmed byte-identical to KJDEV v3 — no drift, Gate 1 passed without a reconciliation deploy.

## 1. `<start>` block

```xml
<start>
    <locationX>50</locationX>
    <locationY>0</locationY>
    <connector>
        <targetReference>Create_Contact</targetReference>
    </connector>
    <object>User</object>
    <recordTriggerType>Create</recordTriggerType>
    <triggerType>RecordAfterSave</triggerType>
</start>
```

- `recordTriggerType` = `Create`, as expected.
- `triggerType` = `RecordAfterSave`, as expected.
- **No `<filters>`** — the flow runs unconditionally on every User creation, with no entry criteria at all. C2/C3 guard logic has to be the first thing that runs.
- Connector goes straight from `<start>` to `Create_Contact`. v4 must insert `Get_Existing_Contact` → `Check_Contact_Prerequisites` between them.

## 2. `<recordCreates>` — `Create_Contact`

Full `<inputAssignments>` list (7 fields):　

| Field | Source |
|---|---|
| `AccountId` | hardcoded literal `0016g00001AQ7lXAAT` (LBR Office account) |
| `Department` | `$Record.Department` |
| `Email` | `$Record.Email` |
| `FirstName` | `$Record.FirstName` |
| `LastName` | `$Record.LastName` |
| `Phone` | `$Record.Phone` |
| `ReportsToId` | `$Record.ManagerId` |

`storeOutputAutomatically` = `true`. No `<faultConnector>` present — confirms C1 is a net-new addition, not a change to an existing one.

Per §8.5 of the runbook, these 7 `<inputAssignments>` are carried into v4 unmodified.

## 3. Existing decisions / lookups / assignments

**None.** No `<decisions>`, `<recordLookups>`, or `<assignments>` elements exist anywhere in v3. `Check_Contact_Prerequisites` and `Get_Existing_Contact` are both wholly new elements in v4, not modifications of existing ones.

## 4. `<apiVersion>`

`55.0`, confirmed. Left unchanged per runbook §8.5 (out of scope to bump).

## 5. Fault connector

Confirmed **absent**. No `<faultConnector>` anywhere in the file — the `Create_Contact` `<recordCreates>` element has no fault handling today, which is exactly the defect C1 fixes.

## 6. Other observations

- One flow variable, `var_flowname` (String, input+output, default `"User: Create Contact from User"`), unused elsewhere in the flow. Legacy, not touched.
- `<status>` = `Active` (v3 is the live version).
- No decisions/loops/subflows of any kind — this is about as minimal an after-save flow as they come, which keeps the v4 diff contained.

## Implications for Phase 4 authoring

- Element names in the runbook's illustrative XML (§8.1–8.4) match what actually needs to be built — no renaming required, since there's nothing pre-existing to reconcile against.
- The new `Get_Existing_Contact` → `Check_Contact_Prerequisites` chain replaces the `<start>` element's direct connector to `Create_Contact`; `Check_Contact_Prerequisites`'s `Safe_To_Create` rule then connects to `Create_Contact` to close the loop.
- Per runbook §8.2 guidance, splitting "blank first name" from "duplicate exists" into two distinct outcomes (rather than one combined `Safe_To_Create` rule with a single default) is worth doing here — it costs one extra decision outcome and one extra notification action, and it's the only way T2 and T3 produce distinguishable evidence in the Phase 6 test matrix.
