#!/usr/bin/env bash
# hwinfo.sh - collect hardware/system info from an Android device over ADB.
# No root needed. Anything the device won't reveal is recorded as an error line.
# Usage: ./hwinfo.sh [-s SERIAL] [--full]
#   -s SERIAL   pick a device when several are connected
#   --full      also dump the full (large, slow) `dumpsys`

set -u

SERIAL_ARG=()
FULL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL_ARG=(-s "${2:?missing serial}"); shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v adb >/dev/null 2>&1 || { echo "adb not found in PATH" >&2; exit 1; }
ADB=(adb ${SERIAL_ARG[@]+"${SERIAL_ARG[@]}"})

OUT="hwinfo-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

echo "Waiting for device..."
"${ADB[@]}" wait-for-device || { echo "No device found" >&2; exit 1; }

# sh_out NAME 'command'  -> runs on the device, strips CRs, saves to $OUT/NAME.txt
sh_out() {
  local name="$1" cmd="$2"
  "${ADB[@]}" shell "$cmd" 2>&1 | tr -d '\r' > "$OUT/$name.txt"
  printf '  %-20s %7s bytes\n' "$name" "$(wc -c < "$OUT/$name.txt")"
}

echo "Collecting into $OUT/"
"${ADB[@]}" devices -l | tr -d '\r' > "$OUT/adb_devices.txt"

sh_out getprop           'getprop'
for f in cpuinfo meminfo version cmdline partitions mounts modules iomem interrupts devices; do
  sh_out "proc_$f" "cat /proc/$f"
done
sh_out dmesg             'dmesg'
sh_out df                'df'
sh_out net_ifaces        'ls /sys/class/net'
sh_out platform_devices  'ls -l /sys/bus/platform/devices'
sh_out partitions_by_name 'ls -l /dev/block/platform/*/by-name'
sh_out dt_model          'cat /proc/device-tree/model'
sh_out soc0              'for f in /sys/devices/soc0/*; do [ -f "$f" ] && echo "$f: $(cat "$f" 2>/dev/null)"; done'
sh_out emmc              'for d in /sys/class/mmc_host/mmc0/mmc0:*; do for f in name manfid oemid date fwrev hwrev serial; do echo "$f: $(cat $d/$f 2>/dev/null)"; done; done'
sh_out thermal           'for z in /sys/class/thermal/thermal_zone*; do echo "$z: $(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null)"; done'
sh_out diskstats         'dumpsys diskstats'
if [ "$FULL" -eq 1 ]; then
  sh_out dumpsys_full    'dumpsys'
fi

# Kernel config: pull as a binary file (adb shell > file corrupts binaries on old adbd)
if "${ADB[@]}" pull /proc/config.gz "$OUT/config.gz" >/dev/null 2>&1; then
  zcat "$OUT/config.gz" > "$OUT/kernel_config.txt" 2>/dev/null \
    && echo "  kernel config saved ($(wc -l < "$OUT/kernel_config.txt") lines)"
else
  echo "  /proc/config.gz not available"
fi

# Short summary of the most useful facts
{
  echo "== Key properties =="
  grep -E '^\[ro\.(product\.(model|name|device|board|manufacturer)|board\.platform|hardware|build\.(fingerprint|display\.id|version\.release)|bootloader|baseband|boot\.hardware|revision)\]' "$OUT/getprop.txt"
  echo; echo "== Kernel =="
  cat "$OUT/proc_version.txt"
  echo; echo "== CPU =="
  grep -E 'Hardware|Revision|Processor' "$OUT/proc_cpuinfo.txt" | sort -u
  echo; echo "== Memory =="
  head -2 "$OUT/proc_meminfo.txt"
  echo; echo "== SoC =="
  cat "$OUT/soc0.txt"
  echo; echo "== eMMC =="
  cat "$OUT/emmc.txt"
  echo; echo "== Device tree model =="
  cat "$OUT/dt_model.txt"
} > "$OUT/SUMMARY.txt"

tar czf "$OUT.tar.gz" "$OUT" && echo "Archive: $OUT.tar.gz"
echo "Done. Read $OUT/SUMMARY.txt first."
echo "Note: getprop/dmesg/emmc output can include serial numbers - review before sharing."

