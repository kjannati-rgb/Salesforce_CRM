# Order Form: insert the Send_for_Signature quick action into the SBQQ__Quote__c "Approved"
# page layout, right after Generate Document. The org hides approval-dependent buttons by
# RECORD-TYPE LAYOUT (AA flips Draft -> Pending -> Approved; each record type has its own
# layout), so placing the action only on the Approved layout hides it until approval - same
# logic as Generate Document / Generate_Quote_Doc.
# Usage (Phase 6, PROD): retrieve the LIVE layout first - never deploy a repo copy:
#   sf project retrieve start -o <org> --manifest package.xml --target-metadata-dir out
#   python patch-approved-layout.py out/unpackaged/layouts/SBQQ__Quote__c-Approved.layout
#   sf project deploy start -o <org> --metadata-dir out/unpackaged
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'Send_for_Signature' in s:
    print('already present'); sys.exit(0)
item = '''        <platformActionListItems>
            <actionName>SBQQ__Quote__c.Send_for_Signature</actionName>
            <actionType>QuickAction</actionType>
            <sortOrder>SORT</sortOrder>
        </platformActionListItems>
'''
m = re.search(r'(<platformActionList>.*?</platformActionList>)', s, re.S)
block = m.group(1)
items = re.findall(r'<platformActionListItems>.*?</platformActionListItems>', block, re.S)
gen = next(i for i in items if 'SBQQ__GenerateDocument' in i)
gen_sort = int(re.search(r'<sortOrder>(\d+)</sortOrder>', gen).group(1))
newblock = block
# bump sortOrder of items after GenerateDocument
def bump(mm):
    v = int(mm.group(1))
    return '<sortOrder>%d</sortOrder>' % (v + 1 if v > gen_sort else v)
newblock = re.sub(r'<sortOrder>(\d+)</sortOrder>', bump, newblock)
newblock = newblock.replace(gen, gen + '\n' + item.replace('SORT', str(gen_sort + 1)).rstrip(), 1)
s = s.replace(block, newblock)
open(p, 'w', encoding='utf-8').write(s)
print('inserted at sortOrder', gen_sort + 1)
