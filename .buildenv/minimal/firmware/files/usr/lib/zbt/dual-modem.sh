#!/bin/sh
# Mapping: pinned DTS power/LED GPIOs + the two-modem USB boot log.
# Never infer a slot from wwanN/ttyUSBN enumeration order or '*-1'.
zbt_slot() {
	case "$1" in
		1|4_1|4-1) ZBT_SECTION=4_1; ZBT_USB=4-1; ZBT_POWER=5g1; ZBT_LED=blue:mobile-1 ;;
		2|2_1|2-1) ZBT_SECTION=2_1; ZBT_USB=2-1; ZBT_POWER=5g2; ZBT_LED=blue:mobile-2 ;;
		*) return 1 ;;
	esac
}
# Used only for missing/new configuration, never to force a later choice.
zbt_default_dial() {
	case "$1" in 4_1) echo 1 ;; 2_1) echo 0 ;; *) return 1 ;; esac
}
zbt_netdev() {
	local entry found='' count=0
	zbt_slot "$1" || return 1
	for entry in "${ZBT_SYSFS:-/sys}/bus/usb/devices/$ZBT_USB"/*/net/*; do
		[ -d "$entry" ] || continue
		found=${entry##*/}; count=$((count + 1))
	done
	[ "$count" = 1 ] || return 1
	printf '%s\n' "$found"
}
zbt_port_matches() {
	local device_path port_path
	zbt_slot "$1" || return 1
	device_path=$(readlink -f "${ZBT_SYSFS:-/sys}/bus/usb/devices/$ZBT_USB") || return 1
	port_path=$(readlink -f "${ZBT_SYSFS:-/sys}/class/tty/${2##*/}/device") || return 1
	[ -d "$device_path" ] && [ -d "$port_path" ] || return 1
	case "$port_path" in "$device_path"/*) return 0 ;; *) return 1 ;; esac
}
# Preserve QModem/Quectel's modem/network-profile auto selection. Manual APNs
# remain untouched. The only automatic exception is documented below.
zbt_apn_mode() {
	case "$1" in ''|auto) printf '%s\n' auto ;; *) printf '%s\n' manual ;; esac
}

# Return an IMSI only when the selected modem gives a clean numeric identity.
# It is used in memory for carrier selection and is never written to logs/UCI.
zbt_modem_imsi() {
	local token
	for token in $(at "$1" 'AT+CIMI' 2>/dev/null | tr -d '\r'); do
		case "$token" in *[!0-9]*) continue ;; esac
		[ "${#token}" -ge 14 ] && [ "${#token}" -le 16 ] || continue
		printf '%s\n' "$token"
		return 0
	done
	return 1
}

# Keep normal modem/profile negotiation for auto APNs, except for a direct
# AT&T US SIM (MCC/MNC 310/410), whose generic modem profile can select an
# unusable APN. A configured APN always wins, including an MVNO override.
zbt_effective_apn() {
	local configured="$1" imsi
	if [ "$(zbt_apn_mode "$configured")" = manual ]; then
		printf '%s\n' "$configured"
		return 0
	fi
	imsi=$(zbt_modem_imsi "$2") || return 0
	case "$imsi" in 310410*) printf '%s\n' broadband ;; esac
}

# Hash only this slot's dial settings. Changing modem2's APN must not
# restart modem1; updating temperatures/counters must not restart either.
zbt_dial_fingerprint() {
	local key
	for key in path at_port network alias dial_tool pdp_type metric use_ubus \
		force_set_apn pdp_index suggest_pdp_index ra_master extend_prefix \
		en_bridge bridge_port network_bridge do_not_add_dns dns_list donot_nat \
		apn apn2 username username2 password password2 auth auth2 pincode pincode2; do
		printf '%s=' "$key"
		uci -q get "qmodem.$1.$key" || true
		printf '\n'
	done | sha256sum | cut -d' ' -f1
}
