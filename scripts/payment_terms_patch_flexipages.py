import sys, os, re, shutil
src_dir, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(out_dir, 'flexipages'), exist_ok=True)
def fi(field, behavior):
    ident = 'Record' + field.replace('__c','_c') + 'Field'
    return f"""        <itemInstances>
            <fieldInstance>
                <fieldInstanceProperties>
                    <name>uiBehavior</name>
                    <value>{behavior}</value>
                </fieldInstanceProperties>
                <fieldItem>Record.{field}</fieldItem>
                <identifier>{ident}</identifier>
            </fieldInstance>
        </itemInstances>
"""
def block(field):
    return re.compile(r"        <itemInstances>\n            <fieldInstance>\n(?:.*?\n)*?                <fieldItem>Record\." + re.escape(field) + r"</fieldItem>\n(?:.*?\n)*?            </fieldInstance>\n        </itemInstances>\n")
names = []
for fn in os.listdir(os.path.join(src_dir, 'flexipages')):
    p = os.path.join(src_dir, 'flexipages', fn); x = open(p, encoding='utf-8').read()
    editable_just = 'Draft' in fn
    if 'Payment_Terms_Justification__c' in x: print('already patched:', fn); shutil.copy(p, os.path.join(out_dir,'flexipages',fn)); names.append(fn.replace('.flexipage','')); continue
    m = block('SBQQ__PaymentTerms__c').search(x); assert m, fn + ': PaymentTerms block not found'
    ins = fi('Payment_Terms_Justification__c', 'none' if editable_just else 'readonly') + fi('Payment_Terms_Days__c', 'readonly') + fi('ACV_GBP__c', 'readonly')
    x = x[:m.end()] + ins + x[m.end():]
    m2 = block('PO_Number__c').search(x); assert m2, fn + ': PO_Number block not found'
    x = x[:m2.end()] + fi('PO_Required__c', 'none') + x[m2.end():]
    open(os.path.join(out_dir,'flexipages',fn), 'w', encoding='utf-8').write(x)
    names.append(fn.replace('.flexipage','')); print('patched', fn, '| justification', 'editable' if editable_just else 'readonly')
open(os.path.join(out_dir,'package.xml'),'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n    <types>\n' + ''.join(f'        <members>{n}</members>\n' for n in sorted(names)) + '        <name>FlexiPage</name>\n    </types>\n    <version>64.0</version>\n</Package>\n')
print('package.xml written for', sorted(names))
