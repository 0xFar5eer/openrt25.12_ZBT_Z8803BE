#!/usr/bin/env bash
# Replay our ZBT-Z8803BE customizations onto a fresh branch sourced from
# upstream OpenWrt main. Usage:
#   ./.buildenv/replay-customizations.sh <source-checkout> <target-checkout>
# where <source-checkout> is the current customized tree (default: pwd)
# and <target-checkout> is a freshly-cloned upstream OpenWrt at the target
# commit/branch. The script copies a curated allowlist of paths and patches
# target/linux/mediatek/image/filogic.mk with the Device/zbtlink_zbt-z8803be
# block.
set -euo pipefail

SRC="${1:-$PWD}"
DST="${2:-}"
if [ -z "$DST" ] || [ ! -d "$DST/target" ]; then
    echo "Usage: $0 [src] <dst>"
    echo "  dst must be an existing OpenWrt checkout"
    exit 2
fi

SRC=$(cd "$SRC" && pwd)
DST=$(cd "$DST" && pwd)
echo "Replaying customizations: $SRC -> $DST"

# 1. Whole directories that we own end-to-end.
DIRS=(
    .buildenv
    package/luci-app-wrtbwmon
    package/luci-app-zbt-about
    package/luci-app-zbt-health
    package/luci-app-zbt-modem-events
    package/luci-app-zbt-speedtest
    package/luci-app-zbt-temperature
    package/wrtbwmon
    target/linux/mediatek/filogic/base-files/etc/profile.d
    target/linux/mediatek/filogic/base-files/etc/rc.d
    target/linux/mediatek/filogic/base-files/usr/lib/zbt
    target/linux/mediatek/filogic/base-files/usr/share/zbt
    releases
    feeds/iwrt_luci/themes/luci-theme-argon
)

# 2. Specific files (board DTS, base-files glue, init.d, hotplug, uci-defaults,
#    sbin helpers).
FILES=(
    target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts
    target/linux/mediatek/filogic/base-files/etc/zbt-leds.sh
    target/linux/mediatek/filogic/base-files/etc/init.d/zbt_qmodem_watchdog
    target/linux/mediatek/filogic/base-files/etc/init.d/zbt-leds
    target/linux/mediatek/filogic/base-files/etc/init.d/zbt-modem-leds
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/40-zbt-status-led
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/iface/50-zbt-wwan-dns
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/10-zbt-qmi-rawip
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/20-zbt-modem-led
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/30-zbt-usb-tether
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/usb/20-zbt-modem-factory-reset
    target/linux/mediatek/filogic/base-files/etc/hotplug.d/usb/40-zbt-qmodem-autoenable
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-baseline
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-hard-reboot-guard
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-led-poller
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-monitor-cooldown
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-reboot-guard
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-modem-soft-reboot
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-qmodem-watchdog-loop
    target/linux/mediatek/filogic/base-files/usr/sbin/zbt-usb-tether-setup
    feeds.conf.default
)

# 3. uci-defaults: glob on prefix.
UCI_DEFAULTS_PREFIX='target/linux/mediatek/filogic/base-files/etc/uci-defaults'

copy_path() {
    local rel=$1 srcp=$SRC/$1 dstp=$DST/$1
    if [ ! -e "$srcp" ]; then
        echo "  skip (missing): $rel"
        return 0
    fi
    mkdir -p "$(dirname "$dstp")"
    if [ -d "$srcp" ]; then
        rm -rf "$dstp"
        cp -a "$srcp" "$dstp"
    else
        cp -a "$srcp" "$dstp"
    fi
    echo "  copied: $rel"
}

echo '== copying directories =='
for d in "${DIRS[@]}"; do copy_path "$d"; done

echo '== copying individual files =='
for f in "${FILES[@]}"; do copy_path "$f"; done

echo '== copying uci-defaults (zbt-prefixed) =='
mkdir -p "$DST/$UCI_DEFAULTS_PREFIX"
for f in "$SRC/$UCI_DEFAULTS_PREFIX"/*-zbt-*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$DST/$UCI_DEFAULTS_PREFIX/"
    echo "  uci-defaults: $(basename "$f")"
done

echo '== patching target/linux/mediatek/image/filogic.mk =='
FILOGIC=$DST/target/linux/mediatek/image/filogic.mk
if [ ! -f "$FILOGIC" ]; then
    echo "ERR: $FILOGIC not found"
    exit 1
fi
if grep -q 'zbtlink_zbt-z8803be' "$FILOGIC"; then
    echo "  device entry already present"
else
    cat >> "$FILOGIC" <<'BLOCK'

define Device/zbtlink_zbt-z8803be
  DEVICE_VENDOR := Zbtlink
  DEVICE_MODEL := ZBT-Z8803BE
  DEVICE_DTS := mt7988a-zbtlink-zbt-z8803be
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-sfp kmod-hwmon-pwmfan kmod-usb3 kmod-mt7996-firmware mt7988-2p5g-phy-firmware mt7988-wo-firmware
  DEVICE_DTC_FLAGS := --pad 4096
  SUPPORTED_DEVICES += zbtlink,zbt-z8803be,mt7988a-nand
  KERNEL := kernel-bin | gzip | \
        fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
        fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += zbtlink_zbt-z8803be
BLOCK
    echo "  appended Device/zbtlink_zbt-z8803be"
fi

echo '== done =='
echo 'Now in dst checkout run:'
echo '   git add -A && git commit -m "feat: ZBT-Z8803BE customizations replayed on upstream"'
echo '   ./.buildenv/build.sh init && ./.buildenv/build.sh feeds && ./.buildenv/build.sh config && ./.buildenv/build.sh build'
