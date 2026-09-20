#!/usr/bin/env bash
set -e

mkdir -p scripts

# 1. build_dtb.sh
cat << 'EOS' > scripts/build_dtb.sh
#!/usr/bin/env bash
# build_dtb.sh - compile the HMUF02-V5 device tree from the msm8916-mainline kernel tree.
set -u

PATCH=${1:-$HOME/edl/hmuf02-stick/patches/add-HMUF02-V5-device-tree.patch}
SRC=$HOME/kernel/linux
NAME=msm8916-thwc-hmuf02
CC=aarch64-linux-gnu-
DTS_DIR=arch/arm64/boot/dts/qcom

die() { echo "ERROR: $*" >&2; exit 1; }

command -v git >/dev/null || die "git is not installed"
command -v make >/dev/null || die "make is not installed (sudo pacman -S base-devel)"
command -v "${CC}gcc" >/dev/null || die "cross-compiler missing: sudo pacman -S aarch64-linux-gnu-gcc"
[ -f "$PATCH" ] || die "patch not found: $PATCH"

if [ ! -d "$SRC/.git" ]; then
  echo "== cloning (shallow, a few hundred MB) ..."
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 git@github.com:msm8916-mainline/linux.git "$SRC" || die "clone failed"
fi
cd "$SRC" || exit 1

[ -f "$DTS_DIR/msm8916-ufi.dtsi" ] || die "this tree has no msm8916-ufi.dtsi"

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
make ARCH=arm64 CROSS_COMPILE=$CC -j"$(nproc)" "qcom/$NAME.dtb" || die "build failed"

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
EOS

# 2. fetch_firmware.sh
cat << 'EOS' > scripts/fetch_firmware.sh
#!/usr/bin/env bash
# fetch_firmware.sh - download the DragonBoard 410c firmware
set -u

URLS=(
  'https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/17.09/dragonboard410c_bootloader_emmc_android-88.zip'
  'https://web.archive.org/web/20241225090617/https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/17.09/dragonboard410c_bootloader_emmc_android-88.zip'
)
ZIP=fw.zip
DIR=dragonboard410_fw

die() { echo "ERROR: $*" >&2; exit 1; }

command -v unzip >/dev/null || die "unzip is not installed (sudo pacman -S unzip)"

if [ ! -s "$ZIP" ]; then
  echo "== downloading"
  ok=0
  for u in "${URLS[@]}"; do
    echo "  trying: $u"
    rm -f "$ZIP.part"
    if command -v wget >/dev/null; then
      wget -O "$ZIP.part" "$u"
    elif command -v curl >/dev/null; then
      curl -fL -o "$ZIP.part" "$u"
    else
      die "neither wget nor curl is installed"
    fi
    if [ $? -eq 0 ] && unzip -tq "$ZIP.part" >/dev/null 2>&1; then
      mv "$ZIP.part" "$ZIP"
      ok=1
      break
    fi
    echo "  that source failed or gave a bad file; trying the next one"
    rm -f "$ZIP.part"
  done
  [ "$ok" -eq 1 ] || die "every download source failed"
else
  echo "== using existing $ZIP"
fi

echo "== checking the zip"
unzip -tq "$ZIP" >/dev/null || die "$ZIP is damaged or incomplete"
rm -rf "$DIR" && mkdir -p "$DIR" && unzip -q "$ZIP" -d "$DIR" || die "unzip failed"

echo "== files in the package"
find "$DIR" -type f -printf '%10s  %P\n' | sort -k2

echo
echo "== do the pieces fit this stick's partitions?"
LIMIT=524288
problems=0
for name in tz hyp sbl1 rpm; do
  f=$(find "$DIR" -type f -iname "$name.mbn" | head -1)
  if [ -z "$f" ]; then
    printf '  %-6s not in the zip\n' "$name"
    continue
  fi
  size=$(stat -c%s "$f")
  if [ "$size" -le "$LIMIT" ]; then
    printf '  %-6s %8s bytes  fits (limit %s)   %s\n' "$name" "$size" "$LIMIT" "$f"
  else
    printf '  %-6s %8s bytes  TOO BIG for the %s-byte partition   %s\n' "$name" "$size" "$LIMIT" "$f"
    problems=$((problems + 1))
  fi
done

echo
find "$DIR" -type f -name '*.mbn' -exec sha256sum {} + > SHA256SUMS-dragonboard.txt
echo "Hashes saved to SHA256SUMS-dragonboard.txt"
if [ "$problems" -gt 0 ]; then
  echo "Something is too big - do not use this package."
  exit 1
fi
echo "Nothing was flashed."
EOS

# 3. restore_stock.sh
cat << 'EOS' > scripts/restore_stock.sh
#!/usr/bin/env bash
# restore_stock.sh - put the ORIGINAL firmware back from your verified backup, using EDL.
set -u

DUMP_DIR=uz801_stock
FULL_DUMP=uz801-stock.bin
PARTS="sbl1 tz hyp aboot rpm"
YES=0
FULL=0
LOADER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)    YES=1 ;;
    --full)   FULL=1 ;;
    --loader) shift; LOADER="${1:?--loader needs a path}" ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

die() { echo "ERROR: $*" >&2; exit 1; }
[ -f edl.py ] || die "run this from the folder that holds edl.py"

LOADER_OPT=()
[ -n "$LOADER" ] && LOADER_OPT=("--loader=$LOADER")

CMDS=()
if [ "$FULL" -eq 1 ]; then
  [ -f "$FULL_DUMP" ] || die "$FULL_DUMP not found"
  CMDS+=("wf $FULL_DUMP")
else
  for p in $PARTS; do
    f="$DUMP_DIR/$p.bin"
    [ -f "$f" ] || die "$f not found"
    if [ -f SHA256SUMS ]; then
      want=$(grep -F " $f" SHA256SUMS | head -1 | cut -d' ' -f1)
      have=$(sha256sum "$f" | cut -d' ' -f1)
      if [ -n "$want" ] && [ "$want" != "$have" ]; then
        die "$f does not match SHA256SUMS"
      fi
    fi
    CMDS+=("w $p $f")
  done
fi

echo "Commands (each is: python edl.py <command> ${LOADER_OPT[*]:-}):"
for c in "${CMDS[@]}"; do echo "  $c"; done
echo "  reset   (only after ALL of the above succeed)"

if [ "$YES" -ne 1 ]; then
  echo; echo "Dry run - nothing was written. Add --yes to do it."
  exit 0
fi

echo; echo "This WRITES to the stick. Type RESTORE to continue:"
read -r answer
[ "$answer" = "RESTORE" ] || die "cancelled"

for c in "${CMDS[@]}"; do
  echo ">> python edl.py $c"
  python edl.py $c ${LOADER_OPT[@]+"${LOADER_OPT[@]}"} || die "step failed: $c"
done

echo ">> python edl.py reset"
python edl.py reset ${LOADER_OPT[@]+"${LOADER_OPT[@]}"}
echo "Done."
EOS

chmod +x scripts/*.sh
echo "All scripts created and made executable in scripts/"
