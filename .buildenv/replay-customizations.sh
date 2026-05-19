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
    docs
    package/emortal
    package/luci-app-mlo
    package/luci-app-qosmate
    package/luci-app-wifi-clients
    package/luci-app-wrtbwmon
    package/luci-app-zbt-about
    package/luci-app-zbt-health
    package/luci-app-zbt-modem-events
    package/luci-app-zbt-speedtest
    package/luci-app-zbt-temperature
    package/qosmate
    package/wrtbwmon
    target/linux/mediatek/filogic/base-files/etc/profile.d
    target/linux/mediatek/filogic/base-files/etc/rc.d
    target/linux/mediatek/filogic/base-files/usr/lib/zbt
    target/linux/mediatek/filogic/base-files/usr/share/zbt
    releases
    feeds/iwrt_luci/themes/luci-theme-argon
)

# 2. Specific files (board DTS, base-files glue, init.d, hotplug, uci-defaults,
#    sbin helpers, custom branding, signing keys, kernel patches).
FILES=(
    target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts
    target/linux/mediatek/filogic/base-files/etc/banner
    target/linux/mediatek/filogic/base-files/etc/zbt-leds.sh
    target/linux/mediatek/filogic/base-files/etc/apk/keys/immortalwrt-snapshots.pem
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
    package/kernel/ntfs/patches/001-conditionally-enable-posix-acl.patch
    package/kernel/r8168/patches/002-Makefile-fix-CFLAGS-with-linux-6.15.patch
    feeds.conf.default
    .gitignore
    README.zh-CN.md
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

echo '== seed a static ./version (getver.sh fallback) =='
# OpenWrt's package/base-files Makefile derives PKG_VERSION from
# scripts/getver.sh, which calls git inside the build container. When
# the destination is a git worktree (with a .git *file* pointing at a
# gitdir under the parent repo's .git/worktrees/), the container can't
# resolve git because only the worktree path is mounted, not the main
# repo's gitdir. Result: getver.sh prints "unknown" and apk mkpkg
# rejects the version. Pre-computing ./version from the host side
# (which still has full git visibility) makes getver.sh's try_version()
# return immediately and skips the broken git path.
REBOOT=ee53a240ac902dc83209008a2671e7fdcf55957a
if [ -f "$DST/.git" ] || [ -d "$DST/.git" ]; then
    REV=$(cd "$DST" && git rev-list "${REBOOT}..HEAD" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    HASH=$(cd "$DST" && git log -n1 --format=%h HEAD 2>/dev/null || echo unknown)
    if [ "$REV" != "0" ] && [ "$HASH" != "unknown" ]; then
        echo "r${REV}-${HASH}" > "$DST/version"
        echo "  wrote $DST/version: r${REV}-${HASH}"
    else
        echo "  skip: could not compute REV/HASH from $DST"
    fi
fi

echo '== seed a per-destination Docker volume name =='
# build.sh now respects the VOL/IMAGE env vars; we drop a small env file
# in the destination so the user can `set -a; source .buildenv/local.env;
# set +a` (or a one-liner wrapper) without editing build.sh after every
# replay. Volume name is derived from the destination directory so each
# replayed worktree gets isolated build state.
DST_VOL="${DST_VOL:-$(basename "$DST")-buildvol}"
cat > "$DST/.buildenv/local.env" <<EOF
# Auto-generated by replay-customizations.sh.
# Source me before invoking build.sh so the upstream-replay tree uses
# its own Docker volume:
#     set -a; . .buildenv/local.env; set +a
#     ./.buildenv/build.sh init
# Edit DST_VOL above (in replay-customizations.sh) and re-run the script
# to change.
VOL="${DST_VOL}"
EOF
echo "  wrote $DST/.buildenv/local.env (VOL=${DST_VOL})"

echo '== done copying =='

echo '== audit: any tracked file in $SRC missing in $DST? =='
# Future-proofing: when we re-run this script after pulling new commits
# from upstream, surface any tracked file in our source tree that is NOT
# present in the destination. False positives are filtered with the
# allowlist regex below (paths that legitimately do not exist in vanilla
# upstream because they were either renamed by upstream or are tracked
# only on our side).
#
# Maintainer: when the warning surfaces a genuine new customization,
# add it to DIRS or FILES above.
audit_missing=0
( cd "$SRC" && git ls-files 2>/dev/null ) | while IFS= read -r f; do
    [ -e "$DST/$f" ] && continue
    # Filter genuine non-issues:
    #   * starfive: upstream removed RISC-V 6.12 support; not relevant
    case "$f" in
        target/linux/starfive/*) continue ;;
    esac
    echo "  WARN: $f exists in source but not in destination"
    audit_missing=$((audit_missing + 1))
done

echo ''
echo '== next steps =='
echo "Now in $DST run:"
echo '   git add -A'
echo '   git status --short | head'
echo '   git commit -m "feat: ZBT-Z8803BE customizations replayed on upstream"'
echo '   ./.buildenv/build.sh init && ./.buildenv/build.sh feeds && \\'
echo '   ./.buildenv/build.sh config && ./.buildenv/build.sh build'
