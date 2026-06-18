# Account Team Manager — How to add a new role

The Account Team Manager is **config-driven**. No role name is hardcoded anywhere —
the LWC picker, the single-holder guardrail, the audit trail, the reportable mirror,
and the backfill all read `Account_Team_Role_Config__mdt` at runtime. So adding a role
is metadata + config, **never an Apex / trigger / LWC / test change.**

There are two cases. Pick based on whether the new role needs its own reportable
column on Account.

---

## Case A — role with NO dedicated report column (pure config)

Use this for any role you just want available in the component, guard-railed, and
audited — but that doesn't need a `Some_Role__c` lookup on Account for reporting.

1. **Ensure the picklist value exists.** The role string must be an active value in
   the **`TeamRole` standard value set** (Setup → Picklist Value Sets → Team Role).
   If it's brand new, add it there first. It must match the CMDT value **exactly**,
   including punctuation (e.g. `E&I CSM`).

2. **Add one CMDT record** — Setup → Custom Metadata Types → Account Team Role Config →
   Manage Records → New. Or as metadata
   (`customMetadata/Account_Team_Role_Config.<DevName>.md-meta.xml`):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
       xmlns:xsd="http://www.w3.org/2001/XMLSchema"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
       <label>Events CSM</label>                                          <!-- <= 40 chars -->
       <protected>false</protected>
       <values><field>Team_Role__c</field><value xsi:type="xsd:string">Events CSM</value></values>
       <values><field>Default_Account_Access__c</field><value xsi:type="xsd:string">Read</value></values>
       <values><field>Badge_Background__c</field><value xsi:type="xsd:string">#FDECEC</value></values>
       <values><field>Badge_Text_Color__c</field><value xsi:type="xsd:string">#8A1C1C</value></values>
       <values><field>Sort_Order__c</field><value xsi:type="xsd:double">40.0</value></values>
       <values><field>Active__c</field><value xsi:type="xsd:boolean">true</value></values>
       <values><field>Single_Holder__c</field><value xsi:type="xsd:boolean">true</value></values>
       <!-- omit Mirror_To_Account_Field__c entirely for Case A -->
   </CustomMetadata>
   ```

   - `Single_Holder__c = true` → at most one active holder per account (blocked at the
     data layer). Set `false` for roles that may have several.

**Done.** The role now appears in the component's picker with its badge colours, is
guard-railed if you flagged it, and every add/remove/role-change is audited — with no
code change.

---

## Case B — role you also want as a reportable Account field

Do everything in Case A, **plus** give the role its own Account lookup so account-team
composition is reportable (the raw `AccountTeamMember` object is not reportable).

3. **Add one Account User-lookup field**
   (`objects/Account/fields/<Role>_CSM__c.field-meta.xml`):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
       <fullName>Events_CSM__c</fullName>
       <label>Events CSM</label>
       <type>Lookup</type>
       <referenceTo>User</referenceTo>
       <relationshipLabel>Accounts (Events CSM)</relationshipLabel>
       <relationshipName>Events_CSM_Accounts</relationshipName>   <!-- must be unique on User -->
       <required>false</required>
       <deleteConstraint>SetNull</deleteConstraint>
       <description>Reportable mirror of the active "Events CSM" team member. Read-only - do not edit directly.</description>
   </CustomField>
   ```

4. **Point the CMDT record at it** — add to the record from step 2:

   ```xml
   <values><field>Mirror_To_Account_Field__c</field><value xsi:type="xsd:string">Events_CSM__c</value></values>
   ```

5. **Grant FLS** on the new field in **both** permission sets (read-only):
   - `Account_Team_Manager` (so CSMs see it)
   - `Account_Team_Reporting` (so the DPO / CS leadership can report on it)

   ```xml
   <fieldPermissions>
       <field>Account.Events_CSM__c</field>
       <readable>true</readable>
       <editable>false</editable>
   </fieldPermissions>
   ```

6. **If the role already has members**, run the backfill once so existing teams
   populate the new field immediately (otherwise it fills in only as teams change):

   ```apex
   Database.executeBatch(new AccountTeamMirrorBackfillBatch(), 200);
   ```

The trigger handler and backfill read the field name from the CMDT mapping and use
dynamic `put`/`get`, so the new field flows through automatically — **still no Apex
change.**

---

## What you never touch
`AccountTeamManagerController`, `AccountTeamMemberTriggerHandler`,
`AccountTeamMemberTrigger`, `AccountTeamMirrorBackfillBatch`, the `accountTeamManager`
LWC, or the test classes. They are all generic over the CMDT config.

## Gotchas
- **Exact match:** `Team_Role__c` must equal the `TeamRole` picklist value character-for-character (watch `&` → write `&amp;` in XML, e.g. `E&amp;I CSM`).
- **CMDT label ≤ 40 chars** (MasterLabel limit); DeveloperName ≤ 40 too.
- **CMDT records need the `xmlns:xsd` namespace** on the root or the deploy fails with a generic `UNKNOWN_EXCEPTION`.
- **New fields deploy with no FLS** — even System Admins can't see them until granted (step 5). Reports respect FLS.
- **One Account field per mirrored role** — that's a Salesforce reality (a reportable column needs a real field), not a limit of the design. Non-mirrored roles cost nothing.
- **ChurnZero** reads the team for CS ownership and keys on specific roles — if a new role should feed ChurnZero, that's a ChurnZero-side mapping, separate from Salesforce.
