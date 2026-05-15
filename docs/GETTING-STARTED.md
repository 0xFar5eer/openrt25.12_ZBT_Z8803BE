# Getting Started

This guide explains how to use the firmware artifacts, flash a ZBTLink ZBT-Z8803BE, and build the image locally from this repository.

## What this firmware targets

This repository builds a custom OpenWrt 25.12.2 image for the ZBTLink ZBT-Z8803BE WiFi 7 router.

Current release metadata is listed in the root `README.md` and detailed release notes are in:

```text
releases/RELEASE_NOTES.md
releases/RELEASE_NOTES.zh-CN.md
```

## Download a release image

Use the latest GitHub release assets for normal installation or upgrade:

```text
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
sha256sums
config.buildinfo
feeds.buildinfo
version.buildinfo
RELEASE_NOTES.md
RELEASE_NOTES.zh-CN.md
```

The release page is linked from the root README and SSH banner:

```text
https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/releases
```

## Verify downloaded files

After downloading the firmware and `sha256sums`, verify the files before flashing:

```sh
sha256sum -c sha256sums --ignore-missing
```

At minimum, verify the `squashfs-sysupgrade.bin` image you plan to flash.

## Flash from existing OpenWrt

Copy the sysupgrade image to the router and run:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

For a clean reset instead of preserving config:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

## Flash from U-Boot recovery

The README documents the recovery path:

1. Hold **Reset** while powering on until recovery starts.
2. Open `http://192.168.1.1`.
3. Upload the `squashfs-sysupgrade.bin` image.
4. Wait for reboot.

## First login

Default first-boot credentials are:

| Field | Value |
|-------|-------|
| IP | `192.168.1.1` |
| User | `root` |
| Password | `admin` |

Change the password immediately after first login.

## Factory WiFi defaults

On first boot, `72-zbt-z8803be-wifi` creates per-band WPA3-SAE networks using a MAC suffix in the SSID.

| Band | SSID pattern | Channel | Width |
|------|--------------|---------|-------|
| 2.4 GHz | `WIFI7-<MAC6>` | `11` | `EHT20` |
| 5 GHz | `WIFI7-5G-<MAC6>` | `149` | `EHT80` |
| 6 GHz | `WIFI7-6G-<MAC6>` | `37` | `EHT160` |

Default WiFi key:

```text
12345678
```

The firmware sets country `PH`, clears firmware-side power/channel clamps, and leaves regulatory enforcement to `wireless-regdb` and the driver.

## Expected first-boot networking

Board defaults configure:

| Role | Interfaces |
|------|------------|
| LAN | `lan0 lan1 lan2` |
| WAN | `eth1 eth2` |
| Cellular failover | `wwan0` bound through `network.4_1` and `network.4_1v6` stubs |

The firmware seeds wired WAN with metric `10` and cellular WWAN with metric `20`, so wired WAN remains preferred when available.

## Build locally

Use the Docker build harness from the repository root:

```sh
./.buildenv/build.sh init
./.buildenv/build.sh feeds
cp .buildenv/zbt8803be.config .config
./.buildenv/build.sh config
./.buildenv/build.sh download
./.buildenv/build.sh build
./.buildenv/build.sh extract
```

The extracted sysupgrade output is expected under:

```text
output/mediatek/filogic/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

## Useful build commands

| Command | Purpose |
|---------|---------|
| `./.buildenv/build.sh shell` | Open an interactive shell in the build container. |
| `./.buildenv/build.sh menuconfig` | Run `make menuconfig` inside the container. |
| `./.buildenv/build.sh build -j1 V=s` | Run a serial verbose build for debugging. |
| `./.buildenv/build.sh clean` | Run `make clean`. |
| `./.buildenv/build.sh dirclean` | Run `make dirclean`. |
| `./.buildenv/build.sh nuke-volume` | Remove the Docker build volume. |
| `./.buildenv/build.sh nuke-all` | Remove the Docker build volume, output directory, build symlinks, and config files. |

## After flashing

Recommended checks after a clean flash:

```sh
ubus call system board
uci show wireless
uci show network.wan
uci show network.4_1
uci show qmodem.4_1
```

For WiFi state:

```sh
iw reg get
iw dev
```

For modem monitor state:

```sh
uci show qmodem.4_1 | grep monitor
ps w | grep '[m]odem_monitor'
```

For generated build metadata, inspect release assets:

```text
config.buildinfo
feeds.buildinfo
version.buildinfo
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```
