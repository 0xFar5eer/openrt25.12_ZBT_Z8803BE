#!/usr/bin/env bash
# Fail closed: exclusions apply to resolved Kconfig AND the image, not just
# a package wish-list. This script never changes router or source state.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode=${1:?Usage: check-minimal-profile.sh config|manifest|rootfs PATH}
input=${2:?Missing input path}
forbidden='speedify|speedtest|mwan3|tailscale|openvpn|wireguard|kmod-tun|modem[-_]watchdog|qmodem[-_]monitor|qmodem-monitor|zbt[-_]modem[-_]events|(^|-)netperf|(^|-)iperf|ovpn-dco|openmptcp'
case "$mode" in
  config)
    packages=$(sed -nE 's/^CONFIG_PACKAGE_(.+)=[ym]$/\1/p' "$input")
    ;;
  manifest)
    packages=$(awk '{print $1}' "$input")
    ;;
  rootfs)
    [[ -d "$input/etc" && -d "$input/usr" ]] || exit 2
    while IFS= read -r relative; do
      [[ -z "$relative" || "$relative" = \#* ]] && continue
      if [[ -e "$input/$relative" || -L "$input/$relative" ]]; then
        echo "Excluded cellular recovery file in image: $relative" >&2; exit 4
      fi
    done < "$repo_root/firmware/profiles/excluded-base-files.txt"
    forbidden_files=$(find "$input/etc/init.d" "$input/etc/rc.d" "$input/usr/sbin" \
      "$input/usr/share/luci/menu.d" "$input/www/luci-static/resources/view" \
      -type f -o -type l | grep -E "$forbidden" || true)
    [[ -z "$forbidden_files" ]] || { echo "Excluded runtime files: $forbidden_files" >&2; exit 4; }
    grep -qx minimal "$input/etc/zbt-build-flavor"
    test -x "$input/etc/init.d/uhttpd"
    echo 'minimal_rootfs_checks=passed'
    exit 0
    ;;
  *) echo "Unknown check mode: $mode" >&2; exit 2 ;;
esac
unexpected=$(printf '%s\n' "$packages" | grep -E "$forbidden" || true)
[[ -z "$unexpected" ]] || { echo "Excluded packages selected in $mode: $unexpected" >&2; exit 3; }
echo "minimal_${mode}_checks=passed"
