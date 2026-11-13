#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""E032 helper: allocate MB megabytes (half incompressible, half zeros) and keep dirtying random pages for SECS seconds, to push the machine into zram/swap.
usage: memhog.py MB SECS. It marks itself as the preferred OOM victim."""
import os, random, sys, time
try:
    open('/proc/self/oom_score_adj', 'w').write('1000')
except OSError:
    pass
mb, secs = int(sys.argv[1]), int(sys.argv[2])
chunks = []
for i in range(mb // 16):
    chunks.append(bytearray(os.urandom(8 << 20)) + bytearray(8 << 20))
end = time.time() + secs
n = 0
while time.time() < end:
    c = chunks[random.randrange(len(chunks))]
    for _ in range(2000):
        c[random.randrange(len(c))] = n & 0xff
    n += 1
print('memhog: %d MB held, %d rounds' % (mb, n))
