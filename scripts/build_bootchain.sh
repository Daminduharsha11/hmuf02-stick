#!/usr/bin/env bash
# build_bootchain.sh - build the two small startup pieces for the HMUF02 stick:
#   * qhypstub  (replacement "hyp" firmware)
#   * lk1st     (bootloader that replaces "aboot")
# and collect them, together with the DragonBoard tz.mbn, in ~/bootchain/flashme/.
#
# It only BUILDS and COPIES. Nothing is written to the stick.
# Run it from ~/edl (the folder that holds dragonboard410_fw/):   bash build_bootchain.sh
#
# The board name given to lk1st must match the "compatible" name of the device tree inside the
# Linux boot image, so pick it to match the image you will build:
#   BOARD=ufi001c  (default) for the ready-made postmarketOS UFI001C kernel - the first boot
#   BOARD=hmuf02             once we have a kernel that contains the HMUF02 device tree
# Example:  BOARD=hmuf02 bash build_bootchain.sh
set -u

FW_DIR=${FW_DIR:-$PWD/dragonboard410_fw}
WORK=${WORK:-$HOME/bootchain}
OUT=$WORK/flashme
BUNDLE_DTB=${LK2ND_BUNDLE_DTB:-msm8916-512mb-mtp.dtb}   # same reference tree the stock boot image carries
BOARD=${BOARD:-ufi001c}
case "$BOARD" in
  ufi001c) COMPAT_DEFAULT=thwc,ufi001c ;;
  hmuf02)  COMPAT_DEFAULT=thwc,hmuf02-v5 ;;
  *) echo "BOARD must be ufi001c or hmuf02" >&2; exit 1 ;;
esac
COMPAT=${LK2ND_COMPATIBLE:-$COMPAT_DEFAULT}

die() { echo "ERROR: $*" >&2; exit 1; }

echo "== checking tools"
missing=0
for t in git make python3 dtc aarch64-linux-gnu-gcc arm-none-eabi-gcc; do
  if ! command -v "$t" >/dev/null 2>&1; then echo "  missing: $t"; missing=1; fi
done
if [ "$missing" -eq 1 ]; then
  echo "  install with:"
  echo "    sudo pacman -S git base-devel python dtc aarch64-linux-gnu-gcc arm-none-eabi-gcc arm-none-eabi-newlib python-cryptography"
  exit 1
fi

[ -f "$FW_DIR/tz.mbn" ]  || die "$FW_DIR/tz.mbn not found (run fetch_firmware.sh first, from ~/edl)"
[ -f "$FW_DIR/hyp.mbn" ] || die "$FW_DIR/hyp.mbn not found"

mkdir -p "$WORK" "$OUT" || die "cannot create $WORK"

# clone with a few retries and the simpler HTTP mode (your earlier clone was cut off once)
clone() {  # clone URL DIR
  if [ -d "$2/.git" ]; then echo "  $2 already cloned"; return 0; fi
  local i
  for i in 1 2 3; do
    if git -c http.version=HTTP/1.1 clone --depth 1 "$1" "$2"; then return 0; fi
    echo "  clone failed (attempt $i of 3)"; rm -rf "$2"; sleep 3
  done
  return 1
}

cd "$WORK" || exit 1

echo "== qhypstub"
clone https://github.com/msm8916-mainline/qhypstub.git qhypstub || die "could not clone qhypstub"
clone https://github.com/msm8916-mainline/qtestsign.git qhypstub/qtestsign || die "could not clone qtestsign"
( cd qhypstub && make CROSS_COMPILE=aarch64-linux-gnu- ) || die "qhypstub build failed - paste the last 20 lines"
[ -f qhypstub/qhypstub-test-signed.mbn ] || die "qhypstub-test-signed.mbn was not produced"

echo "== lk1st (bootloader)"
clone https://github.com/msm8916-mainline/lk2nd.git lk2nd || die "could not clone lk2nd"
( cd lk2nd && make LK2ND_BUNDLE_DTB="$BUNDLE_DTB" LK2ND_COMPATIBLE="$COMPAT" \
    TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 ) || die "lk1st build failed - paste the last 20 lines"
[ -f lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn ] || die "emmc_appsboot.mbn was not produced"

echo "== signing (test-signing, as the wiki does for boards without secure boot)"
python3 qhypstub/qtestsign/qtestsign.py aboot lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn \
  || die "signing failed (if it complains about a missing module: sudo pacman -S python-cryptography)"
[ -f lk2nd/build-lk1st-msm8916/emmc_appsboot-test-signed.mbn ] || die "signed aboot was not produced"

echo "== collecting into $OUT"
cp "$FW_DIR/tz.mbn"                                          "$OUT/tz.mbn"
cp qhypstub/qhypstub-test-signed.mbn                         "$OUT/hyp.mbn"
cp lk2nd/build-lk1st-msm8916/emmc_appsboot-test-signed.mbn   "$OUT/aboot.mbn"
cp "$FW_DIR/hyp.mbn"                                         "$OUT/hyp-db410c-fallback.mbn"

echo
echo "== do they fit this stick's partitions?"
problems=0
check() {  # check FILE LIMIT
  local size; size=$(stat -c%s "$OUT/$1")
  if [ "$size" -le "$2" ]; then printf '  %-26s %8s bytes  fits (limit %s)\n' "$1" "$size" "$2"
  else printf '  %-26s %8s bytes  TOO BIG (limit %s)\n' "$1" "$size" "$2"; problems=1; fi
}
check tz.mbn 524288
check hyp.mbn 524288
check aboot.mbn 1048576
check hyp-db410c-fallback.mbn 524288

( cd "$OUT" && sha256sum ./*.mbn > SHA256SUMS )
echo
echo "Files and hashes are in $OUT (SHA256SUMS)."
echo "Built with: board = $BOARD, bundle dtb = $BUNDLE_DTB, compatible = $COMPAT"
[ "$problems" -eq 0 ] || die "something is too big - do not flash it, paste the lines above"
echo "Nothing was flashed. Paste the fit results above."
