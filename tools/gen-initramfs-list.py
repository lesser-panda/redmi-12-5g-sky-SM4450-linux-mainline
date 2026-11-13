#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Emit a kernel initramfs list (uid/gid 0) from a staged directory tree: gen-initramfs-list.py TREE > list"""
import os, stat, sys
tree = os.path.abspath(sys.argv[1])
out = []
for dp, dns, fns in os.walk(tree):
    dns.sort(); fns.sort()
    rel = os.path.relpath(dp, tree)
    if rel != '.':
        out.append(f"dir /{rel} {stat.S_IMODE(os.lstat(dp).st_mode):04o} 0 0")
    for n in fns + [d for d in dns if os.path.islink(os.path.join(dp, d))]:
        p = os.path.join(dp, n); r = '/' + os.path.relpath(p, tree)
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            out.append(f"slink {r} {os.readlink(p)} 0777 0 0")
        elif stat.S_ISREG(st.st_mode):
            out.append(f"file {r} {p} {stat.S_IMODE(st.st_mode) | 0o444:04o} 0 0")
print("\n".join(out))
