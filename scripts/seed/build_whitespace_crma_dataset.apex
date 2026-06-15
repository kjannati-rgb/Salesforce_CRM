/*
 * Build the "Whitespace_Headroom" CRM Analytics dataset (architecture §9) from the Account Plans
 * white-space data via the External Data API — one denormalized row per Whitespace_Cell__c
 * (firm / plan / segment / tier / family / node / state / ARR / headroom). Lands in the
 * Account_Plans_Whitespace app. Re-runnable (Operation=Overwrite).
 * Run: sf apex run --file scripts/seed/build_whitespace_crma_dataset.apex --target-org KJDEV
 */

List<Whitespace_Cell__c> cells = [
    SELECT Account_Plan__c, Account_Plan__r.Account__r.Name, Account_Plan__r.Name, Account_Plan__r.Segment__c,
           Account_Plan__r.Plan_Tier__c, Product_Family__r.Name, Node_Label__c, State__c,
           ARR__c, Expected_Revenue__c
    FROM Whitespace_Cell__c
];

// CSV: quoted text columns, raw numeric columns.
String csv = '"Firm","Plan","PlanId","Segment","Tier","Family","Node","State","ARR","Headroom"\n';
for (Whitespace_Cell__c c : cells) {
    List<String> txt = new List<String>{
        c.Account_Plan__r.Account__r.Name, c.Account_Plan__r.Name, String.valueOf(c.Account_Plan__c),
        c.Account_Plan__r.Segment__c, c.Account_Plan__r.Plan_Tier__c, c.Product_Family__r.Name,
        c.Node_Label__c, c.State__c
    };
    String line = '';
    for (String v : txt) {
        line += '"' + (v == null ? '' : v.replace('"', '""')) + '",';
    }
    line += String.valueOf(c.ARR__c == null ? 0 : c.ARR__c) + ','
          + String.valueOf(c.Expected_Revenue__c == null ? 0 : c.Expected_Revenue__c);
    csv += line + '\n';
}

Map<String, Object> meta = new Map<String, Object>{
    'fileFormat' => new Map<String, Object>{
        'charsetName' => 'UTF-8', 'fieldsDelimitedBy' => ',', 'fieldsEnclosedBy' => '"',
        'linesTerminatedBy' => '\n', 'numberOfLinesToIgnore' => 1 },
    'objects' => new List<Object>{
        new Map<String, Object>{
            'connector' => 'CSV', 'fullyQualifiedName' => 'Whitespace_Headroom',
            'name' => 'Whitespace_Headroom', 'label' => 'White-Space Headroom',
            'fields' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Firm',    'fullyQualifiedName' => 'Firm',    'label' => 'Firm',    'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'Plan',    'fullyQualifiedName' => 'Plan',    'label' => 'Plan',    'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'PlanId',  'fullyQualifiedName' => 'PlanId',  'label' => 'PlanId',  'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'Segment', 'fullyQualifiedName' => 'Segment', 'label' => 'Segment', 'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'Tier',    'fullyQualifiedName' => 'Tier',    'label' => 'Tier',    'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'Family',  'fullyQualifiedName' => 'Family',  'label' => 'Family',  'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'Node',    'fullyQualifiedName' => 'Node',    'label' => 'Node',    'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'State',   'fullyQualifiedName' => 'State',   'label' => 'State',   'type' => 'Text' },
                new Map<String, Object>{ 'name' => 'ARR',      'fullyQualifiedName' => 'ARR',      'label' => 'ARR',      'type' => 'Numeric', 'precision' => 18, 'scale' => 2, 'defaultValue' => '0', 'format' => '0.00' },
                new Map<String, Object>{ 'name' => 'Headroom', 'fullyQualifiedName' => 'Headroom', 'label' => 'Headroom', 'type' => 'Numeric', 'precision' => 18, 'scale' => 2, 'defaultValue' => '0', 'format' => '0.00' }
            }
        }
    }
};

Id appId = [SELECT Id FROM Folder WHERE DeveloperName = 'Account_Plans_Whitespace' LIMIT 1].Id;

InsightsExternalData ext = new InsightsExternalData(
    Format = 'Csv', EdgemartAlias = 'Whitespace_Headroom', EdgemartLabel = 'White-Space Headroom',
    EdgemartContainer = appId, Operation = 'Overwrite', Action = 'None',
    MetadataJson = Blob.valueOf(JSON.serialize(meta)));
insert ext;
insert new InsightsExternalDataPart(InsightsExternalDataId = ext.Id, PartNumber = 1, DataFile = Blob.valueOf(csv));
ext.Action = 'Process';
update ext;
System.debug('Submitted external data ' + ext.Id + ' with ' + cells.size() + ' rows into app ' + appId);
