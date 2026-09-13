"""Generates the Workday-to-User metadata (7 fields, Division validation rule, regrouped User layout, 2 permission sets)
into force-app/main/default so it can be deployed with sf project deploy start.

Usage: python generate_metadata.py --org KJDEV|PROD
The layout variant differs per org because KJDEV lacks some production custom fields; the org's field list is read from
preflight/describe_User_<org>.json when present, otherwise from a describe call.
"""
import argparse, json, os, subprocess, sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DEF = os.path.join(ROOT, "force-app", "main", "default")
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
for v in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    os.environ.pop(v, None)

SUB_DIVISION = ["Editorial", "Intelligence", "Events", "Professional Development", "DIU", "Software Development", "Customer Excellence", "Finance",
                "Contributed Content", "Financial Control", "Marketing", "Program-Project", "Product Management", "Operations People & Culture",
                "Marketing Services", "IT Operations", "Labs-Innovation", "Data and CRM", "Production Ops", "Revenue Operations", "Corporate Executive",
                "Executive Office", "Content Operations", "Facilities", "Legal"]
LOCATION = ["London", "Remote US", "Remote UK (35)", "New York", "Hong Kong", "Remote UK (37)", "London (35)", "Philadelphia, PA", "New York (Union Only)",
            "Erlanger, KY", "Texas Office Cedar Park", "Spain", "Manchester", "Washington D.C.", "Texas Office Abilene", "Australia", "Belgium", "Sweden",
            "Italy", "Romania", "Singapore"]
EMPLOYEE_TYPE = ["Permanent", "EOR", "Fixed Term", "Casual", "NED"]
DIVISION = ["Commercial", "Content and Editorial", "Product & Technology", "Operations Finance", "Corporate Strategy", "Operations",
            "Operations People & Culture", "Corporate Executive", "Executive Office"]
HELP = "Maintained by the Workday HR sync. Change it in Workday; manual edits are overwritten on the next run."

def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("wrote", os.path.relpath(path, ROOT))

def picklist_xml(values):
    vals = "".join("""
            <value>
                <fullName>%s</fullName>
                <default>false</default>
                <label>%s</label>
            </value>""" % (escape(v), escape(v)) for v in values)
    return """
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>%s
        </valueSetDefinition>
    </valueSet>""" % vals

def field(name, label, body, help_text=HELP):
    return """<?xml version="1.0" encoding="UTF-8"?>
<CustomField %s>
    <fullName>%s</fullName>
    <externalId>%s</externalId>
    <inlineHelpText>%s</inlineHelpText>
    <label>%s</label>
    <required>false</required>
    <trackHistory>false</trackHistory>%s
</CustomField>
""" % (NS, name, "true" if name == "Workday_Employee_ID__c" else "false", escape(help_text), escape(label), body)

FIELDS = {
    "Workday_Employee_ID__c": field("Workday_Employee_ID__c", "Workday Employee ID", """
    <caseSensitive>false</caseSensitive>
    <length>20</length>
    <type>Text</type>
    <unique>true</unique>""", "Workday Employee ID, verbatim (numeric or prefixed, e.g. HK578). " + HELP),
    "Hire_Date__c": field("Hire_Date__c", "Hire Date", """
    <type>Date</type>"""),
    "Sub_Division__c": field("Sub_Division__c", "Sub Division", """
    <type>Picklist</type>""" + picklist_xml(SUB_DIVISION)),
    "Location__c": field("Location__c", "Location", """
    <type>Picklist</type>""" + picklist_xml(LOCATION)),
    "Employee_Type__c": field("Employee_Type__c", "Employee Type", """
    <type>Picklist</type>""" + picklist_xml(EMPLOYEE_TYPE)),
    # The User object does not allow a custom Lookup(User); the User-only "Hierarchy" type is the supported equivalent (same as Manager).
    "ELT_Lead__c": field("ELT_Lead__c", "ELT Lead", """
    <relationshipLabel>ELT Lead of</relationshipLabel>
    <relationshipName>ELT_Lead_Of</relationshipName>
    <type>Hierarchy</type>""", "Executive Leadership Team lead for this person, from Workday. " + HELP),
    "Workday_Last_Sync__c": field("Workday_Last_Sync__c", "Workday Last Sync", """
    <type>DateTime</type>""", "When the Workday HR sync last wrote this record."),
    # Standard Division keeps the CRM business-unit taxonomy (57 report filters/groupings, ChurnZero segmentation formula).
    # Workday's division is a different taxonomy and gets its own restricted picklist.
    "Workday_Division__c": field("Workday_Division__c", "Workday Division", """
    <type>Picklist</type>""" + picklist_xml(DIVISION), "Division as recorded in Workday (nine values). Not the same as the standard Division field, which the CRM team maintains. " + HELP),
}

VR = """<?xml version="1.0" encoding="UTF-8"?>
<ValidationRule %s>
    <fullName>Division_Workday_Values</fullName>
    <active>false</active>
    <description>INACTIVE (8 Sep 2026): standard Division keeps the CRM business-unit taxonomy (57 report filters, ChurnZero formula); Workday division is written to Workday_Division__c. Kept for a possible future merge.</description>
    <errorConditionFormula>AND(
  NOT( ISBLANK( Division ) ),
  NOT( $Setup.Application_Settings__c.Disable_Validation_Rules__c ),
  CASE( Division,
    %s,
    0 ) = 0
)</errorConditionFormula>
    <errorDisplayField>Division</errorDisplayField>
    <errorMessage>Division must be one of the nine Workday divisions (see the field help). It is maintained by the Workday sync: correct the value in Workday.</errorMessage>
</ValidationRule>
""" % (NS, ",\n    ".join('"%s", 1' % escape(d) for d in DIVISION))

SECTIONS = [
    ("From Workday (read-only)", ["Workday_Employee_ID__c", "Hire_Date__c", "Employee_Type__c", "Workday_Division__c", "Sub_Division__c", "Location__c", "ELT_Lead__c", "Workday_Last_Sync__c"], "Readonly"),
    ("Sales setup", ["Team__c", "Team_Role__c", "Price_Book__c", "Reporting_Level__c", "Renewal_Opportunity_Owner__c", "finance_approver__c",
                     "Advanced_Approvals_Grouping__c", "Advanced_Approvals_Renewal_Grouping__c", "Brands__c", "Group__c", "Business_Group__c", "LBR_Legal_Entity__c",
                     "Business_Unit__c", "Team_Position__c"], "Edit"),
    ("Licences and tools", ["Clari_Copilot_license__c", "Clari_Groove_license__c", "Clari_Groove_Flow_license__c", "Clari_Groove_Dialer_license__c",
                            "Groove_Booking_Link__c", "Gong_Access__c", "ChurnZero_Access_Can_Log_In__c", "LinkedIn_Sales_Navigator__c", "ZoomInfo_Licence__c",
                            "Allow_Ownership_Update_on_Records__c", "Can_Add_Remove_Opp_Team_Member__c", "Opportunity_User__c", "Advendio_User__c"], "Edit"),
    ("System", ["Salesforce_User_ID__c", "ALM_Legacy_User_ID__c", "Rep_Code__c", "alm_id__c", "Employee_Code__c", "Meeting_Scheduler__c", "Swoogo_Discount_Code__c", "DB_Region__c"], "Edit"),
]

def layout_xml(org_fields, calculated=frozenset()):
    def items(fields, behavior):
        out = []
        for f in fields:
            if f not in org_fields:
                print("  layout: skipping %s (not in this org)" % f); continue
            out.append("""
            <layoutItems>
                <behavior>%s</behavior>
                <field>%s</field>
            </layoutItems>""" % ("Readonly" if f in calculated else behavior, f))
        return out
    secs = ""
    for label, fields, behavior in SECTIONS:
        its = items(fields, behavior)
        half = (len(its) + 1) // 2
        secs += """
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>%s</label>
        <layoutColumns>%s
        </layoutColumns>
        <layoutColumns>%s
        </layoutColumns>
        <style>TwoColumnsLeftToRight</style>
    </layoutSections>""" % (escape(label), "".join(its[:half]), "".join(its[half:]))
    return """<?xml version="1.0" encoding="UTF-8"?>
<Layout %s>%s
    <layoutSections>
        <customLabel>false</customLabel>
        <detailHeading>false</detailHeading>
        <editHeading>false</editHeading>
        <label>Custom Links</label>
        <layoutColumns/>
        <layoutColumns/>
        <layoutColumns/>
        <style>CustomLinks</style>
    </layoutSections>
    <showEmailCheckbox>false</showEmailCheckbox>
    <showHighlightsPanel>false</showHighlightsPanel>
    <showInteractionLogPanel>false</showInteractionLogPanel>
    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>
""" % (NS, secs)

def permset(name, label, desc, editable):
    fps = "".join("""
    <fieldPermissions>
        <editable>%s</editable>
        <field>User.%s</field>
        <readable>true</readable>
    </fieldPermissions>""" % ("true" if editable else "false", f) for f in FIELDS)
    return """<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet %s>
    <description>%s</description>%s
    <hasActivationRequired>false</hasActivationRequired>
    <label>%s</label>
</PermissionSet>
""" % (NS, escape(desc), fps, escape(label))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--org", required=True); a = ap.parse_args()
    dp = os.path.join(ROOT, "scripts", "hr_sync_phase1", "preflight", "describe_User_%s.json" % a.org)
    if os.path.exists(dp):
        d = json.load(open(dp, encoding="utf-8"))
    else:
        o = subprocess.run(["sf", "sobject", "describe", "--sobject", "User", "--target-org", a.org, "--json"], capture_output=True, text=True, shell=True, encoding="utf-8").stdout
        d = json.loads(o[o.find("{"):])
    org_fields = {f["name"] for f in d["result"]["fields"]} | set(FIELDS)
    calculated = {f["name"] for f in d["result"]["fields"] if f.get("calculated") or not f.get("updateable", True)}
    for name, xml in FIELDS.items():
        w(os.path.join(DEF, "objects", "User", "fields", name + ".field-meta.xml"), xml)
    w(os.path.join(DEF, "objects", "User", "validationRules", "Division_Workday_Values.validationRule-meta.xml"), VR)
    w(os.path.join(DEF, "layouts", "User-User Layout.layout-meta.xml"), layout_xml(org_fields, calculated))
    w(os.path.join(DEF, "permissionsets", "Workday_User_Fields_Sync.permissionset-meta.xml"),
      permset("Workday_User_Fields_Sync", "Workday User Fields - Sync (edit)", "Edit access to the Workday-sourced User fields. Assign only to the user that runs the HR sync and to System Administrators who fix sync faults.", True))
    w(os.path.join(DEF, "permissionsets", "Workday_User_Fields_Read.permissionset-meta.xml"),
      permset("Workday_User_Fields_Read", "Workday User Fields - Read", "Read access to the Workday-sourced User fields for everyone who views User records.", False))
    w(os.path.join(HERE, "package.xml"), """<?xml version="1.0" encoding="UTF-8"?>
<Package %s>
    <types>%s
        <name>CustomField</name>
    </types>
    <types>
        <members>User.Division_Workday_Values</members>
        <name>ValidationRule</name>
    </types>
    <types>
        <members>User-User Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>Workday_User_Fields_Sync</members>
        <members>Workday_User_Fields_Read</members>
        <name>PermissionSet</name>
    </types>
    <version>62.0</version>
</Package>
""" % (NS, "".join("\n        <members>User.%s</members>" % f for f in FIELDS)))

if __name__ == "__main__":
    main()
