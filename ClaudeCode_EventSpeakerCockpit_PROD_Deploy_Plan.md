# Event Speaker Cockpit — PROD Deploy Plan

Branch: `event-speaker-cockpit` (built off `salesforce-opp-automation`)
Status: verified in KJDEV and FULLUAT. This plan promotes to PROD.

## 1. What ships

| Component | Type | Notes |
|---|---|---|
| `EventSpeakerCockpitController` | Apex | thin `@AuraEnabled` facade |
| `EventSpeakerCockpitService` | Apex | business logic, `WITH SECURITY_ENFORCED` + `stripInaccessible` throughout |
| `EventSpeakerCockpitControllerTest` | Apex test | 8 methods, governor-tested to 200 records in one bulk call |
| `eventSpeakerRosterBoard` | LWC | the kanban board — stat bar, search, missing-item filter, pagination, bulk-select, chip toggles, click-through to Contact/record |
| `speakerReadinessPanel` | LWC | companion panel on the individual record page, same chip language as the board |
| `EventSpeakerCockpit_TestPage` | FlexiPage (App Page) | standalone hub, not tied to any one Campaign |
| `EventSpeakerCockpit_TestPage` | CustomTab | points at the App Page above |
| `Event_Speaker_Management_Record_Page1` | FlexiPage (Record Page) | **PROD variant differs from KJDEV/FULLUAT — see §3** |
| `Event_Speaker_Management_Access` | PermissionSet | extended with Apex class access, 3 field permissions, 2 tab-visibility entries |
| `standard__LightningSales` app nav | not in git | one `<tabs>` line added directly to the org, same as KJDEV/FULLUAT — see §4 |

**Explicitly not going to PROD:**
- `EventSpeakerCockpit_CampaignPreview` FlexiPage — was a KJDEV-only admin debugging page, scoped to my profile only, never meant to ship.
- `Event_Speaker_Cockpit_Access` PermissionSet — test-only tab-visibility grant for my own KJDEV testing. PROD access comes entirely from the real `Event_Speaker_Management_Access` permset, which already covers the real team.

## 2. Pre-flight checks already done

- **Apex naming collision**: none. No `EventSpeakerCockpit*` class exists in PROD today.
- **Permission set drift**: retrieved PROD's current `Event_Speaker_Management_Access` and diffed it against the file in this branch. Clean — the only differences are the additions this branch makes (class access, 3 field grants, 2 tab entries). Nothing PROD-specific would be clobbered.
- **Real users already on the permset**: 20 total, 15 active (Denise Rossa, Richard Adderley, Sukie Leung, Francesca Tyrrell, Peter Musavaya, Lauren Harvey, Emily Hynd, Greg Storan, Holly Wyld, Cheryl Pak, Sophia Williams, Samantha Richardson, Ailina Liuhe, Olivia Nardell, Miah Whittle). Deploying the extended permset gives all of them the new Apex/field/tab access automatically — no separate assignment step needed for the real team.
- **Data volume**: 20,966 real `Event_Speaker_Management__c` records in PROD. No demo/test data will be created there.
- **Record page drift**: diffed PROD's current `Event_Speaker_Management_Record_Page1` against the KJDEV/FULLUAT-derived version in this branch. One real difference found (not drift, a genuine environment difference) — see §3.

## 3. Record page — PROD-specific handling

KJDEV and FULLUAT's Einstein Discovery panel on this page pointed at a prediction definition that resolved to nothing (`No Predictions Available`), so it was removed there as dead weight when the page was modernized.

PROD's copy of the same panel references `mlpd_Speaker_Confirmation_v0`, which is a real `MLPredictionDefinition` with **Status: Enabled**. Sandboxes generally don't carry live Einstein Discovery models on refresh, which is the likely reason it looked dead everywhere else but may not be in PROD.

**Decision (confirmed with Kamyar): keep the Einstein panel in PROD.**

The PROD deploy of this FlexiPage will therefore differ from the committed KJDEV/FULLUAT version: it adds the `speakerReadinessPanel` component in the same place (top of `main`, above the tabset), but does **not** remove the `einsteinDiscoveryPanel` block. This PROD-only variant will be built at deploy time from a fresh PROD retrieve (not from the KJDEV-committed file) and is not merged back into the branch, since it's an environment-specific difference, not a code change.

## 4. Deploy sequence

Same order used successfully in FULLUAT:

1. **Apex** (`EventSpeakerCockpitController`, `EventSpeakerCockpitService`, `EventSpeakerCockpitControllerTest`) with `RunSpecifiedTests` scoped to just `EventSpeakerCockpitControllerTest` — deliberately not `RunLocalTests`, since PROD is known to carry pre-existing unrelated red tests and a scoped test run avoids being blocked by them.
2. **LWC** (`eventSpeakerRosterBoard`, `speakerReadinessPanel`).
3. **FlexiPage + CustomTab** (`EventSpeakerCockpit_TestPage` app page + tab).
4. **Record page** (`Event_Speaker_Management_Record_Page1`) — built fresh per §3, Einstein panel retained.
5. **Permission set** (`Event_Speaker_Management_Access`, extended) — grants the real 15 active users everything at once.
6. **Sales app nav** — retrieve PROD's `standard__LightningSales`, add the one `<tabs>` line, dry-run, deploy. Requires your explicit go-ahead at execution time, same as it did for FULLUAT (this edits shared nav for real live users, not a sandbox).

## 5. Verification approach in PROD (read-only by default)

Unlike FULLUAT, I will **not** click-test writes against real PROD records unless you explicitly ask for it. Verification will be:
- Confirm the Apex test run passed and coverage is reported.
- Confirm the tab appears in the Sales app nav (for a user with the permset — likely me if I get assigned, or ask one of the 15 to check).
- Load the cockpit against a real, already-scheduled event and visually confirm the roster, stat bar, and chip states render correctly — no chip clicks, no bulk actions.
- Open one real speaker's record and confirm the readiness panel renders correctly *and* the Einstein panel is still present and unchanged.

If you want a live write/revert test like the one I did in FULLUAT (toggle-and-immediately-revert), say so explicitly — I won't do it by default in PROD.

## 6. Rollback

Everything except the record page and the Sales app nav line is purely additive (new Apex, new LWC, new FlexiPage, new tab, additive permset changes) — rollback is deleting/deactivating those components, no risk to existing functionality.

- **Record page**: revert to the pre-deploy retrieve (taken immediately before deploying in step 4) to restore the exact prior state.
- **Sales app nav**: remove the single `<tabs>EventSpeakerCockpit_TestPage</tabs>` line and redeploy.
- **Permission set**: the additions (class access, 3 fields, 2 tab entries) can be removed in one deploy; this does not touch the pre-existing grants.

## 7. Open items before executing

- **Sign-off**: this org's convention (per prior features) is to get explicit sign-off before PROD deploys of user-facing changes. Recommend at minimum your own go-ahead on timing, and ideally a quick heads-up to whoever owns the event production team given 15 of them get new tab access and a changed record page the moment this ships.
- **Timing**: no maintenance window strictly required (all changes are additive or low-risk), but avoid deploying during an active live event if one of the 20,966 existing records is mid-event today.
