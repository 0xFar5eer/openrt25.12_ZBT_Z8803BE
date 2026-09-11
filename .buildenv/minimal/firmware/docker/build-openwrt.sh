#!/usr/bin/env bash
set -euo pipefail
FIRMWARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENWRT_ROOT="${OPENWRT_ROOT:-/workspace/openwrt}"
OPENWRT_GIT_URL="${OPENWRT_GIT_URL:-https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE.git}"
OPENWRT_GIT_REF="${OPENWRT_GIT_REF:-v25.12.021}"
EXPECTED_OPENWRT_COMMIT="${EXPECTED_OPENWRT_COMMIT:-edc738504fe8fae81eb15de967456204699b1830}"
ALLOW_CLONE_OPENWRT="${ALLOW_CLONE_OPENWRT:-1}"
PROFILE_PACKAGES_FILE="${PROFILE_PACKAGES_FILE:-/workspace/firmware/profiles/packages-default.txt}"
PROFILE_PACKAGES_EXTRA_FILES="${PROFILE_PACKAGES_EXTRA_FILES:-}"
PROFILE_KCONFIG_FILE="${PROFILE_KCONFIG_FILE:-/workspace/firmware/profiles/kconfig-fragment.conf}"
BASE_CONFIG_FILE="${BASE_CONFIG_FILE:-/workspace/firmware/profiles/base-config-zbt-z8803be-v25.12.021.config}"
FILES_OVERLAY_DIR="${FILES_OVERLAY_DIR:-/workspace/firmware/files}"
TARGET="${TARGET:-mediatek/filogic}"
SUBTARGET="${SUBTARGET:-}"
DEVICE="${DEVICE:-zbtlink_zbt-z8803be}"
FINAL_MAKE_JOBS="${FINAL_MAKE_JOBS:-$(nproc)}"
HOST_MAKE_JOBS="${HOST_MAKE_JOBS:-1}"
[[ "$HOST_MAKE_JOBS" =~ ^[1-9][0-9]*$ && "$FINAL_MAKE_JOBS" =~ ^[1-9][0-9]*$ ]] || {
  echo 'Build job counts must be positive integers' >&2; exit 2;
}
if [[ ! -d "${OPENWRT_ROOT}" ]]; then
  if [[ "${ALLOW_CLONE_OPENWRT}" = "1" ]]; then
    git clone --depth 1 --branch "${OPENWRT_GIT_REF}" "${OPENWRT_GIT_URL}" "${OPENWRT_ROOT}"
  else
    echo "Missing OPENWRT_ROOT: ${OPENWRT_ROOT}" >&2
    exit 2
  fi
fi
cd "${OPENWRT_ROOT}"
export FORCE_UNSAFE_CONFIGURE=1
resolved_openwrt_commit="$(git rev-parse HEAD)"
echo "OpenWrt source: ${OPENWRT_GIT_URL} ${OPENWRT_GIT_REF} (${resolved_openwrt_commit})"
if [[ -n "${EXPECTED_OPENWRT_COMMIT}" && "${resolved_openwrt_commit}" != "${EXPECTED_OPENWRT_COMMIT}" ]]; then
  echo "OpenWrt ref resolved to ${resolved_openwrt_commit}; expected ${EXPECTED_OPENWRT_COMMIT}" >&2
  exit 2
fi
printf '%s  %s\n' \
  '9adb2d14a022727f12364ab6040d15a0d7391465e33abff03602923196e508e4' \
  'target/linux/mediatek/filogic/base-files/etc/zbt-leds.sh' | sha256sum -c -
./scripts/feeds update -a
./scripts/feeds install -a
# The userspace fixes below are reviewed against these exact feed revisions.
[[ "$(git -C feeds/qmodem rev-parse HEAD)" = a8b8a63e5b0853c79d2ad3f1ebbb673a724872bf ]] || {
  echo 'Unexpected QModem revision; review runtime patches before building' >&2; exit 3;
}
[[ "$(git -C feeds/packages rev-parse HEAD)" = db3b315119519f9194dad8aa668aa40618df9b20 ]] || {
  echo 'Unexpected packages revision; review dependency pins before building' >&2; exit 3;
}
# Strict userspace-only patch against the pinned QModem feed. No kernel,
# modem driver or wireless firmware revision changes.
runtime_patch="${FIRMWARE_DIR}/patches/qmodem-dual-runtime.patch"
if patch --dry-run --batch --fuzz=0 --forward -p1 -d feeds/qmodem < "$runtime_patch" >/dev/null; then
  patch --batch --fuzz=0 --forward -p1 -d feeds/qmodem < "$runtime_patch"
elif ! patch --dry-run --batch --fuzz=0 --reverse -p1 -d feeds/qmodem < "$runtime_patch" >/dev/null; then
  echo 'Pinned QModem runtime patch no longer matches; refusing an unpatched build' >&2
  exit 3
fi
for apn in broadband NXTGENPHONE ENHANCEDPHONE firstnet-broadband fast.t-mobile.com vzwinternet h2g2 h2g2-t usccinternet; do
  [ "$(grep -Fo "o.value('$apn'" feeds/qmodem/luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/network_config.js | wc -l)" -eq 2 ] || {
    echo "US APN preset is not present for both QModem SIM selectors: $apn" >&2; exit 3;
  }
done
led_patch="${FIRMWARE_DIR}/patches/zbt-wan-led.patch"
if patch --dry-run --batch --fuzz=0 --forward -p1 < "$led_patch" >/dev/null; then
  patch --batch --fuzz=0 --forward -p1 < "$led_patch"
elif ! patch --dry-run --batch --fuzz=0 --reverse -p1 < "$led_patch" >/dev/null; then
  echo 'WAN LED device-tree patch does not match the pinned board' >&2
  exit 3
fi
# Far5eer's base files carry a pre-created S95 link. Replacing the init script
# with START=97 causes OpenWrt to generate the correct S97 link as well, so the
# legacy link must be removed before rootfs assembly or two owners race at boot.
# Validate its exact target before deleting it; an upstream layout change must
# fail closed instead of silently removing an unrelated service.
legacy_modem_led_link=target/linux/mediatek/filogic/base-files/etc/rc.d/S95zbt-modem-leds
if [[ -L "$legacy_modem_led_link" ]]; then
  [[ "$(readlink "$legacy_modem_led_link")" = ../init.d/zbt-modem-leds ]] || {
    echo 'Unexpected legacy modem LED startup link target' >&2; exit 3;
  }
  rm -f -- "$legacy_modem_led_link"
elif [[ -e "$legacy_modem_led_link" ]]; then
  echo 'Legacy modem LED startup path is not the expected symlink' >&2
  exit 3
fi
mlo_patch="${FIRMWARE_DIR}/patches/luci-app-mlo-shared-iface.patch"
if patch --dry-run --batch --fuzz=0 --forward -p1 -d package/luci-app-mlo < "$mlo_patch" >/dev/null; then
  patch --batch --fuzz=0 --forward -p1 -d package/luci-app-mlo < "$mlo_patch"
elif ! patch --dry-run --batch --fuzz=0 --reverse -p1 -d package/luci-app-mlo < "$mlo_patch" >/dev/null; then
  echo 'MLO shared-interface patch does not match the pinned source' >&2
  exit 3
fi
grep -Eq 'writeCommon\(mldIface,[[:space:]]*selectedDevices\);' \
  package/luci-app-mlo/htdocs/luci-static/resources/view/mlo/main.js || {
  echo 'MLO page did not retain the shared multi-radio writer' >&2; exit 3;
}
# Keep the pinned hostapd release while applying reviewed upstream AP-MLD
# interoperability and reload fixes after OpenWrt's package patch queue.
hostapd_mlo_patch="${FIRMWARE_DIR}/patches/hostapd-mlo-interoperability.patch"
hostapd_mlo_patch_target=package/network/services/hostapd/patches/804-zbt-mlo-interoperability.patch
if ! cmp -s "$hostapd_mlo_patch" "$hostapd_mlo_patch_target"; then
  cp "$hostapd_mlo_patch" "$hostapd_mlo_patch_target"
fi
# Add LED callbacks to the pinned MT7988 Ethernet PHY driver before the kernel
# is prepared. The kernel version, modem drivers and power/SIM pins stay pinned.
cp "${FIRMWARE_DIR}/kernel-patches/753-net-phy-mediatek-mt7988-led-control.patch" \
  target/linux/mediatek/patches-6.12/753-net-phy-mediatek-mt7988-led-control.patch
# Remove only explicitly listed inherited cellular-watchdog files. Leaving
# their UCI installer behind would recreate the monitor even without its APK.
while IFS= read -r relative; do
  [[ -z "$relative" || "$relative" = \#* ]] && continue
  case "$relative" in etc/*|usr/*) ;; *) exit 3 ;; esac
  [[ "$relative" != *..* && "$relative" != *'*'* ]] || exit 3
  rm -f -- "target/linux/mediatek/filogic/base-files/$relative"
done < "${FIRMWARE_DIR}/profiles/excluded-base-files.txt"
mkdir -p files
if [[ -d "${FILES_OVERLAY_DIR}" ]]; then
  # This source tree is intentionally reusable between local builds. Mirror
  # the selected edition exactly so files removed from an overlay cannot leak
  # into a later firmware image through OpenWrt's persistent files/ directory.
  rsync -a --delete "${FILES_OVERLAY_DIR}/" files/
fi
if [[ -d "files/etc/uci-defaults" ]]; then
  chmod +x files/etc/uci-defaults/* 2>/dev/null || true
fi
# Git-created overlay helpers must be executable in the image.
find files/etc/init.d files/etc/hotplug.d files/usr/sbin -type f -exec chmod 755 {} +
cp -f .config .config.bak 2>/dev/null || true
target_main="${TARGET%%/*}"
target_sub="${TARGET#*/}"
if [[ "${target_sub}" = "${TARGET}" ]]; then
  target_sub=""
fi
if [[ -z "${SUBTARGET}" && -n "${target_sub}" ]]; then
  SUBTARGET="${target_sub}"
fi
if [[ -f "${BASE_CONFIG_FILE}" ]]; then
  cp -f "${BASE_CONFIG_FILE}" .config
else
cat > .config <<EOF
CONFIG_TARGET_${target_main}=y
EOF
fi
if [[ -n "${SUBTARGET}" ]]; then
  echo "CONFIG_TARGET_${target_main}_${SUBTARGET}=y" >> .config
  target_device_config="CONFIG_TARGET_${target_main}_${SUBTARGET}_DEVICE_${DEVICE}"
else
  target_device_config="CONFIG_TARGET_${target_main}_DEVICE_${DEVICE}"
fi
echo "${target_device_config}=y" >> .config
if [[ -f "${PROFILE_PACKAGES_FILE}" ]]; then
  while IFS= read -r pkg; do
    [[ -z "${pkg}" || "${pkg}" =~ ^# ]] && continue
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
  done < "${PROFILE_PACKAGES_FILE}"
fi
if [[ -n "${PROFILE_PACKAGES_EXTRA_FILES}" ]]; then
  IFS=',' read -r -a extra_files <<< "${PROFILE_PACKAGES_EXTRA_FILES}"
  for extra_file in "${extra_files[@]}"; do
    [[ -f "${extra_file}" ]] || continue
    while IFS= read -r pkg; do
      [[ -z "${pkg}" || "${pkg}" =~ ^# ]] && continue
      echo "CONFIG_PACKAGE_${pkg}=y" >> .config
    done < "${extra_file}"
  done
fi
if [[ -f "${PROFILE_KCONFIG_FILE}" ]]; then
  cat "${PROFILE_KCONFIG_FILE}" >> .config
fi
make defconfig
# Source patches are not guaranteed to invalidate package stamps in a reused
# OpenWrt tree. Rebuild every directly patched package so an incremental build
# cannot ship an older dialer, QModem UI, MLO writer, or hostapd binary.
make package/feeds/qmodem/qmodem/clean
make package/feeds/qmodem/luci-app-qmodem-next/clean
make package/luci-app-mlo/clean
make package/network/services/hostapd/clean
bash "${FIRMWARE_DIR}/scripts/check-minimal-profile.sh" config .config
required_config_flags=(
  "${target_device_config}=y"
  "CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y"
  "CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y"
  "CONFIG_PACKAGE_kmod-usb-wdm=y"
  "CONFIG_PACKAGE_kmod-usb-serial-option=y"
  "CONFIG_PACKAGE_uqmi=y"
  "CONFIG_PACKAGE_umbim=y"
  "CONFIG_PACKAGE_qmodem=y"
  "CONFIG_PACKAGE_luci-app-qmodem-next=y"
  "CONFIG_PACKAGE_luci-app-qmodem-ttlfw4=y"
  "CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_ADD_QFIREHOSE_SUPPORT=y"
  "CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan=y"
  "CONFIG_PACKAGE_luci-proto-qmi=y"
  "CONFIG_PACKAGE_luci-proto-mbim=y"
  "CONFIG_PACKAGE_quectel-CM-5G-M=y"
  "CONFIG_PACKAGE_luci-app-mlo=y"
  "CONFIG_PACKAGE_wpad-openssl=y"
  "CONFIG_PACKAGE_ndisc6=y"
  "CONFIG_PACKAGE_kmod-mhi-bus=y"
  "CONFIG_PACKAGE_kmod-mhi-net=y"
  "CONFIG_PACKAGE_kmod-mhi-pci-generic=y"
  "CONFIG_PACKAGE_kmod-mhi-wwan-ctrl=y"
  "CONFIG_PACKAGE_kmod-mhi-wwan-mbim=y"
  "CONFIG_PACKAGE_ca-bundle=y"
  "CONFIG_PACKAGE_curl=y"
  "CONFIG_PACKAGE_libatomic=y"
  "CONFIG_PACKAGE_uhttpd=y"
  "CONFIG_PACKAGE_uhttpd-mod-ubus=y"
)
for cfg in "${required_config_flags[@]}"; do
  if ! grep -q "^${cfg}$" .config; then
    echo "Required package missing from resolved config: ${cfg}" >&2
    exit 3
  fi
done
make tools/install -j"${HOST_MAKE_JOBS}" V=s
make toolchain/install -j"${HOST_MAKE_JOBS}" V=s
# Let the selected package dependency graph drive host tools. No forced Go
# bootstrap for removed Tailscale/speedtest-go packages.
make -j"${FINAL_MAKE_JOBS}" V=s

manifest="$(find "bin/targets/${target_main}/${SUBTARGET}" -maxdepth 1 -type f -name "*zbt-z8803be*.manifest" -print -quit)"
if [[ -z "${manifest}" ]]; then
  echo "No ZBT-Z8803BE image manifest was produced" >&2
  exit 4
fi
bash "${FIRMWARE_DIR}/scripts/check-minimal-profile.sh" manifest "$manifest"
required_image_packages=(
  kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-wdm
  kmod-usb-serial-option uqmi umbim luci-proto-qmi luci-proto-mbim
  qmodem luci-app-qmodem-next
  luci-app-qmodem-ttlfw4 quectel-CM-5G-M ndisc6
  luci-app-mlo wpad-openssl
  kmod-mhi-bus kmod-mhi-net kmod-mhi-pci-generic
  kmod-mhi-wwan-ctrl kmod-mhi-wwan-mbim
  ca-bundle curl libatomic1 uhttpd uhttpd-mod-ubus
)
for package in "${required_image_packages[@]}"; do
  if ! grep -q "^${package} - " "${manifest}"; then
    echo "Required runtime package missing from image manifest: ${package}" >&2
    exit 4
  fi
done
echo "Validated image manifest: ${manifest}"

rootfs_dir="$(find build_dir -maxdepth 2 -type d -name 'root-mediatek' -print -quit)"
if [[ -z "${rootfs_dir}" ]]; then
  echo "Unable to locate the built MediaTek root filesystem" >&2
  exit 4
fi
required_overlay_files=(
  etc/zbt-build-flavor
  etc/uci-defaults/99-cellular-multiwan-defaults
  etc/uci-defaults/99-zbt-route-priority-repair
  usr/lib/zbt/dual-modem.sh
  usr/lib/zbt/modem-leds.sh
  etc/init.d/zbt-modem-leds
  etc/uci-defaults/48-zbt-modem-led-dark-repair
  etc/uci-defaults/49-zbt-modem-labels-leds
  etc/uci-defaults/50-zbt-luci-uhttpd
  etc/uci-defaults/74-zbt-mlo-shared-iface-repair
  usr/lib/zbt/quectel-bands.sh
  usr/sbin/zbt-qmodem-profile
  usr/sbin/zbt-modem-led-poller
  etc/init.d/qmodem_network
)
for overlay_file in "${required_overlay_files[@]}"; do
  if [[ ! -s "${rootfs_dir}/${overlay_file}" ]]; then
    echo "Required overlay file missing from built root filesystem: ${overlay_file}" >&2
    exit 4
  fi
done
echo "Validated files overlay in root filesystem: ${rootfs_dir}"
# A package/base-files install must expose exactly one modem LED owner. S97
# deliberately runs after OpenWrt's generic S96 LED configuration service.
[ "$(readlink "${rootfs_dir}/etc/rc.d/S97zbt-modem-leds")" = ../init.d/zbt-modem-leds ] || {
  echo 'Modem LED boot service is not enabled at S97 in the image' >&2; exit 4;
}
mapfile -t modem_led_links < <(find "${rootfs_dir}/etc/rc.d" -maxdepth 1 -type l -name 'S??zbt-modem-leds' -print)
[ "${#modem_led_links[@]}" -eq 1 ] || {
  printf 'Expected one modem LED startup link, found %s: %s\n' "${#modem_led_links[@]}" "${modem_led_links[*]}" >&2
  exit 4
}
[ "$(readlink "${rootfs_dir}/etc/rc.d/S10zbt-leds")" = ../init.d/zbt-leds ] || {
  echo 'Far5eer status LED state machine is not enabled at S10' >&2; exit 4;
}
test -x "${rootfs_dir}/etc/zbt-leds.sh" && test -x "${rootfs_dir}/etc/hotplug.d/iface/40-zbt-status-led" || {
  echo 'Far5eer status LED runtime is missing from the image' >&2; exit 4;
}
cmp target/linux/mediatek/filogic/base-files/etc/zbt-leds.sh "${rootfs_dir}/etc/zbt-leds.sh" || {
  echo 'Far5eer modem/status LED helper was changed or overwritten in rootfs' >&2; exit 4;
}
for overlay_file in usr/lib/zbt/modem-leds.sh usr/sbin/zbt-modem-led-poller etc/init.d/zbt-modem-leds etc/hotplug.d/net/20-zbt-modem-led usr/sbin/zbt-qmodem-profile etc/uci-defaults/48-zbt-modem-led-dark-repair etc/uci-defaults/49-zbt-modem-labels-leds etc/uci-defaults/50-zbt-luci-uhttpd etc/uci-defaults/74-zbt-mlo-shared-iface-repair etc/uci-defaults/99-cellular-multiwan-defaults etc/uci-defaults/99-zbt-route-priority-repair; do
  cmp -s "${FILES_OVERLAY_DIR}/${overlay_file}" "${rootfs_dir}/${overlay_file}" || {
    echo "Runtime repair was overwritten in rootfs: ${overlay_file}" >&2; exit 4;
  }
done
grep -Fq 'network_metric=$(uci -q get network.${interface_name}.metric)' \
  "${rootfs_dir}/usr/share/qmodem/modem_dial.sh" || {
  echo 'QModem is not consuming the persistent network route metric' >&2; exit 4;
}
grep -Eq "form\.DummyValue,[[:space:]]*'_route_metric'" \
  "${rootfs_dir}/www/luci-static/resources/view/qmodem/network_config.js" || {
  echo 'QModem read-only route-metric display is missing from the image' >&2; exit 4;
}
[ "$(readlink "${rootfs_dir}/etc/rc.d/S50uhttpd")" = ../init.d/uhttpd ] || {
  echo 'Stock LuCI uhttpd frontend is not enabled at S50' >&2; exit 4;
}
grep -Eq 'writeCommon\(mldIface,[[:space:]]*selectedDevices\);' \
  "${rootfs_dir}/www/luci-static/resources/view/mlo/main.js" || {
  echo 'Corrected shared-interface MLO page is missing from the image' >&2; exit 4;
}
# Keep the upstream package from silently restoring the global-only TTL UI
# or old init/hotplug/default writers over this firmware's independent policy.
for overlay_file in \
  usr/lib/zbt/ttl.sh usr/sbin/zbt-qmodem-ttl etc/init.d/qmodem_ttl \
  etc/nftables.d/99-qmodem-ttl.nft \
  etc/hotplug.d/net/95-zbt-qmodem-ttl etc/hotplug.d/iface/60-zbt-ttl-probe \
  etc/uci-defaults/36-zbt-z8803be-wan-speed-mode etc/uci-defaults/54-zbt-qmodem-ttl-defaults \
  www/luci-static/resources/view/qmodem/ttl.js \
  usr/share/rpcd/acl.d/luci-app-qmodem-ttlfw4.json; do
  cmp -s "${FILES_OVERLAY_DIR}/${overlay_file}" "${rootfs_dir}/${overlay_file}" || {
    echo "Per-modem TTL repair missing or overwritten in rootfs: ${overlay_file}" >&2; exit 4;
  }
done
for ui_file in qmodem/qmodem.js view/qmodem/network_config.js view/qmodem/settings.js; do
  grep -q display_name "${rootfs_dir}/www/luci-static/resources/${ui_file}" || {
    echo "Friendly modem labels missing from built LuCI: ${ui_file}" >&2; exit 4;
  }
done
for apn in broadband NXTGENPHONE ENHANCEDPHONE firstnet-broadband fast.t-mobile.com vzwinternet h2g2 h2g2-t usccinternet; do
  [ "$(grep -Fo "o.value('$apn'" "${rootfs_dir}/www/luci-static/resources/view/qmodem/network_config.js" | wc -l)" -eq 2 ] || {
    echo "US APN preset missing from one or both built SIM selectors: $apn" >&2; exit 4;
  }
done
bash "${FIRMWARE_DIR}/scripts/check-minimal-profile.sh" rootfs "$rootfs_dir"

for image_pattern in '*zbt-z8803be-initramfs-kernel.bin' '*zbt-z8803be-squashfs-sysupgrade.bin'; do
  image="$(find "bin/targets/${target_main}/${SUBTARGET}" -maxdepth 1 -type f -size +0c -name "${image_pattern}" -print -quit)"
  if [[ -z "${image}" ]]; then
    echo "Required ZBT-Z8803BE image was not produced: ${image_pattern}" >&2
    exit 4
  fi
  echo "Validated firmware image: ${image}"
done
