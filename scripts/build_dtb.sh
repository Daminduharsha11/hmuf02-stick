#!/usr/bin/env bash
# build_dtb.sh - compile the HMUF02-V5 device tree from the msm8916-mainline kernel tree.
# Writes nothing to the stick. Clones into ~/kernel/linux (outside your git repo).
# Usage: bash build_dtb.sh [path/to/add-HMUF02-V5-device-tree.patch]
set -u

PATCH=${1:-$HOME/edl/hmuf02-stick/patches/add-HMUF02-V5-device-tree.patch}
SRC=$HOME/kernel/linux
NAME=msm8916-thwc-hmuf02
CC=aarch64-linux-gnu-
DTS_DIR=arch/arm64/boot/dts/qcom

die() { echo "ERROR: $*" >&2; exit 1; }

command -v git  >/dev/null || die "git is not installed"
command -v make >/dev/null || die "make is not installed (sudo pacman -S base-devel)"
command -v "${CC}gcc" >/dev/null || die "cross-compiler missing: sudo pacman -S aarch64-linux-gnu-gcc"
[ -f "$PATCH" ] || die "patch not found: $PATCH  (pass its path as the first argument)"

if [ ! -d "$SRC/.git" ]; then
  echo "== cloning (shallow, a few hundred MB) ..."
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 https://github.com/msm8916-mainline/linux "$SRC" || die "clone failed"
fi
cd "$SRC" || exit 1

[ -f "$DTS_DIR/msm8916-ufi.dtsi" ] \
  || die "this tree has no msm8916-ufi.dtsi, so the patch cannot build here (wrong branch?)"

echo "== applying patch"
if [ -f "$DTS_DIR/$NAME.dts" ]; then
  echo "  already applied"
elif git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH" && echo "  applied"
elif git apply --check --ignore-whitespace "$PATCH" 2>/dev/null; then
  git apply --ignore-whitespace "$PATCH" && echo "  applied (ignoring whitespace differences)"
else
  echo "  the patch does not apply cleanly. Details:"
  git apply --check "$PATCH"
  die "paste the lines above so we can fix it"
fi

echo "== configuring"
make ARCH=arm64 CROSS_COMPILE=$CC defconfig >/dev/null || die "defconfig failed"

echo "== building $NAME.dtb"
make ARCH=arm64 CROSS_COMPILE=$CC -j"$(nproc)" "qcom/$NAME.dtb" \
  || die "build failed - paste the last 20 lines above"

OUT=$DTS_DIR/$NAME.dtb
[ -f "$OUT" ] || die "no dtb was produced"
echo; ls -l "$OUT"

echo; echo "== quick check of the result"
if [ -x scripts/dtc/dtc ]; then
  scripts/dtc/dtc -I dtb -O dts "$OUT" 2>/dev/null > /tmp/hmuf02.dts
  grep -m3 -E '^\s*(model|compatible) =' /tmp/hmuf02.dts
  echo "pins named in the tree (want 37 71 72 73 for button/LEDs; 12 14 114 119 for SIM):"
  grep -o -E '"gpio(12|14|37|71|72|73|114|119)"' /tmp/hmuf02.dts | sort -u | tr '\n' ' '; echo
  echo "full decompiled copy: /tmp/hmuf02.dts"
fi
echo; echo "Done. The compiled file is: $SRC/$OUT"
