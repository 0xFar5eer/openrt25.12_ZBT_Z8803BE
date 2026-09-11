#!/bin/sh
# Static regression checks for ZBT-Z8803BE firmware customizations.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
bf="$root/target/linux/mediatek/filogic/base-files"
seed="$root/.buildenv/zbt8803be.config"
replay="$root/.buildenv/replay-customizations.sh"
failover32="$bf/etc/uci-defaults/32-zbt-z8803be-wan-failover"
speedmode="$bf/etc/uci-defaults/36-zbt-z8803be-wan-speed-mode"
noula="$bf/etc/uci-defaults/37-zbt-z8803be-no-ula"
autostart="$bf/etc/uci-defaults/99-zbt-z8803be-qmodem-autostart"
gpioboard="$bf/etc/board.d/03_gpio_switches"
auto="$bf/etc/hotplug.d/usb/40-zbt-qmodem-autoenable"
watchdog="$bf/usr/sbin/zbt-qmodem-watchdog-loop"
watchdog_init="$bf/etc/init.d/zbt_qmodem_watchdog"
rndis="$bf/etc/hotplug.d/net/15-zbt-rndis-auto"
ledhot="$bf/etc/hotplug.d/net/20-zbt-modem-led"
slots="$bf/etc/uci-defaults/20-zbt-qmodem-slots"
mlorepair="$bf/etc/uci-defaults/74-zbt-mlo-shared-iface-repair"
mlojs="$root/package/luci-app-mlo/htdocs/luci-static/resources/view/mlo/main.js"
qmodem_dial="$root/package/qmodem/files/usr/share/qmodem/modem_dial.sh"
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
# A second modem must never be bounced by RNDIS detection on the other
# slot: hang only the detected profile's dialer instance.
require "$rndis" 'qmodem_network hang "$rndis_slot"'
forbid "$rndis" 'qmodem_network restart'
# The modem LED hotplug handler binds by exact USB slot path: the qmodem
# modem-slot led option first, then the hard-wired 4-1/4-2 fallback. A
# suffix map (*-1/*-2) misbinds usb1/usb2 root-hub ports like 2-1 to the
# 5G1 LED even though no modem slot lives there.
require "$ledhot" 'qmodem.$led_sec.led'
require "$ledhot" '4-1) [ -n "$led_name" ] || led_name="blue:mobile-1"'
require "$ledhot" '4-2) [ -n "$led_name" ] || led_name="blue:mobile-2"'
require "$ledhot" 'no LED mapping for USB slot'
forbid "$ledhot" '*-1)'
forbid "$ledhot" '*-2)'
require "$slots" "qmodem.@modem-slot[-1].led='blue:mobile-1'"
require "$slots" "qmodem.@modem-slot[-1].led='blue:mobile-2'"
# package/qmodem vendors the pinned feed app so dialer fixes are carried
# in-tree (upstream's Build/Prepare is empty, so a patches/ dir would never
# apply). The fixes must stay in and the dual-modem/proto=none rewrites out.
require "$seed" 'CONFIG_PACKAGE_qmodem=y'
require "$qmodem_dial" 'network_metric=$(uci -q get network.${interface_name}.metric)'
require "$qmodem_dial" 'if [ "$network_cfg" = "$interface_name" ]; then'
require "$qmodem_dial" '[ -z "$pincode" ] && config_get pincode $modem_config pincode'
require "$qmodem_dial" '[ -z "$suggest_pdp_index" ] && suggest_pdp_index=$(get_platform_suggest_pdp_index)'
forbid "$qmodem_dial" 'zbt_netcard'
forbid "$qmodem_dial" 'dual-modem.sh'
forbid "$qmodem_dial" 'qmi|mbim|mhi) proto="none"'
# MLO must be written as ONE shared wifi-iface with a device list; per-band
# mlo=1 sections yield single-link MLDs that never group. The migration
# uci-default repairs records saved by older app versions.
require "$mlojs" 'function sectionDevices(section)'
require "$mlojs" "uci.set('wireless', mldIface, 'mlo', '1')"
require "$mlorepair" 'uci -q add_list "wireless.${first}.device=${device}"'
require "$mlorepair" 'uci -q set "wireless.${first}.mlo=1"'
require "$mlorepair" 'uci -q delete "wireless.${member}"'
require "$seed" 'CONFIG_PACKAGE_luci-app-qmodem-ttlfw4=y'
require "$ttl" "qmodem_ttl.main.ttl='64'"
require "$ttl" "qmodem_ttl.main.enable='0'"
require "$ttl" '/etc/init.d/qmodem_ttl disable'
require "$ttl" 'zbt-modem-nat-probe'

# Issue #9: the WWAN stubs must state the proto QModem's set_if() would pick
# anyway, or QModem rewrites them and re-runs ifup on every dial.
require "$failover32" "uci -q set network.4_1.proto='dhcp'"
require "$failover32" "uci -q set network.4_1v6.proto='dhcpv6'"
forbid "$failover32" "network.4_1.proto='none'"
# The metric only sticks if it is written where QModem reads it back.
require "$failover32" 'qmodem.${sec}.metric=200'

# WAN failover must be create-if-missing: an earlier revision deleted and
# recreated network.wan/wan6/wan_sfp unconditionally, stomping operator
# customisations and force-adding every uplink to the stock wan zone.
forbid "$failover32" 'uci -q delete network.'
require "$failover32" 'ensure_invariants()'
require "$failover32" 'ensure_invariants wan_sfp 9'
require "$failover32" 'if ! uci -q get network.wan_sfp >/dev/null 2>&1; then'
require "$failover32" 'iface_in_any_zone'
require "$failover32" 'find_wan_zone'
require "$failover32" "uci -q set network.4_1.metric='200'"

# GPIO root cause of the "modem gone after reboot" regression: 5G1 must
# default to powered-on, matching the DTS gpio-export,output = <1>, or
# gpio_switch (START=94) cuts Vbat a few seconds into every boot.
require "$gpioboard" 'ucidef_add_gpio_switch "5g1" "Power 5G1 modem slot" "5g1" "1"'
require "$gpioboard" 'ucidef_add_gpio_switch "5g2" "Power 5G2 modem slot" "5g2" "0"'
require "$gpioboard" 'ucidef_add_gpio_switch "sim1" "SIM1 slot active (off = SIM2 slot)" "sim1" "1"'

# Upgrades carry the stale persisted gpio_switch value=0; 99-autostart must
# migrate it before S94gpio_switch runs, guarded by a once-marker so an
# operator who powers 5G1 off later is never overridden.
require "$autostart" 'zbt_gpio_default'
require "$autostart" 'system.$gsec.zbt_gpio_default=1'
require "$autostart" "system.\$gsec.value=1"
# The section must be matched by ID or gpio_pin: the name label is prose and
# comparing it to the slot name turned the first v25.12.021 migration into a
# silent no-op ("modem unpowered after upgrade").
require "$autostart" '[ "$gsec" = "5g1" ]'
require "$autostart" 'system.$gsec.gpio_pin'
forbid "$autostart" 'system.$gsec.name'
# uci stores the value after "=" verbatim: no embedded shell quotes.
forbid "$autostart" "zbt_gpio_default='1'"
forbid "$autostart" "value='1'"

# The permanent TTL-64 nft rule is seeded only when absent, so an operator's
# hand-raised 65 survives a reflash.
require "$speedmode" 'if [ ! -e /etc/nftables.d/99-tether-ttl.nft ]; then'
require "$speedmode" 'oifname "wwan0" ip ttl set 64'

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
# The plugin ships disabled, so the probe must also keep the permanent
# 99-tether-ttl.nft rule in step — otherwise a module that still NATs is
# policed with the seeded 64 and the connection dies seconds after a client
# connects. Only 64<->65 transitions are firmware-managed; anything else is
# operator-owned.
require_exec "$natprobe"
require "$natprobe" 'TTL_FOR_NAT=${TTL_FOR_NAT:-65}'
require "$natprobe" 'TTL_FOR_TRANSPARENT=${TTL_FOR_TRANSPARENT:-64}'
require "$natprobe" '192.0.0. 192.168.225. 10.168.'
require "$natprobe" 'zbt_auto_ttl'
require "$natprobe" 'apply_nft_ttl'
require "$natprobe" '99-tether-ttl.nft'
require "$natprobe" 'reason=hand-edited'
require "$natprobe" 'ip6 hoplimit set'
require "$natprobe" 'firewall reload'
require "$ttlhook" 'zbt-modem-nat-probe --apply'

# Cellular QMI carries no DHCPv6-PD, so a stock ULA announced on the LAN
# breaks dual-stack clients (AAAA answers, no v6 path). The no-ULA default
# must be once-per-flash, marker-guarded.
require "$noula" 'uci -q delete network.globals.ula_prefix'
require "$noula" 'zbt_no_ula'
require "$noula" 'board_name'
require "$ttlhook" 'zbt-modem-nat-probe --apply'

absent "$bf/etc/hotplug.d/usb/30-zbt-qmodem-autoenable"
absent "$bf/etc/hotplug.d/usb/29-zbt-modem-factory-reset"
absent "$bf/etc/hotplug.d/net/00-zbt-qmi-rawip"
absent "$bf/etc/hotplug.d/net/10-zbt-modem-led"
absent "$bf/etc/hotplug.d/iface/30-zbt-status-led"
absent "$bf/etc/hotplug.d/iface/30-zbt-wwan-dns"

# Renumbered uci-defaults: the old file must be gone or both ship.
absent "$bf/etc/uci-defaults/10-zbt-apk-feeds"
absent "$bf/etc/uci-defaults/15-zbt-modem-factory-reset-flag"
absent "$bf/etc/uci-defaults/30-zbt-z8803be-wan-failover"
absent "$bf/etc/uci-defaults/32-zbt-z8803be-wan-speed-mode"
absent "$bf/etc/uci-defaults/35-zbt-qmodem-dns-suppress"
absent "$bf/etc/uci-defaults/38-zbt-throughput-tuning"
absent "$bf/etc/uci-defaults/40-zbt-qmodem-watchdog-enable"
absent "$bf/etc/uci-defaults/44-zbt-qmodem-watchdog-disable"
absent "$bf/etc/uci-defaults/45-zbt-qmodem-monitor-enable"
absent "$bf/etc/uci-defaults/46-zbt-qmodem-monitor-patch"
absent "$bf/etc/uci-defaults/47-zbt-persistent-app-stats"
absent "$bf/etc/uci-defaults/47-zbt-qmodem-soft-reboot-patch"
absent "$bf/etc/uci-defaults/50-zbt-sms-tool-compat"
absent "$bf/etc/uci-defaults/60-zbt-leds-cleanup"
absent "$bf/etc/uci-defaults/70-zbt-z8803be-wifi"
absent "$bf/etc/uci-defaults/76-zbt-z8803be-admin-password"
absent "$bf/etc/uci-defaults/80-zbt-z8803be-dns-cache"
absent "$bf/etc/uci-defaults/84-zbt-luci-js-compat"
absent "$bf/etc/uci-defaults/99-zbt-z8803be-services"
absent "$bf/etc/uci-defaults/99a-zbt-youtubeunblock-disable"

# Anything new outside an allowlisted directory must be listed here too, or it
# silently never reaches a fresh upstream checkout.
for f in "$natprobe" "$ttlhook" "$rndis"; do
	require "$replay" "${f#$root/}"
done

for file in "$auto" "$watchdog" "$watchdog_init" "$rndis" "$ledhot" \
	"$slots" "$mlorepair" "$qmodem_dial" "$ttl" "$failover32" \
	"$speedmode" "$noula" "$autostart" "$gpioboard" "$natprobe" \
	"$ttlhook"; do
	sh -n "$file"
done

printf 'zbt firmware static checks passed\n'
