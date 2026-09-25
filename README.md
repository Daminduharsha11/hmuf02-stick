# Mainline Linux Kernel 7.0.0 for the HMUF02 V5 (Zhihe) MSM8916 LTE Dongle

A from-scratch 64-bit mainline Linux kernel (7.0.0) built and booted on the **HMUF02 V5**, a Qualcomm MSM8916 USB LTE dongle that shipped with 32-bit Android 4.3/4.4 and, until now, had **no documented postmarketOS support**. Per the postmarketOS wiki's own Zhihe-series device page, this specific board was previously only known to work "sans LEDs when built for UFI001c" — this repo adds full, verified LED, SIM, and button support via a dedicated device tree.

<p align="center">
  <img src="neofetch.jpeg" alt="neofetch output showing postmarketOS + Linux 7.0.0 running on HMUF02 V5" width="600">
</p>

---

## 🧠 The Kernel — Main Feature

This is the core of the project: taking a board that only ever ran a 32-bit vendor Android kernel and getting a current mainline 64-bit kernel booting cleanly on it, with hardware fully verified rather than just "boots to shell."

- **From 32-bit to 64-bit:** Stock firmware only knows how to start a 32-bit Android boot image. To boot an arm64 mainline kernel, the `tz` (TrustZone) and `hyp` firmware had to be replaced with builds from the Dragonboard 410c (same MSM8916 SoC family) — the stock firmware cannot be reused as-is.
- **qhypstub over stock hyp:** Used [qhypstub](https://github.com/msm8916-mainline/qhypstub) instead of Linaro's `hyp.mbn` so Linux boots in EL2, keeping KVM available. Mixing Linaro `tz` with stock `hyp` (or vice versa) bricks the device, so both had to be swapped together, in the correct order, with no reboot in between until both were confirmed flashed.
- **lk1st over lk2nd:** Went with `lk1st` rather than `lk2nd` — vendor `aboot` firmware varies enough across Zhihe-family boards that `lk2nd` introduces quirks lk1st avoids.
- **No fastboot, EDL only:** This board doesn't expose fastboot the way most Zhihe-series devices do — every flash and every recovery from a bad boot went through Qualcomm EDL mode (`05c6:9008`), which meant zero margin for a bad flash.
- **eMMC space constraints:** Small onboard eMMC meant the generic rootfs/boot flashing strategies (flash-to-system, flash-to-userdata) weren't clean options. Boot image modules were manually audited and stripped of anything not needed for this board to fit within partition limits and avoid sector errors.
- **First custom device tree for this board:** No DTB existed for HMUF02 V5 specifically. Booted initially from a borrowed/adapted device tree, then built and verified a dedicated `msm8916-thwc-hmuf02.dtb`, cross-checked against a decompiled stock Android DTB dump, with a fallback boot entry (generic `ufi001c` DTB) kept in `extlinux.conf` in case the custom tree failed.
- **Build environment:** Entire kernel cross-compiled on modest hardware — full builds take 2–3 hours per iteration, so every change was reasoned through carefully before compiling.

---

## 📌 Hardware Overview & Verified Pinout

- **SoC:** Qualcomm MSM8916 / Snapdragon 410 (Quad-Core Cortex-A53 @ 1.0–1.2GHz)
- **Board Target:** HMUF02 V5 (Zhihe series), previously undocumented
- **Storage:** Onboard eMMC (`/dev/mmcblk0`, 4GB common)
- **Host Interface:** USB CDC NCM (`enp0s...`)
- **Kernel:** 7.0.0, mainline

### Verified GPIO Mapping Table
Verified by decompiling the stock Android DTB blob and cross-referencing live device states — this is the part that was previously undocumented/unconfirmed for this exact board:

| Function | GPIO Pin | Subsystem / Sysfs Node |
| :--- | :--- | :--- |
| **WAN LED (Blue)** | `GPIO 71` | `/sys/class/leds/blue:wan` |
| **WLAN LED (Green)** | `GPIO 72` | `/sys/class/leds/green:wlan` |
| **Power LED (Red)** | `GPIO 73` | `/sys/class/leds/red:power` |
| **Reset Button** | `GPIO 37` | `gpio-keys` |
| **SIM Control Pins** | `12`, `14`, `114`, `119` | `esim1_en`, `esim2_en`, `sim_hotplug` |

---

## 🛠️ Repository Layout

- `scripts/` — Helper scripts for firmware fetching, DTB compilation, bootchain creation, and stock restoration.
- `patches/` — Mainline kernel patches for the HMUF02-V5 device tree.
- `notes/` — Extracted stock Android DTS notes and pinout references.
- `docs/` — Screenshots and reference images (neofetch output, boot logs, etc).

---

## 🚀 Quick Start Guide

### Prerequisites
- Host machine running Linux (Arch Linux recommended).
- Dependencies: `python`, `dtc`, `pmbootstrap`, `edl` (Qualcomm EDL Tool).
- **Back up the eMMC before touching anything** — see [bkerler/EDL](https://github.com/bkerler/edl). There is no fastboot fallback on this board; a bad flash means EDL recovery or a brick.
- Budget 2–3 hours per full kernel build.

### 1. Verification & Hardware Dump
Plug the stick in Qualcomm EDL mode (`05c6:9008`) and run:
```bash
./scripts/hwinfo.sh
python3 ./scripts/verify_backup.py
```

### 2. Build Bootchain & Device Tree
```bash
./scripts/fetch_firmware.sh
./scripts/build_bootchain.sh
./scripts/build_dtb.sh
```

### 3. Flash Bootloader/Firmware via EDL
Replace stock 32-bit firmware with Dragonboard 410c `tz`, `qhypstub` in place of `hyp`, and `lk1st` for `aboot`. Flash in this order, and **do not reboot the device until all three are confirmed flashed** — mixing firmware sources here is what bricks the device:
```bash
python edl.py w tz dragonboard410_fw/tz.mbn
python edl.py w hyp qhypstub-test-signed.mbn
python edl.py w aboot build-lk1st-msm8916/emmc_appsboot-test-signed.mbn
```

### 4. Flash Rootfs
```bash
# Flash postmarketOS rootfs image to userdata
python edl.py w userdata /path/to/zhihe-generic.img
```

### 5. Boot & SSH Access
Unplug and replug the device normally. Set host interface IP and log in:
```bash
sudo ip link
sudo ip link set <interface> up
sudo ip addr add 172.16.42.2/24 dev <interface>
ssh <user-name>@172.16.42.1
```

---

## 📄 Installing & Testing the HMUF02 Device Tree

Rather than replacing the default DTB immediately, it is safest to copy the compiled `.dtb` to `/boot` and add a secondary boot entry in `extlinux.conf`. This keeps a working bootable fallback if the custom tree fails.

### 1. Copy the Compiled DTB to the Stick
```bash
scp /path/to/msm8916-thwc-hmuf02.dtb <user-name>@172.16.42.1:/tmp/
ssh <user-name>@172.16.42.1 "sudo cp /tmp/msm8916-thwc-hmuf02.dtb /boot/"
```

### 2. Configure extlinux.conf for Dual-Booting DTBs
Back up your boot config first:
```bash
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
```

Edit `/boot/extlinux/extlinux.conf`, setting the default to the new entry while keeping the generic `ufi001c` DTB as fallback:

```
# Custom HMUF02-V5 DTB (Full LED, SIM, and Button support)
timeout 1
default postmarketOS-hmuf02
menu title Boot Options

label postmarketOS-hmuf02
	kernel /vmlinuz
	fdt /msm8916-thwc-hmuf02.dtb
	initrd /initramfs
	append quiet earlycon console=ttyMSM0,115200 pmos_boot_uuid=d79dd64c-4986-4b6a-8457-676644b5bc46 pmos_root_uuid=e4b30cc0-3de3-43ae-b5df-cc862657a767 pmos_rootfsopts=defaults

# Fallback Generic DTB
label postmarketOS
	kernel /vmlinuz
	fdt /msm8916-thwc-ufi001c.dtb
	initrd /initramfs
	append quiet earlycon console=ttyMSM0,115200 pmos_boot_uuid=d79dd64c-4986-4b6a-8457-676644b5bc46 pmos_root_uuid=e4b30cc0-3de3-43ae-b5df-cc862657a767 pmos_rootfsopts=defaults
```

Reboot the device (`sudo reboot`). Once booted, verify LEDs respond under `/sys/class/leds/`.

---

### 🔄 Stock Recovery
To restore the device to original factory state:
```bash
./scripts/restore_stock.sh
```

### 🙏 Credits & Acknowledgments
- Device Tree Patch (`HMUF02-V5-device-tree.patch`): initial GPIO identification for LEDs, reset button, and SIM lines by Rudi Knauss.
- Verification & Integration: verified against stock Android device tree dumps, compiled, and tested on physical HMUF02 V5 hardware by [Your Name / GitHub Username].
- postmarketOS Community: MSM8916 mainline kernel developers, lk2nd/lk1st and qhypstub maintainers.
- [postmarketOS Wiki — Zhihe-series LTE dongles](https://wiki.postmarketos.org) for prior art on the wider device family.
