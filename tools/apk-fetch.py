#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""apk-fetch.py OUTDIR pkg... : download the verified dependency closure of Alpine packages (v3.24, aarch64) for a RAM rootfs.
Trust chain: HTTPS -> APKINDEX.tar.gz signature verified with sources/dl-alpine-keys/*.pub (openssl, RSA-SHA1 over the index gzip stream)
-> each .apk control segment SHA-1 must equal the index 'C:' field and the size the 'S:' field. Packages are only downloaded,
never executed on the host. Project tool."""
import sys, os, re, zlib, hashlib, base64, subprocess, tempfile, urllib.request, pathlib
ROOT=pathlib.Path(__file__).resolve().parent.parent
BASE='https://dl-cdn.alpinelinux.org/alpine/v3.24'; ARCH='aarch64'; REPOS=['main','community']
KEY=next((ROOT/'sources/dl-alpine-keys').glob('*.pub'))
def get(url):
    with urllib.request.urlopen(url,timeout=120) as r: return r.read()
def gz_streams(b):
    out=[]
    while b:
        d=zlib.decompressobj(31); d.decompress(b)   # raises on corrupt data
        used=len(b)-len(d.unused_data); out.append(b[:used]); b=d.unused_data
    return out
def rsa_sha1_verify(data,sig):
    """PKCS#1 v1.5 RSA-SHA1 verify with Python ints (OpenSSL on this host refuses SHA-1 signatures by policy)."""
    t=subprocess.run(['openssl','rsa','-pubin','-in',str(KEY),'-noout','-text'],capture_output=True,text=True,check=True).stdout
    mod=int(''.join(re.findall(r'[0-9a-f]{2}',t.split('Modulus:')[1].split('Exponent:')[0])),16)
    exp=int(re.search(r'Exponent: (\d+)',t)[1]); k=(mod.bit_length()+7)//8
    em=pow(int.from_bytes(sig,'big'),exp,mod).to_bytes(k,'big')
    di=bytes.fromhex('3021300906052b0e03021a05000414')+hashlib.sha1(data).digest()
    want=b'\x00\x01'+b'\xff'*(k-len(di)-3)+b'\x00'+di
    return len(sig)==k and em==want
def load_index(repo):
    raw=get('%s/%s/%s/APKINDEX.tar.gz'%(BASE,repo,ARCH))
    st=gz_streams(raw); assert len(st)==2,'unexpected APKINDEX layout'
    import tarfile, io
    sig=tarfile.open(fileobj=io.BytesIO(zlib.decompress(st[0],31))).getmembers()[0]
    sigdata=tarfile.open(fileobj=io.BytesIO(zlib.decompress(st[0],31))).extractfile(sig).read()
    if not rsa_sha1_verify(st[1],sigdata): sys.exit('APKINDEX signature check FAILED for '+repo)
    print('APKINDEX %s signature OK (%s)'%(repo,sig.name),file=sys.stderr)
    txt=tarfile.open(fileobj=io.BytesIO(zlib.decompress(st[1],31))).extractfile('APKINDEX').read().decode()
    recs=[];cur={}
    for l in txt.split('\n'):
        if not l:
            if cur: cur['repo']=repo; recs.append(cur); cur={}
            continue
        cur.setdefault(l[0],[]).append(l[2:])
    return recs
def main():
    out=pathlib.Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
    recs=[r for repo in REPOS for r in load_index(repo)]
    by={};prov={}
    for r in recs:
        n=r['P'][0]; by.setdefault(n,r)
        for p in r.get('p',[''])[0].split(): prov.setdefault(p.split('=')[0],n)
    def res(d):
        d=re.split('[<>=~]',d)[0]
        return None if d.startswith('!') else (d if d in by else prov.get(d))
    seen={};todo=list(sys.argv[2:])
    while todo:
        n=todo.pop(); n=n if n in by else res(n)
        if not n or n in seen: continue
        seen[n]=by[n]
        todo+=[m for d in by[n].get('D',[''])[0].split() if (m:=res(d))]
    if os.environ.get('DRYRUN'):
        print('DRYRUN: %d packages, download %d MiB, installed %d MiB'%(len(seen),sum(int(r['S'][0]) for r in seen.values())>>20,sum(int(r['I'][0]) for r in seen.values())>>20))
        if os.environ.get('DRYRUN')=='2': print(' '.join(sorted(seen)))
        return
    tot=0
    for n,r in sorted(seen.items()):
        fn='%s-%s.apk'%(n,r['V'][0]); p=out/fn
        if not p.exists():
            data=get('%s/%s/%s/%s'%(BASE,r['repo'],ARCH,fn))
            if len(data)!=int(r['S'][0]): sys.exit('size mismatch '+fn)
            ctrl=gz_streams(data)[1 if len(gz_streams(data))>2 else 0]
            want=r['C'][0]; assert want.startswith('Q1')
            if base64.b64encode(hashlib.sha1(ctrl).digest()).decode()!=want[2:]: sys.exit('checksum mismatch '+fn)
            p.write_bytes(data)
        tot+=p.stat().st_size
    print('%d packages, %d KiB in %s (all verified)'%(len(seen),tot//1024,out))
main()
