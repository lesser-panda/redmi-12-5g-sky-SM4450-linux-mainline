#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Shrink the last partition (userdata) of the phone's UFS LUN sda and add linuxboot/linuxroot in the freed space.
Works on the 4 KiB-sector GPT only (blocks 1..2 primary, backup entries + header at the end); never touches partition contents.
Usage: gpt-split-sda.py <old-head.bin> <old-tail.bin> <outdir> [userdata_gib=40] [boot_gib=1]
  old-head.bin: first 1 MiB of /dev/sda; old-tail.bin: last 1 MiB. Writes outdir/{primary.bin (LBA1..2, 8192 B), backup.bin (backup entries + header), plan.txt}.
Dry-run only: this script writes no device. Device writes are done separately (tools/gpt-write-sda.sh) after the live GPT is compared with the input."""
import struct, zlib, sys, uuid, pathlib
SS = 4096
def parse(blob_head, blob_tail):
    h = blob_head[SS:SS+92]
    sig, rev, hs, crc, _, cur, bak, first, last = struct.unpack('<8sIIIIQQQQ', h[:56])
    assert sig == b'EFI PART' and hs == 92
    dguid = h[56:72]
    ent_lba, n, esz, ecrc = struct.unpack('<QIII', h[72:92])
    ents = blob_head[ent_lba*SS: ent_lba*SS + n*esz]
    assert zlib.crc32(ents) & 0xffffffff == ecrc, 'primary entries crc'
    hc = bytearray(h); hc[16:20] = b'\0'*4
    assert zlib.crc32(bytes(hc)) & 0xffffffff == crc, 'primary header crc'
    # backup header = last block of the tail file
    bh = blob_tail[-SS:][:92]
    bsig, _, _, bcrc, _, bcur, bbak, bfirst, blast = struct.unpack('<8sIIIIQQQQ', bh[:56])
    assert bsig == b'EFI PART' and bcur == bak and bbak == cur and bfirst == first and blast == last
    bent_lba = struct.unpack('<Q', bh[72:80])[0]
    tail_lba0 = bak + 1 - len(blob_tail)//SS
    bents = blob_tail[(bent_lba - tail_lba0)*SS: (bent_lba - tail_lba0)*SS + n*esz]
    assert bents == ents, 'backup entries differ from primary'
    return dict(cur=cur, bak=bak, first=first, last=last, dguid=dguid, ent_lba=ent_lba, n=n, esz=esz, ents=bytearray(ents), bent_lba=bent_lba, rev=rev)
def entry(i, ents, esz):
    return ents[i*esz:(i+1)*esz]
def build(info, userdata_gib, boot_gib):
    n, esz, ents = info['n'], info['esz'], info['ents']
    used = [i for i in range(n) if entry(i, ents, esz)[:16] != b'\0'*16]
    last_i = max(used, key=lambda i: struct.unpack('<Q', entry(i, ents, esz)[32:40])[0])
    e = bytearray(entry(last_i, ents, esz))
    name = e[56:128].decode('utf-16le').rstrip('\0')
    assert name == 'userdata' and last_i == used[-1], 'last partition is not userdata: ' + name
    start, end = struct.unpack('<QQ', e[32:48])
    assert end == info['last'], 'userdata does not end at last usable LBA'
    blocks_per_gib = (1 << 30) // SS
    new_end = start + userdata_gib * blocks_per_gib - 1
    assert new_end < end
    e[40:48] = struct.pack('<Q', new_end)
    ents[last_i*esz:(last_i+1)*esz] = e
    free = [i for i in range(n) if i not in used]
    assert len(free) >= 2, 'no free GPT entries'
    linux_type = uuid.UUID('0FC63DAF-8483-4772-8E79-3D69D8477DE4').bytes_le
    def mk(i, s, l_end, nm):
        x = bytearray(esz)
        x[:16] = linux_type; x[16:32] = uuid.uuid4().bytes_le
        x[32:48] = struct.pack('<QQ', s, l_end); x[48:56] = b'\0'*8
        x[56:56+len(nm)*2] = nm.encode('utf-16le')
        ents[i*esz:(i+1)*esz] = x
    b_start = new_end + 1; b_end = b_start + boot_gib * blocks_per_gib - 1
    r_start = b_end + 1; r_end = end
    mk(free[0], b_start, b_end, 'linuxboot'); mk(free[1], r_start, r_end, 'linuxroot')
    plan = [(last_i+1, 'userdata', start, new_end), (free[0]+1, 'linuxboot', b_start, b_end), (free[1]+1, 'linuxroot', r_start, r_end)]
    return plan
def header(info, ents, cur, bak, ent_lba):
    ecrc = zlib.crc32(bytes(ents)) & 0xffffffff
    h = bytearray(SS)
    h[:92] = struct.pack('<8sIIIIQQQQ16sQIII', b'EFI PART', info['rev'], 92, 0, 0, cur, bak, info['first'], info['last'], info['dguid'], ent_lba, info['n'], info['esz'], ecrc)
    h[16:20] = struct.pack('<I', zlib.crc32(bytes(h[:92])) & 0xffffffff)
    return bytes(h)
def main():
    head = open(sys.argv[1], 'rb').read(); tail = open(sys.argv[2], 'rb').read(); out = pathlib.Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
    ud = int(sys.argv[4]) if len(sys.argv) > 4 else 40; bt = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    info = parse(head, tail)
    plan = build(info, ud, bt)
    ents = info['ents']
    pad = lambda b: b + b'\0' * (SS - len(b) % SS if len(b) % SS else 0)
    primary = header(info, ents, info['cur'], info['bak'], info['ent_lba']) + pad(bytes(ents))     # LBA1, then entries from LBA2
    bhdr = header(info, ents, info['bak'], info['cur'], info['bent_lba'])
    # self-test: rebuilding the untouched tables must reproduce the original header bytes exactly (proves the CRC/field layout)
    orig = parse(head, tail); oe = orig['ents']
    assert header(orig, oe, orig['cur'], orig['bak'], orig['ent_lba'])[:92] == head[SS:SS+92], 'primary header self-test'
    assert header(orig, oe, orig['bak'], orig['cur'], orig['bent_lba'])[:92] == tail[-SS:][:92], 'backup header self-test'
    (out/'primary.bin').write_bytes(primary)                       # LBA 1 (header) + LBA 2 (entries)
    (out/'backup-entries.bin').write_bytes(pad(bytes(ents)))       # at bent_lba
    (out/'backup-header.bin').write_bytes(bhdr)                    # at the last LBA
    (out/'plan.txt').write_text('\n'.join(f'{no} {nm} LBA {s}-{e} ({(e-s+1)*SS/2**30:.2f} GiB)' for no, nm, s, e in plan) + f"\nprimary.bin: {len(primary)} bytes at LBA 1\nbackup-entries.bin: {len(pad(bytes(ents)))} bytes at LBA {info['bent_lba']}\nbackup-header.bin: 4096 bytes at LBA {info['bak']}\n")
    print((out/'plan.txt').read_text())
main()
