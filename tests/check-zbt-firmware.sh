#!/bin/sh
# Static regression checks for ZBT-Z8803BE firmware customizations.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
seed="$root/.buildenv/zbt8803be.config"
auto="$root/target/linux/mediatek/filogic/base-files/etc/hotplug.d/usb/40-zbt-qmodem-autoenable"
watchdog="$root/target/linux/mediatek/filogic/base-files/usr/sbin/zbt-qmodem-watchdog-loop"
rndis="$root/target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/15-zbt-rndis-auto"

require() {
	grep -Fq "$2" "$1" || {
		printf 'missing %s in %s\n' "$2" "$1" >&2
		exit 1
	}
}

require "$seed" 'CONFIG_PACKAGE_luci-app-mlo=y'
require "$seed" 'CONFIG_PACKAGE_coreutils-timeout=y'
require "$auto" '4-1) section=4_1; power=5g1'
require "$auto" '4-2) section=4_2; power=5g2'
require "$auto" 'qmodem.$section.path=$usb_path'
require "$watchdog" 'case "$sec" in 4_1|4_2)'
require "$watchdog" 'slot="${sec/_/-}"'
require "$watchdog" 'power="$(slot_power "$sec")"'
require "$rndis" '4-1) rndis_slot=4_1'
require "$rndis" '4-2) rndis_slot=4_2'

for file in "$auto" "$watchdog" "$rndis"; do
	sh -n "$file"
done

printf 'zbt firmware static checks passed\n'
