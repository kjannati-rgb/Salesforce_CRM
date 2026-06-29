#!/usr/bin/env bash
# FSS §8.3 — reference scan (trust-but-verify Q9): find every consumer of the four legacy
# Rollup Helper (rh2) fields before any decommission. Run from the repo root.
#   ./scripts/firm-sales-summary/reference_scan.sh [TARGET_ORG]
set -euo pipefail
ORG="${1:-KJDEV}"
FIELDS='(CFY_)?(Val|No)_of_Won_Office_Opportunities__c'

echo "=================================================================="
echo " rh2 reference scan — fields:"
echo "   Val_of_Won_Office_Opportunities__c, No_of_Won_Office_Opportunities__c,"
echo "   CFY_Val_of_Won_Office_Opportunities__c, CFY_No_of_Won_Office_Opportunities__c"
echo "=================================================================="

echo
echo "## 1. Source (repo) references"
grep -REn "$FIELDS" force-app --include='*.xml' --include='*.cls' --include='*.trigger' \
  | grep -vE 'Firm_(Won|Cancellation|Active|Rollup)' || echo "  (none)"

echo
echo "## 2. Org metadata dependencies (Tooling API — catches Reports/ListViews/Flows not in repo)"
sf data query --use-tooling-api --target-org "$ORG" -q \
"SELECT MetadataComponentType, MetadataComponentName, RefMetadataComponentName \
 FROM MetadataComponentDependency \
 WHERE RefMetadataComponentName IN ('Val_of_Won_Office_Opportunities__c','No_of_Won_Office_Opportunities__c','CFY_Val_of_Won_Office_Opportunities__c','CFY_No_of_Won_Office_Opportunities__c') \
 ORDER BY MetadataComponentType" || echo "  (dependency query unavailable)"

echo
echo "Decommission gate: rh2 must NOT be deactivated while any CONSUMER above reads these fields."
