#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""deb-fetch.py OUTDIR pkg... : download the verified dependency closure of Debian packages (suite trixie, arm64, main) for a persistent rootfs.
Trust chain: HTTPS -> InRelease clear-signed and checked with gpgv against sources/dl-debian-keys/debian-archive-keyring.gpg
(extracted from the debian-archive-keyring .deb that this script fetches on first run, trust-on-first-use over HTTPS; its sha256 and the key
fingerprints are printed and stored in sources/dl-debian-keys/README.txt for a human check) -> Packages.xz sha256 from Release -> each .deb sha256
from Packages. Packages are only downloaded, never executed or unpacked on the host by this tool. Project tool, GPL-2.0-only.
Resolution: Essential + Priority required + the roots, Depends/Pre-Depends only (no Recommends); version constraints are ignored (one version per suite);
first alternative already selected, else the first real package, else a provider from PREFER, else the first provider (printed for review)."""
import sys, os, re, io, lzma, hashlib, subprocess, tempfile, tarfile, urllib.request, pathlib, json
ROOT=pathlib.Path(__file__).resolve().parent.parent
MIRROR='https://deb.debian.org/debian'; SUITE='trixie'; ARCH='arm64'; COMP='main'
KEYDIR=ROOT/'sources/dl-debian-keys'
PREFER={'debconf-2.0':'debconf','awk':'mawk','default-dbus-system-bus':'dbus-system-bus-common','default-dbus-session-bus':'dbus-user-session','dbus-session-bus':'dbus-user-session','dbus-system-bus':'dbus-daemon','libgl1-mesa-dri':'libgl1-mesa-dri','x-terminal-emulator':'gnome-terminal','editor':'nano','pinentry':'pinentry-gnome3','gdm-greeter':'gdm3','cron-daemon':'cron','mail-transport-agent':'','httpd':'','logind':'systemd','tzdata':'tzdata','libc-bin':'libc-bin'}
def get(url,timeout=300):
    with urllib.request.urlopen(url,timeout=timeout) as r: return r.read()
def keyring():
    kr=KEYDIR/'debian-archive-keyring.gpg'
    if kr.exists(): return kr
    KEYDIR.mkdir(parents=True,exist_ok=True)
    idx=get('%s/pool/main/d/debian-archive-keyring/'%MIRROR).decode()
    debs=sorted(set(re.findall(r'debian-archive-keyring_[0-9.~a-z+]+_all\.deb',idx)))
    name=debs[-1]; blob=get('%s/pool/main/d/debian-archive-keyring/%s'%(MIRROR,name))
    (KEYDIR/name).write_bytes(blob)
    members=[]; pos=8
    while pos<len(blob):
        h=blob[pos:pos+60]; n=h[:16].decode().strip(); sz=int(h[48:58]); members.append((n,blob[pos+60:pos+60+sz])); pos+=60+sz+(sz&1)
    data=[m for m in members if m[0].startswith('data.tar')][0]
    comp={'.xz':'xz','.gz':'gz','.zst':None}.get(os.path.splitext(data[0])[1])
    if data[0].endswith('.zst'):
        raw=subprocess.run(['zstd','-dc'],input=data[1],capture_output=True,check=True).stdout; tf=tarfile.open(fileobj=io.BytesIO(raw))
    else: tf=tarfile.open(fileobj=io.BytesIO(data[1]))
    f=[m for m in tf.getmembers() if m.name.endswith('debian-archive-keyring.gpg')][0]
    kr.write_bytes(tf.extractfile(f).read())
    fp=subprocess.run(['gpg','--show-keys','--with-colons',str(kr)],capture_output=True,text=True).stdout
    fps=[l.split(':')[9] for l in fp.split('\n') if l.startswith('fpr')]
    (KEYDIR/'README.txt').write_text('keyring from %s sha256 %s (fetched over HTTPS, trust-on-first-use)\nprimary/sub fingerprints:\n%s\n'%(name,hashlib.sha256(blob).hexdigest(),'\n'.join(fps)))
    print('keyring from',name,'sha256',hashlib.sha256(blob).hexdigest(),file=sys.stderr)
    return kr
def verified_release():
    kr=keyring(); raw=get('%s/dists/%s/InRelease'%(MIRROR,SUITE))
    with tempfile.NamedTemporaryFile() as t:
        t.write(raw); t.flush()
        r=subprocess.run(['gpgv','--keyring',str(kr),'--output','-',t.name],capture_output=True)
    if r.returncode: sys.exit('InRelease signature check FAILED: '+r.stderr.decode())
    print('InRelease signature OK',file=sys.stderr)
    return r.stdout.decode()
def packages():
    rel=verified_release()
    want='%s/binary-%s/Packages.xz'%(COMP,ARCH)
    m=re.search(r'^ ([0-9a-f]{64}) +(\d+) +%s$'%re.escape(want),rel,re.M); assert m,'Packages.xz not in Release'
    raw=get('%s/dists/%s/%s'%(MIRROR,SUITE,want))
    if hashlib.sha256(raw).hexdigest()!=m[1]: sys.exit('Packages.xz hash mismatch')
    txt=lzma.decompress(raw).decode(); recs={}
    for blk in txt.split('\n\n'):
        d={}; last=None
        for l in blk.split('\n'):
            if l[:1] in ' \t' and last: d[last]+='\n'+l; continue
            if ':' in l: k,v=l.split(':',1); last=k; d[k]=v.strip()
        if 'Package' in d: recs[d['Package']]=d
    return recs
def alts(field):
    out=[]
    for part in (field or '').replace('\n',' ').split(','):
        part=part.strip()
        if not part: continue
        out.append([re.sub(r'\s*\(.*?\)|\s*\[.*?\]|\s*<.*?>','',a).strip().split(':')[0] for a in part.split('|')])
    return out
def main():
    outdir=pathlib.Path(sys.argv[1]); roots=sys.argv[2:]; outdir.mkdir(parents=True,exist_ok=True)
    recs=packages(); prov={}
    for n,d in recs.items():
        for p in alts(d.get('Provides')):
            prov.setdefault(p[0],[]).append(n)
    sel=[]; seen=set(); notes=[]
    base=[n for n,d in recs.items() if d.get('Essential')=='yes' or d.get('Priority')=='required']
    queue=base+roots
    for r in roots:
        if r not in recs and r not in prov: sys.exit('unknown package '+r)
    while queue:
        n=queue.pop(0)
        if n in seen: continue
        if n not in recs:
            continue
        seen.add(n); sel.append(n); d=recs[n]
        for a in alts(d.get('Pre-Depends'))+alts(d.get('Depends')):
            pick=None
            for x in a:
                if x in seen: pick=x; break
            if not pick:
                for x in a:
                    if x in recs: pick=x; break
            if not pick:
                for x in a:
                    if x in prov:
                        c=PREFER.get(x); ps=prov[x]
                        pick=c if c in ps else next((p for p in ps if p in seen),None) or sorted(ps)[0]
                        notes.append('virtual %s -> %s (of %d)'%(x,pick,len(ps))); break
            if pick is None: notes.append('UNRESOLVED %s needs %s'%(n,a)); continue
            if pick not in seen: queue.append(pick)
    tot=sum(int(recs[n]['Size']) for n in sel)
    print('closure: %d packages, %.0f MiB'%(len(sel),tot/2**20),file=sys.stderr)
    for x in sorted(set(notes)): print(x,file=sys.stderr)
    if os.environ.get('DRYRUN'):
        print('\n'.join(sel)); return
    man=[]
    for i,n in enumerate(sel):
        d=recs[n]; f=outdir/pathlib.Path(d['Filename']).name
        if not (f.exists() and f.stat().st_size==int(d['Size']) and hashlib.sha256(f.read_bytes()).hexdigest()==d['SHA256']):
            b=get('%s/%s'%(MIRROR,d['Filename']))
            if hashlib.sha256(b).hexdigest()!=d['SHA256']: sys.exit('hash mismatch '+n)
            f.write_bytes(b)
        man.append({'package':n,'version':d['Version'],'file':f.name,'sha256':d['SHA256'],'size':int(d['Size'])})
        if i%50==0: print(i,'/',len(sel),file=sys.stderr)
    (outdir/'MANIFEST.json').write_text(json.dumps(man,indent=0))
    print('done',len(man),file=sys.stderr)
main()
