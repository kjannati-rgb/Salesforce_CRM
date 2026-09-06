#!/usr/bin/env bash
# Grace-period cleanup for the Contact Role Check rebuild.
# Deletes the dormant validation rule and prunes obsolete/draft flow versions in LBR_PROD.
# Safe to re-run. Aborts if the new flows are not the active versions or the VR is still active.
set -uo pipefail
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
cd /c/sf-work/kjdev || exit 1
ORG=LBR_PROD

echo "== Safety checks =="
ACTIVE_CC=$(sf data query --use-tooling-api -o $ORG --json -q "SELECT VersionNumber FROM Flow WHERE Definition.DeveloperName='Check_Completeness_of_Contact_Roles' AND Status='Active'" 2>/dev/null | grep -oE '"VersionNumber": [0-9]+' | grep -oE '[0-9]+')
ACTIVE_LOG=$(sf data query --use-tooling-api -o $ORG --json -q "SELECT VersionNumber FROM Flow WHERE Definition.DeveloperName='Check_Contact_Role_Log_Faults' AND Status='Active'" 2>/dev/null | grep -oE '"VersionNumber": [0-9]+' | grep -oE '[0-9]+')
VR_ACTIVE=$(sf data query --use-tooling-api -o $ORG --json -q "SELECT Active FROM ValidationRule WHERE Id='03d6g000000Zo8YAAS'" 2>/dev/null | grep -oE '"Active": (true|false)' | grep -oE '(true|false)')
echo "  Check_Completeness active version = $ACTIVE_CC (expect 5)"
echo "  Logger active version = $ACTIVE_LOG (expect 3)"
echo "  VR active = $VR_ACTIVE (expect false)"
if [ "$ACTIVE_CC" != "5" ] || [ "$ACTIVE_LOG" != "3" ] || [ "$VR_ACTIVE" != "false" ]; then
  echo "ABORT: state is not as expected (rollback may be in effect). No changes made."
  exit 2
fi

echo "== 1. Delete dormant validation rule Contact_Role_Complete_50 =="
sf project deploy start -o $ORG --manifest manifest/crc_cleanup/package.xml \
  --post-destructive-changes manifest/crc_cleanup/destructiveChanges.xml --json 2>&1 | grep -E '"status"' | head -1

echo "== 2. Prune obsolete/draft flow versions =="
IDS=$(sf data query --use-tooling-api -o $ORG --json -q "SELECT Id FROM Flow WHERE Definition.DeveloperName IN ('Check_Completeness_of_Contact_Roles','Check_Contact_Role_Log_Faults') AND Status IN ('Obsolete','Draft')" 2>/dev/null | grep -oE '"Id": "[0-9A-Za-z]+"' | grep -oE '30[0-9A-Za-z]{15,16}')
for id in $IDS; do
  echo "  deleting flow version $id"
  sf data delete record --use-tooling-api -o $ORG -s Flow -i "$id" 2>&1 | grep -iE "Success|Error" | head -1
done

echo "== Done. Remaining versions: =="
sf data query --use-tooling-api -o $ORG --json -q "SELECT Definition.DeveloperName, VersionNumber, Status FROM Flow WHERE Definition.DeveloperName IN ('Check_Completeness_of_Contact_Roles','Check_Contact_Role_Log_Faults') ORDER BY Definition.DeveloperName, VersionNumber" 2>/dev/null | grep -E '"(DeveloperName|VersionNumber|Status)"'
