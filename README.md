# postmarketOS for HMUF02 V5 (Zhihe) MSM8916 LTE Dongle

Automated setup scripts, verified Device Tree sources, and stock recovery tooling for running mainline Linux (postmarketOS, Kernel 6.12+) on the **Zhihe / HMUF02 V5** Qualcomm MSM8916 USB LTE stick.

---

## 📌 Hardware Overview & Verified Pinout

- **SoC:** Qualcomm MSM8916 (Quad-Core Cortex-A53 @ 1.2GHz)
- **Board Target:** HMUF02 V5 (Zhihe series)
- **Storage:** Onboard eMMC (`/dev/mmcblk0`)
- **Host Interface:** USB CDC NCM (`enp0s...`)

### Verified GPIO Mapping Table
The following pin assignments were verified by decompiling the stock Android DTB blob and cross-referencing running device states:

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

---

## 🚀 Quick Start Guide

### Prerequisites
- Host machine running Linux (Arch Linux recommended).
- Dependencies: `python`, `dtc`, `pmbootstrap`, `edl` (Qualcomm EDL Tool).

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
### 3. Flash to Device via EDL
```bash
# Flash bootloader binaries
python edl.py w tz tz.mbn
python edl.py w hyp hyp.mbn
python edl.py w aboot aboot.mbn

# Flash postmarketOS rootfs image to userdata
python edl.py w userdata /path/to/zhihe-generic.img
```
### 4. Boot & SSH Access

Unplug and replug the device normally. Set host interface IP and log in:
```bash
sudo ip link
sudo ip link set <interface> up
sudo ip addr add 172.16.42.2/24 dev <interface>
ssh <user-name>@172.16.42.1
```

## 📄 Installing & Testing the HMUF02 Device Tree

Rather than replacing the default DTB immediately, it is safest to copy the compiled `.dtb` to `/boot` and add a secondary boot entry in `extlinux.conf`. This ensures you retain a working bootable fallback if something goes wrong.

### 1. Copy the Compiled DTB to the Stick
From your host build machine, transfer the `.dtb` to the dongle:
```bash
scp /path/to/msm8916-thwc-hmuf02.dtb <user-name>@172.16.42.1:/tmp/
ssh <user-name>@172.16.42.1 "sudo cp /tmp/msm8916-thwc-hmuf02.dtb /boot/"
```

### 2. Configure extlinux.conf for Dual-Booting DTBs

Log into the stick and create a backup of your boot config:
```bash
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
```

Edit /boot/extlinux/extlinux.conf and set default to your new entry while keeping the generic ufi001c DTB as a fallback:

# Custom HMUF02-V5 DTB (Full LED, SIM, and Button support)
```
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
Reboot the device (sudo reboot). Once booted, verify that the LEDs respond under /sys/class/leds/.

### 🔄 Stock Recovery

To restore the device to original factory state:
```bash
./scripts/restore_stock.sh
```
### 🙏 Credits & Acknowledgments

Device Tree Patch (HMUF02-V5-device-tree.patch): Created by Rudi Knauss (initial GPIO identification for LEDs, reset button, and SIM lines).

Verification & Integration: Verified against stock Android device tree dumps, compiled, and tested on physical HMUF02 V5 hardware by [Your Name / GitHub Username].

postmarketOS Community: MSM8916 mainline kernel developers & lk2nd maintainers.
