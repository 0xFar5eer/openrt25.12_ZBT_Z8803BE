#!/bin/sh
# Read-only post-flash checks. No AT writes, resets, reloads, UCI commits,
# full modem/SIM config dumps or account tokens.
. /usr/lib/zbt/dual-modem.sh
printf '%s\n' 'Runtime diagnostics (review/redact before sharing)'
printf 'kernel=%s\n' "$(uname -r)"
printf 'board=%s\n' "$(cat /tmp/sysinfo/board_name 2>/dev/null)"
printf 'flavor=%s\n' "$(cat /etc/zbt-build-flavor 2>/dev/null)"
for section in 4_1 2_1; do
	zbt_slot "$section"
	device=$(zbt_netdev "$section") || device=''
	port=$(uci -q get "qmodem.$section.at_port")
	printf '\nmodem=%s usb=%s device=%s power=%s led=%s\n' "$section" "$ZBT_USB" "${device:-absent}" "$ZBT_POWER" "$ZBT_LED"
	printf 'power_value=%s at_port=%s port_matches=%s\n' "$(cat "/sys/class/gpio/$ZBT_POWER/value" 2>/dev/null)" "$port" "$(zbt_port_matches "$section" "$port" && echo yes || echo no)"
	for key in display_name alias state enable_dial pdp_type metric monitor_enabled; do
		printf '%s=%s\n' "$key" "$(uci -q get "qmodem.$section.$key")"
	done
	printf 'apn_mode=%s secondary_apn_mode=%s\n' "$(zbt_apn_mode "$(uci -q get "qmodem.$section.apn")")" "$(zbt_apn_mode "$(uci -q get "qmodem.$section.apn2")")"
	printf 'proto=%s network_metric=%s\n' \
		"$(uci -q get "network.$section.proto")" \
		"$(uci -q get "network.$section.metric")"
	/etc/init.d/qmodem_network modem_status "$section" 2>/dev/null
	if [ -n "$device" ]; then
		ip addr show dev "$device" scope global 2>/dev/null
	fi
done
printf '\n%s\n' 'Independent modem TTL policy (read-only; auto uses a passive 64/65 heuristic)'
for section in 4_1 2_1; do
	printf 'modem=%s ttl_enabled=%s ttl_mode=%s custom_ttl=%s\n' "$section" \
		"$(uci -q get "qmodem_ttl.$section.enable")" \
		"$(uci -q get "qmodem_ttl.$section.mode")" \
		"$(uci -q get "qmodem_ttl.$section.ttl")"
done
nft list chain inet fw4 zbt_qmodem_ttl_postrouting 2>/dev/null || true
printf '\n%s\n' 'Physical modem LED status (read-only)'
/usr/sbin/zbt-modem-led-poller status
/etc/init.d/zbt-modem-leds status 2>/dev/null || true
printf '%s\n' 'Factory status LED owner and channels'
/etc/init.d/zbt-leds status 2>/dev/null || true
for lamp in red:status green:wan blue:power; do
	printf 'led=%s trigger=%s brightness=%s\n' "$lamp" \
		"$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "/sys/class/leds/$lamp/trigger" 2>/dev/null)" \
		"$(cat "/sys/class/leds/$lamp/brightness" 2>/dev/null)"
done
printf '\n%s\n' 'Ethernet jack LED controls (read-only; amber/green metadata may mean orange)'
for lamp in mt7530-0:00:green:lan mt7530-0:02:green:lan mt7530-0:03:green:lan mdio-bus:0f:amber:wan; do
	printf 'led=%s' "$lamp"
	if [ ! -d "/sys/class/leds/$lamp" ]; then
		printf ' missing\n'
		continue
	fi
	for attribute in trigger brightness device_name link rx tx offloaded; do
		[ -r "/sys/class/leds/$lamp/$attribute" ] || continue
		printf ' %s=%s' "$attribute" "$(cat "/sys/class/leds/$lamp/$attribute")"
	done
	printf '\n'
done
printf '\n%s\n' 'Routing (no mwan3 or speed-test watchdog in this build)'
for interface in wan_sfp wan_sfp6 wan wan6 4_1 2_1; do
	uci -q get "network.$interface" >/dev/null 2>&1 || continue
	printf 'network.%s metric=%s proto=%s device=%s\n' "$interface" \
		"$(uci -q get "network.$interface.metric")" \
		"$(uci -q get "network.$interface.proto")" \
		"$(uci -q get "network.$interface.device")"
done
ip -4 route show default
printf '\n%s\n' 'Minimal package exclusions and service health'
for package in luci-app-mlo uhttpd uhttpd-mod-ubus; do
	apk info -e "$package" >/dev/null 2>&1 && printf '%s=installed\n' "$package" || printf '%s=missing\n' "$package"
done
for service in uhttpd qmodem_network; do
	printf '%s=' "$service"
	"/etc/init.d/$service" status 2>/dev/null || true
done
printf 'luci_http_status='
curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1/cgi-bin/luci/
printf 'luci_https_status='
curl -ksS --max-time 5 -o /dev/null -w '%{http_code}\n' https://127.0.0.1/cgi-bin/luci/
printf '\n%s\n' 'MLO representation and LAN bridge state (SSID/MAC output may need redaction)'
for section in $(uci -q show wireless | sed -nE 's/^wireless\.([^.]+)=wifi-iface$/\1/p'); do
	[ "$(uci -q get "wireless.${section}.mlo")" = 1 ] || continue
	set -- $(uci -q get "wireless.${section}.device")
	printf 'section=%s radios=%s device_count=%s network=%s security=%s disabled=%s\n' \
		"$section" "$*" "$#" "$(uci -q get "wireless.${section}.network")" \
		"$(uci -q get "wireless.${section}.encryption")" "$(uci -q get "wireless.${section}.disabled")"
done
iw dev 2>/dev/null || true
bridge link show 2>/dev/null || true
ubus list 'hostapd.*' 2>/dev/null || true
logread 2>/dev/null | grep -Ei 'mld|mlo|AP-ENABLED|too many open files|not supported' | tail -n 120
printf '%s\n' 'mac80211 peer-link objects (two or more link-* entries are required for an active multi-link peer)'
find /sys/kernel/debug/ieee80211 -type d -path '*/stations/*/link-*' -print 2>/dev/null || true
printf '\n%s\n' 'Compare AT registration/band readbacks separately in the selected modem AT Debug tab; do not publish SIM identifiers.'
