#!/bin/sh
# Static regression checks for ZBT-Z8803BE firmware customizations.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bf="$root/target/linux/mediatek/filogic/base-files"
seed="$root/.buildenv/zbt8803be.config"
replay="$root/.buildenv/replay-customizations.sh"
failover30="$bf/etc/uci-defaults/30-zbt-z8803be-wan-failover"
failover32="$bf/etc/uci-defaults/32-zbt-z8803be-wan-failover"
auto="$bf/etc/hotplug.d/usb/40-zbt-qmodem-autoenable"
watchdog="$bf/usr/sbin/zbt-qmodem-watchdog-loop"
watchdog_init="$bf/etc/init.d/zbt_qmodem_watchdog"
rndis="$bf/etc/hotplug.d/net/15-zbt-rndis-auto"
ttl="$bf/etc/uci-defaults/54-zbt-qmodem-ttl-defaults"
natprobe="$bf/usr/sbin/zbt-modem-nat-probe"
ttlhook="$bf/etc/hotplug.d/iface/60-zbt-ttl-probe"

require() {
	grep -Fq "$2" "$1" || {
		printf 'missing %s in %s\n' "$2" "$1" >&2
		exit 1
	}
}

# Negative checks look at code only: these files carry long comments that quote
# the very strings we are forbidding to explain why they went away.
forbid() {
	if grep -v '^[[:space:]]*#' "$1" | grep -Fq "$2"; then
		printf 'unexpected %s in %s\n' "$2" "$1" >&2
		exit 1
	fi
	return 0
}

# Renumbering a uci-default or hotplug handler without deleting the old file
# leaves both in the image, and hotplug handlers then run twice per event. The
# stale 30-zbt-qmodem-autoenable in particular restarted qmodem_network on
# every USB add, which is the redial storm reported in issue #9.
absent() {
	if [ -e "$1" ]; then
		printf 'stale duplicate shipped: %s\n' "$1" >&2
		exit 1
	fi
	return 0
}

require_exec() {
	[ -x "$1" ] || {
		printf 'not executable: %s\n' "$1" >&2
		exit 1
	}
}

require "$seed" 'CONFIG_PACKAGE_luci-app-mlo=y'
require "$seed" 'CONFIG_PACKAGE_coreutils-timeout=y'
require "$auto" '4-1) section=4_1; power=5g1'
require "$auto" '4-2) section=4_2; power=5g2'
require "$auto" 'set_q "qmodem.$section.path" "$usb_path"'
require "$watchdog" 'case "$sec" in 4_1|4_2)'
require "$watchdog" 'slot="${sec/_/-}"'
require "$watchdog" 'power="$(slot_power "$sec")"'
require "$rndis" '4-1) rndis_slot=4_1'
require "$rndis" '4-2) rndis_slot=4_2'
require "$seed" 'CONFIG_PACKAGE_luci-app-qmodem-ttlfw4=y'
require "$ttl" "qmodem_ttl.main.ttl='64'"
require "$ttl" "qmodem_ttl.main.enable='0'"
require "$ttl" '/etc/init.d/qmodem_ttl disable'
require "$ttl" 'zbt-modem-nat-probe'

# Issue #9: the WWAN stubs must state the proto QModem's set_if() would pick
# anyway, or QModem rewrites them and re-runs ifup on every dial.
require "$failover30" "uci -q set network.4_1.proto='dhcp'"
require "$failover30" "uci -q set network.4_1v6.proto='dhcpv6'"
require "$failover32" "uci -q set network.4_1.proto='dhcp'"
require "$failover32" "uci -q set network.4_1v6.proto='dhcpv6'"
forbid "$failover30" "network.4_1.proto='none'"
forbid "$failover32" "network.4_1.proto='none'"
# The metric only sticks if it is written where QModem reads it back.
require "$failover30" "qmodem.4_1.metric='200'"
require "$failover32" 'qmodem.${sec}.metric=200'

# The watchdog must not trigger on the configs it commits itself, and must
# rate-limit re-asserting a section that is already healthy.
forbid "$watchdog_init" 'procd_add_reload_trigger'
require "$watchdog" 'REASSERT_MIN_INTERVAL='
require "$watchdog" 'link_healthy()'
require "$watchdog" 'recently_asserted()'
require "$watchdog" 'boot_ts'

# A USB add must not redial a profile that is already enabled.
require "$auto" 'if [ "$was_disabled" = 1 ] && [ -x /etc/init.d/qmodem_network ]; then'
require "$auto" 'set_q "qmodem.$section.metric" 200'

# Module-side NAT defeats donot_nat in QMI mode, so the TTL has to be probed.
require_exec "$natprobe"
require_exec "$ttlhook"
require "$natprobe" 'TTL_FOR_NAT=${TTL_FOR_NAT:-65}'
require "$natprobe" 'TTL_FOR_TRANSPARENT=${TTL_FOR_TRANSPARENT:-64}'
require "$natprobe" '192.0.0. 192.168.225. 10.168.'
require "$natprobe" 'zbt_auto_ttl'
require "$ttlhook" 'zbt-modem-nat-probe --apply'

absent "$bf/etc/hotplug.d/usb/30-zbt-qmodem-autoenable"
absent "$bf/etc/hotplug.d/usb/29-zbt-modem-factory-reset"
absent "$bf/etc/hotplug.d/net/00-zbt-qmi-rawip"
absent "$bf/etc/hotplug.d/net/10-zbt-modem-led"
absent "$bf/etc/hotplug.d/iface/30-zbt-status-led"
absent "$bf/etc/hotplug.d/iface/30-zbt-wwan-dns"

# Anything new outside an allowlisted directory must be listed here too, or it
# silently never reaches a fresh upstream checkout.
for f in "$natprobe" "$ttlhook" "$rndis"; do
	require "$replay" "${f#$root/}"
done

for file in "$auto" "$watchdog" "$watchdog_init" "$rndis" "$ttl" \
	"$failover30" "$failover32" "$natprobe" "$ttlhook"; do
	sh -n "$file"
done

printf 'zbt firmware static checks passed\n'
