#!/usr/bin/env bash
# restore_stock.sh - put the ORIGINAL firmware back from your verified backup, using EDL.
#
# Usage (run from ~/edl with your venv active):
#   bash restore_stock.sh                    show what it WOULD do (writes nothing)
#   bash restore_stock.sh --yes              restore tz, hyp and aboot (the three pieces we replace)
#   add  --with-sbl1-rpm  to also rewrite sbl1 and rpm (only if they were ever changed)
#   bash restore_stock.sh --full --yes       restore the WHOLE flash from uz801-stock.bin
#   add  --loader PATH  if edl needs a firehose loader file
#
# Before using --yes: the stick must be in EDL mode (lsusb shows 05c6:9008).
set -u

DUMP_DIR=uz801_stock
FULL_DUMP=uz801-stock.bin
PARTS="tz hyp aboot"
YES=0
FULL=0
LOADER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)    YES=1 ;;
    --full)   FULL=1 ;;
    --with-sbl1-rpm) PARTS="sbl1 tz hyp aboot rpm" ;;
    --loader) shift; LOADER="${1:?--loader needs a path}" ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

die() { echo "ERROR: $*" >&2; exit 1; }
[ -f edl.py ] || die "run this from the folder that holds edl.py (your ~/edl)"

LOADER_OPT=()
[ -n "$LOADER" ] && LOADER_OPT=("--loader=$LOADER")

# ---- work out the commands ------------------------------------------------
CMDS=()
if [ "$FULL" -eq 1 ]; then
  [ -f "$FULL_DUMP" ] || die "$FULL_DUMP not found"
  CMDS+=("wf $FULL_DUMP")
else
  for p in $PARTS; do
    f="$DUMP_DIR/$p.bin"
    [ -f "$f" ] || die "$f not found"
    # check the file still matches the hash recorded when the backup was made
    if [ -f SHA256SUMS ]; then
      want=$(grep -F " $f" SHA256SUMS | head -1 | cut -d' ' -f1)
      have=$(sha256sum "$f" | cut -d' ' -f1)
      if [ -n "$want" ] && [ "$want" != "$have" ]; then
        die "$f does not match SHA256SUMS - do not restore from a changed file"
      fi
    fi
    CMDS+=("w $p $f")
  done
fi

echo "Commands (each is:  python edl.py <command> ${LOADER_OPT[*]:-}):"
for c in "${CMDS[@]}"; do echo "  $c"; done
echo "  reset   (only after ALL of the above succeed)"

if [ "$YES" -ne 1 ]; then
  echo
  echo "Dry run - nothing was written. Add --yes to do it (stick in EDL mode)."
  exit 0
fi

echo
echo "This WRITES to the stick. Type RESTORE to continue:"
read -r answer
[ "$answer" = "RESTORE" ] || die "cancelled"

for c in "${CMDS[@]}"; do
  echo ">> python edl.py $c"
  # shellcheck disable=SC2086
  python edl.py $c ${LOADER_OPT[@]+"${LOADER_OPT[@]}"} || die "step failed: $c  (do NOT unplug or reset; paste the error)"
done

echo ">> python edl.py reset"
python edl.py reset ${LOADER_OPT[@]+"${LOADER_OPT[@]}"}
echo "Done. Unplug, wait a few seconds, plug back in and check adb devices."
