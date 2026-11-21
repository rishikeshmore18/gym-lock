import os,re,sys
root=sys.argv[1]
decl=re.compile(r'^\s{0,4}(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|final|open)\s+)*(struct|class|enum|actor|protocol|extension)\s+([A-Za-z_][\w\.]*)')
rows=[]
for dp,dn,fn in os.walk(root):
    dn[:]=[d for d in dn if d not in('.git','build','DerivedData')]
    for f in fn:
        if not f.endswith('.swift'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,root)
        try: L=open(p,encoding='utf-8').read().split('\n')
        except: continue
        names=[];doc=''
        for i,l in enumerate(L):
            m=decl.match(l)
            if m and (l.startswith(('struct','class','enum','actor','protocol','extension','final','public','@','private','fileprivate','internal')) or l.startswith(' ')):
                n=m.group(2)
                if m.group(1)=='extension': n='+'+n
                if n not in names: names.append(n)
        for l in L[:25]:
            s=l.strip()
            if s.startswith('//') and not s.startswith('///') and 'MARK' not in s and len(s)>8 and not re.match(r'//\s*(Created|Copyright|[A-Za-z]+\.swift)',s) and '©' not in s:
                doc=s.lstrip('/ ').strip();break
            if s.startswith('///'):
                doc=s.lstrip('/ ').strip();break
        rows.append((rel,len(L),names,doc))
rows.sort()
out=[]
for rel,n,names,doc in rows:
    nm=','.join(names[:6])+('…' if len(names)>6 else '')
    d=(' — '+doc[:90]) if doc else ''
    out.append(f"{rel} [{n}] {nm}{d}")
print('\n'.join(out))
