#!/usr/bin/env python3
"""Insert read-only Sales_Development_Representative__c field into the MAIN DETAILS
section of Opportunity Dynamic Forms record pages, right after the main-details OwnerId.

Heuristic: a field on a Dynamic Forms page is its own <itemInstances> block. The
highlights-panel OwnerId block is the LAST in its region (followed by <name>Facet...).
The main-details OwnerId block is followed by another <itemInstances> (more fields).
We anchor on the OwnerId block whose next sibling is another <itemInstances>.

Run with no args = report only. Run with --apply to write changes (idempotent).
"""
import sys, re, glob, os

APPLY = '--apply' in sys.argv
FIELD = 'Sales_Development_Representative__c'
SDR_BLOCK = (
    "        <itemInstances>\n"
    "            <fieldInstance>\n"
    "                <fieldInstanceProperties>\n"
    "                    <name>uiBehavior</name>\n"
    "                    <value>readonly</value>\n"
    "                </fieldInstanceProperties>\n"
    "                <fieldItem>Record.Sales_Development_Representative__c</fieldItem>\n"
    "                <identifier>RecordSales_Development_Representative__cField</identifier>\n"
    "            </fieldInstance>\n"
    "        </itemInstances>\n"
)

files = sorted(glob.glob('force-app/main/default/flexipages/Opportunity_Record_Page_*.flexipage-meta.xml'))
for path in files:
    name = os.path.basename(path)
    src = open(path, encoding='utf-8').read()
    if FIELD in src:
        print(f"SKIP (already present): {name}")
        continue
    # Find each OwnerId itemInstances block, classify by the NEXT field after it.
    # Main-details OwnerId is followed by Opportunity_Number__c (or, for Cancellation
    # which has a single OwnerId, by Sales_Manager__c). Highlights-facet OwnerId is
    # followed by a <name>Facet...</name> or a highlights-only field (e.g. GroupID__c).
    blocks = list(re.finditer(r'<itemInstances>\s*<fieldInstance>.*?Record\.OwnerId.*?</fieldInstance>\s*</itemInstances>', src, re.S))
    def next_field(m):
        after = src[m.end():m.end()+300]
        nf = re.search(r'<fieldItem>(Record\.[^<]+)</fieldItem>', after)
        facet = re.search(r'<name>(Facet[^<]*)</name>', after)
        if facet and (not nf or facet.start() < nf.start()):
            return None  # highlights facet
        return nf.group(1) if nf else None
    chosen = None
    for m in blocks:
        nf = next_field(m)
        line = src[:m.start()].count('\n') + 1
        print(f"   {name}: OwnerId block @line {line} -> next={nf}")
        if nf == 'Record.Opportunity_Number__c' and chosen is None:
            chosen = m
    if chosen is None and len(blocks) == 1:
        chosen = blocks[0]   # e.g. Cancellation: single OwnerId in details
    if chosen is None:
        print(f"!! NO main-details OwnerId anchor found: {name} (NEEDS MANUAL)")
        continue
    insert_at = chosen.end()
    # preserve the newline structure: insert after the block's trailing newline
    nl = src.find('\n', insert_at)
    insert_pos = nl + 1 if nl != -1 else insert_at
    new = src[:insert_pos] + SDR_BLOCK + src[insert_pos:]
    aline = src[:chosen.start()].count('\n') + 1
    print(f"==> {name}: insert SDR after main-details OwnerId @line {aline}  [{'APPLIED' if APPLY else 'dry-run'}]")
    if APPLY:
        open(path, 'w', encoding='utf-8', newline='').write(new)
