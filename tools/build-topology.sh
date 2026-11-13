#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the AudioReach topology firmware (qcom/sm8450/Redmi-12-5G-tplg.bin) from the upstream SM8450-HDK topology source
# (linux-msm/audioreach-topology, BSD-3-Clause). The sc8280xp sound card driver asks for <card model>-tplg.bin; the card model of this
# phone is "Redmi-12-5G" (set in the DTS). Needs m4 and alsatplg (package alsa-utils). Output: out/extra-fw/qcom/sm8450/Redmi-12-5G-tplg.bin
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
S=sources/audioreach-topology; O=out/extra-fw/qcom/sm8450
[ -d "$S" ] || { echo "run tools/fetch-sources.sh first" >&2; exit 1; }
command -v m4 >/dev/null || { echo "m4 not found" >&2; exit 1; }
ALSATPLG=${ALSATPLG:-$(command -v alsatplg || true)}; [ -n "$ALSATPLG" ] || { echo "alsatplg not found (install alsa-utils, or set ALSATPLG=...)" >&2; exit 1; }
mkdir -p "$O" out/topology
m4 -I "$S" -I "$S/audioreach" "$S/SM8450-HDK.m4" > out/topology/sky.conf
"$ALSATPLG" -c out/topology/sky.conf -o "$O/Redmi-12-5G-tplg.bin" 2>out/topology/alsatplg.log || { cat out/topology/alsatplg.log >&2; exit 1; }
# warnings about "undefined sink widget" are expected: the kernel resolves them when it loads the topology
sha256sum "$O/Redmi-12-5G-tplg.bin"
