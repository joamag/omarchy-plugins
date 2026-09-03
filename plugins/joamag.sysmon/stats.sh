#!/bin/bash

# Collect one snapshot of system metrics as tab-separated key/value lines.
# The QML side keeps the previous CPU jiffies and computes the busy fraction
# from the delta, so this script never sleeps.
#
# Usage: stats.sh [process-count]

set -o pipefail

process_count=${1:-6}

# CPU jiffies: idle (idle + iowait) and total.
awk 'NR == 1 {
  idle = $5 + $6
  total = 0
  for (i = 2; i <= NF; i++) total += $i
  printf "cpu_idle\t%s\ncpu_total\t%s\n", idle, total
}' /proc/stat

# Average frequency across cores, in MHz.
awk -F: '/^cpu MHz/ { sum += $2; n++ } END { if (n > 0) printf "cpu_mhz\t%.0f\n", sum / n }' /proc/cpuinfo

nproc | awk '{ printf "cpu_count\t%s\n", $1 }'

awk '
  /^MemTotal:/ { mem_total = $2 }
  /^MemAvailable:/ { mem_avail = $2 }
  /^SwapTotal:/ { swap_total = $2 }
  /^SwapFree:/ { swap_free = $2 }
  END {
    printf "mem_total_kb\t%s\nmem_avail_kb\t%s\nswap_total_kb\t%s\nswap_free_kb\t%s\n", mem_total, mem_avail, swap_total, swap_free
  }
' /proc/meminfo

awk '{ printf "load1\t%s\nload5\t%s\nload15\t%s\n", $1, $2, $3 }' /proc/loadavg
awk '{ printf "uptime_sec\t%d\n", $1 }' /proc/uptime

# CPU package temperature: prefer the well-known CPU sensor drivers, fall back
# to the first hwmon that exposes a temperature at all.
cpu_temp=""
for hwmon in /sys/class/hwmon/hwmon*; do
  name=$(<"$hwmon/name") 2>/dev/null || continue
  case "$name" in
    k10temp | zenpower | coretemp | cpu_thermal | soc_thermal)
      for input in "$hwmon"/temp*_input; do
        [[ -r $input ]] || continue
        label_file="${input%_input}_label"
        label=$(<"$label_file") 2>/dev/null || label=""
        # k10temp exposes Tctl (control) and Tdie/Tccd; Tctl is what users see.
        if [[ -z $cpu_temp || $label == Tctl || $label == "Package id 0" ]]; then
          cpu_temp=$(<"$input")
        fi
      done
      ;;
  esac
  [[ -n $cpu_temp ]] && break
done
if [[ -z $cpu_temp ]]; then
  for input in /sys/class/hwmon/hwmon*/temp1_input; do
    [[ -r $input ]] || continue
    cpu_temp=$(<"$input")
    break
  done
fi
[[ -n $cpu_temp ]] && printf 'cpu_temp_c\t%.1f\n' "$(bc -l <<<"$cpu_temp / 1000" 2>/dev/null || awk -v t="$cpu_temp" 'BEGIN { print t / 1000 }')"

# GPU: NVIDIA via nvidia-smi, otherwise the first amdgpu/i915 card via sysfs.
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | head -n 1 | awk -F', *' '
    NF >= 5 {
      printf "gpu_name\t%s\ngpu_util\t%s\ngpu_temp_c\t%s\ngpu_mem_used_mb\t%s\ngpu_mem_total_mb\t%s\n", $1, $2, $3, $4, $5
    }'
else
  for card in /sys/class/drm/card*/device; do
    [[ -r $card/gpu_busy_percent ]] || continue
    name=$(cat "$card"/hwmon/hwmon*/name 2>/dev/null | head -n 1)
    printf 'gpu_name\t%s\n' "${name:-GPU}"
    printf 'gpu_util\t%s\n' "$(<"$card/gpu_busy_percent")"
    if [[ -r $card/mem_info_vram_used && -r $card/mem_info_vram_total ]]; then
      printf 'gpu_mem_used_mb\t%d\n' "$(( $(<"$card/mem_info_vram_used") / 1048576 ))"
      printf 'gpu_mem_total_mb\t%d\n' "$(( $(<"$card/mem_info_vram_total") / 1048576 ))"
    fi
    for input in "$card"/hwmon/hwmon*/temp1_input; do
      [[ -r $input ]] && printf 'gpu_temp_c\t%.1f\n' "$(awk -v t="$(<"$input")" 'BEGIN { print t / 1000 }')"
      break
    done
    break
  done
fi

# Root filesystem usage in KiB.
df -Pk / 2>/dev/null | awk 'NR == 2 { printf "disk_total_kb\t%s\ndisk_used_kb\t%s\ndisk_pct\t%s\n", $2, $3, $5 + 0 }'

# Busiest processes by instantaneous CPU: pid, %cpu, %mem, command name. top's
# %CPU is measured since the previous refresh, unlike ps which reports the
# lifetime average. The %CPU column is per-core (a 6-core process reads 600),
# so divide by the core count to match the headline CPU meter.
if (( process_count > 0 )); then
  top -b -n 1 -o %CPU -w 512 2>/dev/null | awk -v limit="$process_count" -v cores="$(nproc)" '
    /^ *PID/ { header = 1; next }
    header && NF >= 12 && $1 != "" && $NF != "top" {
      printf "proc\t%s\t%.1f\t%s\t%s\n", $1, $9 / cores, $10, $NF
      if (++shown >= limit) exit
    }'
fi
