#!/usr/bin/env bash
# fetch_firmware.sh - download the DragonBoard 410c firmware that the postmarketOS wiki
# points to, and check that the pieces we need fit into this stick's partitions.
# Downloads and reads only. NOTHING is flashed.
# Run it from your ~/edl folder:  bash fetch_firmware.sh
# If the download keeps failing, save the zip from your browser as ./fw.zip and run it again.
set -u

URL='https://web.archive.org/web/20241225090617/https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/17.09/dragonboard410c_bootloader_emmc_android-88.zip'
ZIP=fw.zip
DIR=dragonboard410_fw

die() { echo "ERROR: $*" >&2; exit 1; }

command -v unzip >/dev/null || die "unzip is not installed (sudo pacman -S unzip)"

if [ ! -s "$ZIP" ]; then
  echo "== downloading (can take a while; safe to rerun, it resumes)"
  if command -v wget >/dev/null; then
    wget -c -O "$ZIP" "$URL" || die "download failed - save the zip from your browser as $ZIP and rerun"
  elif command -v curl >/dev/null; then
    curl -L -C - -o "$ZIP" "$URL" || die "download failed - save the zip from your browser as $ZIP and rerun"
  else
    die "neither wget nor curl is installed"
  fi
else
  echo "== using existing $ZIP"
fi

echo "== checking the zip"
unzip -tq "$ZIP" >/dev/null || die "$ZIP is damaged or incomplete (if it is a small HTML page, the download was blocked)"
rm -rf "$DIR" && mkdir -p "$DIR" && unzip -q "$ZIP" -d "$DIR" || die "unzip failed"

echo "== files in the package"
find "$DIR" -type f -printf '%10s  %P\n' | sort -k2

echo
echo "== do the pieces fit this stick's partitions? (limits from your own dump)"
LIMIT=524288   # tz, hyp, sbl1 and rpm partitions are 512 KiB each on this stick
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
  echo "Something is too big - do not use this package. Tell me which line."
  exit 1
fi
echo "Nothing was flashed. Paste the file list and the fit results above."
