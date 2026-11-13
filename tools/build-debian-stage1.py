#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""build-debian-stage1.py : turn the verified .debs in sources/dl-debian (tools/deb-fetch.py) into out/rootfs-debian-stage1.tar.
Like debootstrap --foreign: the Essential/required base is unpacked (files only, no maintainer scripts run on the host), every .deb is also
shipped in /debs, and /second-stage.sh (run in a chroot on the phone) does `dpkg --unpack` + `dpkg --configure -a` so triggers and scripts
run natively. Nothing from the packages is executed on the host. Ownership is forced to root. Project tool, GPL-2.0-only."""
import sys, io, os, json, tarfile, subprocess, pathlib, stat, time
ROOT=pathlib.Path(__file__).resolve().parent.parent
DL=ROOT/'sources/dl-debian'; OUT=ROOT/'out/rootfs-debian-stage1.tar'
man=json.loads((DL/'MANIFEST.json').read_text())
BASE=set(open(ROOT/'tools/debian-base.txt').read().split())   # packages unpacked on the host (Essential + required + dpkg deps), written by deb-fetch DRYRUN list
def ar_members(blob):
    assert blob[:8]==b'!<arch>\n'; pos=8; out={}
    while pos<len(blob):
        h=blob[pos:pos+60]; n=h[:16].decode().strip().rstrip('/'); sz=int(h[48:58]); out[n]=blob[pos+60:pos+60+sz]; pos+=60+sz+(sz&1)
    return out
def open_tar(name,data):
    if name.endswith('.zst'): data=subprocess.run(['zstd','-dc'],input=data,capture_output=True,check=True).stdout
    elif name.endswith('.xz'): import lzma; data=lzma.decompress(data)
    elif name.endswith('.gz'): import gzip; data=gzip.decompress(data)
    return tarfile.open(fileobj=io.BytesIO(data))
tf=tarfile.open(OUT,'w'); seen=set()
def add(info,fobj=None):
    info.uid=info.gid=0; info.uname=info.gname='root'
    tf.addfile(info,fobj)
def addstr(path,text,mode=0o644):
    b=text.encode(); i=tarfile.TarInfo(path); i.size=len(b); i.mode=mode; i.mtime=int(time.time()); add(i,io.BytesIO(b))
for d in ['dev','proc','sys','run','tmp','debs','mnt','root','var/lib/dpkg/info','var/lib/dpkg/updates','var/lib/dpkg/triggers','var/cache/apt','etc/dpkg/dpkg.cfg.d']:
    i=tarfile.TarInfo(d); i.type=tarfile.DIRTYPE; i.mode=0o1777 if d=='tmp' else 0o755; i.mtime=int(time.time()); add(i)
n=0
for m in man:
    f=DL/m['file']; blob=f.read_bytes()
    i=tarfile.TarInfo('debs/'+m['file']); i.size=len(blob); i.mode=0o644; i.mtime=int(time.time()); add(i,io.BytesIO(blob))
    if m['package'] not in BASE: continue
    mem=ar_members(blob); dn=[k for k in mem if k.startswith('data.tar')][0]
    t=open_tar(dn,mem[dn])
    for e in t:
        e.name=e.name[2:] if e.name.startswith('./') else e.name
        if not e.name or e.name=='.' or e.isdev() or e.isfifo(): continue
        if e.islnk() and e.linkname.startswith('./'): e.linkname=e.linkname[2:]
        if e.isdir(): e.mode|=0o700
        add(e,t.extractfile(e) if e.isreg() else None)
    n+=1
SECOND='''#!/bin/sh
# Second stage, run inside the chroot on the phone: dpkg unpacks every .deb, then configures them (maintainer scripts and triggers run natively).
export DEBIAN_FRONTEND=noninteractive LC_ALL=C PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /
: > /var/lib/dpkg/status; : > /var/lib/dpkg/available
printf '#!/bin/sh\\nexit 101\\n' > /usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
printf 'force-unsafe-io\\npath-exclude=/usr/share/doc/*\\npath-include=/usr/share/doc/*/copyright\\npath-exclude=/usr/share/man/*\\npath-exclude=/usr/share/info/*\\npath-exclude=/usr/share/locale/*\\npath-include=/usr/share/locale/en*\\npath-include=/usr/share/locale/locale.alias\\n' > /etc/dpkg/dpkg.cfg.d/01-slim
echo "unpack: $(ls /debs/*.deb | wc -l) packages"; date
dpkg --force-depends --force-confnew --unpack /debs/*.deb 2>&1 | tail -n 15
echo "configure"; date
dpkg --configure -a --force-depends --force-confnew 2>&1 | tail -n 30
echo "second stage done"; date
'''
addstr('second-stage.sh',SECOND,0o755)
tf.close()
print('base packages prepared:',n,'tar',OUT.stat().st_size//2**20,'MiB',file=sys.stderr)
