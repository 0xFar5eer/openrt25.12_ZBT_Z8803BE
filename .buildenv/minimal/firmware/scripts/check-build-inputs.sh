#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

bash -n firmware/docker/build-openwrt.sh
for script in \
  firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd \
  firmware/files/etc/uci-defaults/74-zbt-mlo-shared-iface-repair \
  firmware/files/etc/uci-defaults/99-cellular-multiwan-defaults \
  firmware/files/etc/uci-defaults/99-zbt-route-priority-repair \
  firmware/files/etc/hotplug.d/usb/40-zbt-qmodem-autoenable \
  firmware/scripts/apply-router-defaults.sh \
  firmware/scripts/verify-router-runtime.sh; do
  sh -n "${script}"
done

# Cover every new overlay/feed shell entry point, including rpcd backends
# whose filenames do not end in .sh. Libraries are parsed but never run.
while IFS= read -r script; do
  case "$(head -n 1 "$script")" in
    '#!/bin/sh'*) sh -n "$script" ;;
  esac
done < <(rg --files firmware/files)
bash -n firmware/scripts/check-minimal-profile.sh
bash firmware/scripts/check-minimal-profile.sh config firmware/profiles/kconfig-fragment.conf

grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y' \
  firmware/profiles/base-config-zbt-z8803be-v25.12.021.config
printf '%s  %s\n' \
  '98b960b5fcd0908453387b9a1d17efa2d7a0ea03c58eab65e752b5873362028a' \
  'firmware/profiles/base-config-zbt-z8803be-v25.12.021.config' | sha256sum -c -

required_packages=(
  ca-bundle curl
)
for package in "${required_packages[@]}"; do
  grep -qx "${package}" firmware/profiles/packages-default.txt || {
    echo "Missing required minimal package: ${package}" >&2
    exit 1
  }
done

test -s firmware/patches/luci-app-mlo-shared-iface.patch
grep -Fq "writeCommon(mldIface, selectedDevices);" firmware/patches/luci-app-mlo-shared-iface.patch
hostapd_mlo_patch=firmware/patches/hostapd-mlo-interoperability.patch
test -s "$hostapd_mlo_patch"
grep -Fq 'AP MLD: Clear reserved fields in EML capability for AP MLD' "$hostapd_mlo_patch"
grep -Fq 'nl80211: Avoid bogus ENFILE with use_existing' "$hostapd_mlo_patch"
grep -Fq 'hostapd_remove_hapd_iface' "$hostapd_mlo_patch"
grep -Fq 'ap_sta_free_sta_profile(info);' "$hostapd_mlo_patch"
grep -Fq 'hostapd_mlo_patch_target=package/network/services/hostapd/patches/804-zbt-mlo-interoperability.patch' \
  firmware/docker/build-openwrt.sh
grep -Fq "uci -q add_list \"wireless.\${first}.device=\${device}\"" \
  firmware/files/etc/uci-defaults/74-zbt-mlo-shared-iface-repair
if grep -Eq '(^|/)(sbin/)?wifi[[:space:]]+reload|zbt-wifi-reload-deferred' \
  firmware/files/etc/uci-defaults/74-zbt-mlo-shared-iface-repair; then
  echo 'Wi-Fi UCI defaults must not reload wireless during first network bring-up' >&2
  exit 1
fi

# LuCI must remain reachable over warning-free LAN HTTP while preserving the
# optional HTTPS listener. This is a one-time migration so operator changes
# made after first boot are not overwritten on every upgrade.
grep -Fq "uci -q add_list uhttpd.main.listen_http='0.0.0.0:80'" \
  firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd
grep -Fq "uci -q add_list uhttpd.main.listen_http='[::]:80'" \
  firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd
grep -Fq "uci -q set uhttpd.main.redirect_https='0'" \
  firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd
grep -Fq "system.zbt_luci_http.uhttpd_migrated" \
  firmware/files/etc/uci-defaults/50-zbt-luci-uhttpd

# The minimal image has no MWAN3 UI, but its stable base route order must
# still survive QModem disconnect/redial cycles.
grep -Fq 'network_metric=$(uci -q get network.${interface_name}.metric)' \
  firmware/patches/qmodem-dual-runtime.patch
grep -Fq 'Keep the stable 4_1/2_1 record that MWAN3 tracks' \
  firmware/patches/qmodem-dual-runtime.patch
grep -Fq "form.DummyValue, '_route_metric'" firmware/patches/qmodem-dual-runtime.patch
grep -Fq "uci.load('network')" firmware/patches/qmodem-dual-runtime.patch
grep -Fq '4_1:200 2_1:210' \
  firmware/files/etc/uci-defaults/99-zbt-route-priority-repair
grep -Fq 'DEFAULTS_VERSION=2' firmware/files/etc/uci-defaults/99-zbt-route-priority-repair
grep -Fq 'uci -q set "network.$section.metric=$metric"' \
  firmware/files/etc/uci-defaults/99-zbt-route-priority-repair
grep -Fq 'uci -q set "qmodem.$section.metric=$metric"' \
  firmware/files/etc/uci-defaults/99-zbt-route-priority-repair
if rg -n -i 'speedify' firmware/files firmware/profiles/packages-default.txt; then
  echo 'Minimal image inputs still contain Speedify runtime content' >&2
  exit 1
fi
grep -qx '# CONFIG_PACKAGE_kmod-tun is not set' firmware/profiles/kconfig-fragment.conf
grep -qx minimal firmware/files/etc/zbt-build-flavor

grep -q "OPENWRT_GIT_REF:-v25.12.021" firmware/docker/build-openwrt.sh
grep -q "OPENWRT_GIT_URL:-https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE.git" \
  firmware/docker/build-openwrt.sh
grep -q "EXPECTED_OPENWRT_COMMIT:-edc738504fe8fae81eb15de967456204699b1830" \
  firmware/docker/build-openwrt.sh

echo 'firmware_input_checks=passed'
