#!/bin/bash
# SPDX-License-Identifier: MIT
# E032 synthetic load test, runs ON the phone as root (copy it to the phone and run it as root, e.g. as a transient systemd unit; see docs/lab-notebook/EXPERIMENT-010.md).
# 30-minute cycle: A cpu+memory(zram) 10 min, B storage write+verify+random read 6 min, C gpu(glmark2 off-screen)+2 cpu 5 min,
#                  D wifi download + gateway ping + socket stress 5 min, E idle 4 min.  Durations scale with SCALE (dry run: SCALE=0.05).
# Safety (phone-side, independent of the laptop): load is stopped while battery temperature > TEMPMAX (tenths of C) or capacity < BATMIN;
# it never suspends the system; load runs at nice 10 so sshd/GNOME stay responsive; the whole test ends after HOURS.
# Output: $OUT (default /root/loadtest/<timestamp>): samples.csv, kernel-new.log, cycles.log, phase-*.log, SUMMARY.txt
set -u
HOURS=${HOURS:-6}; SCALE=${SCALE:-1}; BATMIN=${BATMIN:-40}; TEMPMAX=${TEMPMAX:-430}; INTERVAL=${INTERVAL:-15}
OUT=${OUT:-/root/loadtest/$(date +%Y%m%d-%H%M)}; mkdir -p "$OUT"
START=$(date +%s); END=$((START + $(awk "BEGIN{printf \"%d\", $HOURS*3600}")))
B=/sys/class/power_supply/battery
ph() { awk "BEGIN{printf \"%d\", $1*$SCALE}"; }
log() { echo "$(date +%T) $*" | tee -a "$OUT/cycles.log"; }
bat() { cat $B/$1 2>/dev/null || echo 0; }
LOADPIDS="stress-ng fio curl"
stop_load() { for p in $LOADPIDS; do pkill -TERM -x "$p" 2>/dev/null; done; pkill -TERM -f glmark2-es2 2>/dev/null; pkill -TERM -f memhog.py 2>/dev/null; sleep 1; for p in $LOADPIDS; do pkill -KILL -x "$p" 2>/dev/null; done; pkill -KILL -f glmark2-es2 2>/dev/null; pkill -KILL -f memhog.py 2>/dev/null; }
trap 'stop_load; kill $SAMPLER 2>/dev/null; log "controller stopped"; exit 0' TERM INT

# protect the services we need to stay reachable from the OOM killer (runtime only)
for n in sshd gdm gdm3 gnome-shell NetworkManager wpa_supplicant systemd-logind systemd-journald dbus-daemon; do
  for p in $(pidof $n 2>/dev/null); do echo -900 > /proc/$p/oom_score_adj 2>/dev/null; done
done
echo 15 > /proc/sys/kernel/panic 2>/dev/null   # a kernel panic reboots instead of leaving the phone dark (comes back in Android)

KBASE=$(dmesg | wc -l)
IGN='disallowed SPMI write|wlan: \[[0-9]+:[IDP]:|sky-c[0-9]|\[kworke\]\[0x|\[system\]\[0x|\[soft_i\]\[0x'
PAT='BUG|Oops|WARNING|Call trace|soft lockup|rcu|stall|hung task|panic|fault|error|fail|timeout|firmware|crash|ufshcd|UFS|dpu|ERROR|Out of memory|oom|Killed process|blocked|lockup|thermal|overheat|throttl|hangcheck|reset|watchdog'

sampler() {
  echo "time,uptime_s,load1,cap,status,cur_ma,temp_dC,cpu0_khz,cpu6_khz,memavail_mb,swap_used_mb,zram_orig_mb,zram_compr_mb,procs_running,kernel_new" > "$OUT/samples.csv"
  while :; do
    local z=0 zc=0 sw cur
    read -r orig compr _ < /sys/block/zram0/mm_stat 2>/dev/null && { z=$((orig/1048576)); zc=$((compr/1048576)); }
    sw=$(awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{print int((t-f)/1024)}' /proc/meminfo)
    cur=$(( $(bat current_now) / 1000 ))
    local all newl; all=$(dmesg | tail -n +$((KBASE+1))); KBASE=$((KBASE + $(printf '%s\n' "$all" | grep -c ''))); [ -z "$all" ] && KBASE=$(dmesg | wc -l)
    all=$(printf '%s\n' "$all" | grep -Ev "$IGN")
    [ -n "$all" ] && printf '%s\n' "$all" | sed "s/^/$(date +%T) /" >> "$OUT/kernel-all.log"
    newl=$(printf '%s\n' "$all" | grep -Ei "$PAT")
    [ -n "$newl" ] && printf '%s\n' "$newl" | sed "s/^/$(date +%T) /" >> "$OUT/kernel-new.log"
    echo "$(date +%T),$(cut -d. -f1 /proc/uptime),$(cut -d' ' -f1 /proc/loadavg),$(bat capacity),$(bat status),$cur,$(bat temp),$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq),$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq),$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo),$sw,$z,$zc,$(awk '/procs_running/{print $2}' /proc/stat),$(wc -l < "$OUT/kernel-new.log" 2>/dev/null || echo 0)" >> "$OUT/samples.csv"
    sleep "$INTERVAL"
  done
}
sampler & SAMPLER=$!

guard() {  # sleeps while the battery is too hot / too empty; returns when it is fine (or the test time is over)
  while [ "$(date +%s)" -lt "$END" ]; do
    t=$(bat temp); c=$(bat capacity)
    if [ "$t" -gt "$TEMPMAX" ] || [ "$c" -lt "$BATMIN" ]; then
      stop_load; log "GUARD: temp ${t}dC cap ${c}% -> load paused"; sleep 60
    else return 0; fi
  done
  return 1
}

# run a load command for $1 seconds (guard-aware): usage: phase NAME SECONDS cmd...
phase() { local n=$1 s=$2; shift 2; log "phase $n ${s}s"; guard || return 1
  nice -n 10 timeout "$((s+20))" "$@" > "$OUT/phase-$n.log" 2>&1; local rc=$?
  log "phase $n done rc=$rc"; return 0; }

cycle=0
log "start: hours=$HOURS scale=$SCALE out=$OUT battery $(bat capacity)% $(bat temp)dC kernel $(uname -r)"
while [ "$(date +%s)" -lt "$END" ]; do
  cycle=$((cycle+1)); log "=== cycle $cycle"
  # A: cpu + memory pressure (two 2.8 GB workers on a 7.2 GB machine => zram/swap)
  phase A-$cycle "$(ph 420)" stress-ng --cpu 8 --cpu-method matrixprod --vm 2 --vm-bytes 2800M --vm-method walk-1d --metrics-brief --timeout "$(ph 420)s"
  # A2: memory hog bigger than RAM minus the desktop => zram/swap traffic (stress-ng caps its own vm size to the free memory)
  phase A2-$cycle "$(ph 180)" bash -c "stress-ng --cpu 4 --timeout $(ph 180)s & python3 /root/memhog.py 6900 $(ph 170); wait"
  # B: storage: 1 GiB direct write with crc32c verify, then 3.5 min random read (data-integrity check on the persistent root)
  if guard; then
    log "phase B-$cycle"
    rm -f /var/tmp/lt.dat
    nice -n 10 fio --name=wv --filename=/var/tmp/lt.dat --size=1G --rw=randwrite --bs=64k --direct=1 --ioengine=libaio --iodepth=8 \
      --verify=crc32c --do_verify=1 --verify_fatal=0 --output="$OUT/phase-B-$cycle-write.log" 2>&1
    nice -n 10 fio --name=rr --filename=/var/tmp/lt.dat --size=1G --rw=randread --bs=4k --direct=1 --ioengine=libaio --iodepth=16 --time_based --runtime="$(ph 210)" \
      --output="$OUT/phase-B-$cycle-read.log" 2>&1
    rm -f /var/tmp/lt.dat
    grep -hE "verify|error|err=" "$OUT/phase-B-$cycle-write.log" | head -3 | sed "s/^/B-$cycle: /" >> "$OUT/cycles.log"
    log "phase B-$cycle done"
  fi
  # C: gpu (off-screen, no frame callbacks needed) + 2 cpu workers
  ( phase C-$cycle "$(ph 300)" stress-ng --cpu 2 --timeout "$(ph 300)s" ) & CP=$!
  guard && nice -n 10 timeout "$(ph 300)" runuser -u user -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 glmark2-es2-wayland --off-screen --run-forever > "$OUT/phase-C-$cycle-glmark2.log" 2>&1
  wait $CP; grep -hE "glmark2 Score" "$OUT/phase-C-$cycle-glmark2.log" | sed "s/^/C-$cycle: /" >> "$OUT/cycles.log"
  # D: wifi download (3 MB/s cap) + gateway ping loss + socket stress
  gw=$(ip route | awk '/^default/{print $3; exit}')
  ( ping -i 0.5 -w "$(ph 300)" "$gw" > "$OUT/phase-D-$cycle-ping.log" 2>&1 ) & DP1=$!
  ( end=$(( $(date +%s) + $(ph 300) )); while [ "$(date +%s)" -lt "$end" ]; do
      nice -n 10 curl -s -o /dev/null --limit-rate 3M -m 120 -w "%{http_code} %{size_download} %{time_total}\n" https://deb.debian.org/debian/ls-lR.gz; done > "$OUT/phase-D-$cycle-curl.log" 2>&1 ) & DP2=$!
  phase D-$cycle "$(ph 300)" stress-ng --sock 2 --cpu 2 --timeout "$(ph 300)s"; wait $DP1 $DP2
  tail -2 "$OUT/phase-D-$cycle-ping.log" | tr '\n' ' ' | sed "s/^/D-$cycle: /" >> "$OUT/cycles.log"; echo >> "$OUT/cycles.log"
  awk '{c[$1]++; b[$1]+=$2} END{for(k in c) printf "D-'$cycle' curl http %s x%d %.0f MB\n", k, c[k], b[k]/1048576}' "$OUT/phase-D-$cycle-curl.log" >> "$OUT/cycles.log"
  # E: idle
  log "phase E-$cycle idle $(ph 240)s"; sleep "$(ph 240)"
  # cycle health check
  {
    echo "health $cycle: failed units: $(systemctl --failed --no-legend | wc -l); gnome-shell pid: $(pidof gnome-shell | tr ' ' ',' ); gdm: $(systemctl is-active gdm3 2>/dev/null); evdi: $(grep -c '^evdi ' /proc/modules)"
    echo "health $cycle: oom kills so far: $(dmesg | grep -ci 'Out of memory\|Killed process'); cap $(bat capacity)% status $(bat status) temp $(bat temp)dC thresholds $(cat $B/charge_control_start_threshold)/$(cat $B/charge_control_end_threshold)"
  } | tee -a "$OUT/cycles.log"
done
stop_load; kill $SAMPLER 2>/dev/null
{
  echo "finished $(date) after $(( ($(date +%s)-START)/60 )) min, cycles: $cycle"
  echo "kernel-new.log lines: $(wc -l < "$OUT/kernel-new.log" 2>/dev/null || echo 0)"
  awk -F, 'NR>1{if($7>m)m=$7; if($10<a||a=="")a=$10; if($11>s)s=$11; if($13>zc)zc=$13} END{printf "max battery temp %.1f C, min MemAvailable %d MB, max swap used %d MB, max zram compressed %d MB\n", m/10, a, s, zc}' "$OUT/samples.csv"
} > "$OUT/SUMMARY.txt"; cat "$OUT/SUMMARY.txt" | tee -a "$OUT/cycles.log"
