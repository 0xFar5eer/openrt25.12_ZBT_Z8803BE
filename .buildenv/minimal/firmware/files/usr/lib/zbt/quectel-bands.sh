#!/bin/sh
# QModem extension: query failures are not empty masks; writes require readback.
. /usr/lib/zbt/dual-modem.sh
zbt_band_key() {
	case "$1" in
		UMTS) band_key=gw_band; capability=wcdma_band ;;
		LTE) band_key=lte_band; capability=lte_band ;;
		NR) band_key=nr5g_band; capability=sa_band ;;
		NR_NSA) band_key=nsa_nr5g_band; capability=nsa_band ;;
		*) return 1 ;;
	esac
}
zbt_band_ok() {
	printf '%s\n' "$1" | awk '
		{ gsub(/\r/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
		/^ERROR$|^\+CM[ES] ERROR:|^NO CARRIER$/ { failed=1 }
		/^OK$/ { ok=1 }
		END { exit (!ok || failed) }'
}
zbt_band_values() {
	local values
	# Do not accept a truncated reply, or join duplicate response lines into
	# invented bands (e.g. two replies containing 41 used to become 4141).
	zbt_band_ok "$1" || return 1
	values=$(printf '%s\n' "$1" | awk -v key="$2" '
		{ gsub(/\r/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
		/^OK$/ { if (seen) complete=1; ended=1 }
		/^\+QNWPREFCFG:/ {
			prefix=$0; sub(/,.*/, "", prefix); gsub(/[[:space:]"]/, "", prefix)
			if (prefix != "+QNWPREFCFG:" key) next
			if (ended) bad=1
			value=$0; sub(/^[^,]*,[[:space:]]*/, "", value)
			if (value ~ /^".*"$/) value=substr(value, 2, length(value)-2)
			sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
			gsub(/[[:space:]]*:[[:space:]]*/, ":", value)
			if (value !~ /^[1-9][0-9]*(:[1-9][0-9]*)*$/) { bad=1; next }
			for (band in current) delete current[band]
			count=split(value, parts, ":")
			for (i=1; i<=count; i++) current[parts[i]]=1
			if (seen) {
				for (band in current) if (!(band in prior)) bad=1
				for (band in prior) if (!(band in current)) bad=1
			}
			for (band in prior) delete prior[band]
			for (band in current) prior[band]=1
			previous=value; seen=1
		}
		END { if (bad || !complete) exit 1; print previous }') || return 1
	printf '%s\n' "$values" | tr ':' '\n' | sort -nu
}
zbt_band_diagnostic() {
	# Only band replies and AT status; never expose unrelated SIM/identity URCs.
	printf '%s\n' "$1" | awk '
		{ gsub(/\r/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
		/^\+QNWPREFCFG:|^OK$|^ERROR$|^\+CM[ES] ERROR:|^NO CARRIER$/ {
			if (++lines <= 8) print substr($0, 1, 1024)
		}'
}
zbt_read_band() {
	# Sets caller-local response/values/read_error. Never probes the other port.
	response=''; values=''; read_error=''
	if ! zbt_port_matches "$config_section" "$at_port"; then
		read_error='AT port does not belong to this modem, or the modem is absent.'
		return 1
	fi
	if ! response=$(at "$at_port" "AT+QNWPREFCFG=\"$band_key\""); then
		read_error='Band query transport failed or timed out. Retry reading this modem.'
		return 1
	fi
	if ! values=$(zbt_band_values "$response" "$band_key"); then
		read_error='No complete, unambiguous band list was returned. Unknown is not all bands off. See the band query reply below.'
		return 1
	fi
}
zbt_get_lockband_nr() {
	local at_port="$1" class available response values band band_key capability read_error
	for class in UMTS LTE NR NR_NSA; do
		zbt_band_key "$class"
		available=$(uci -q get "qmodem.$config_section.$capability" | tr '/' ' ')
		zbt_read_band || values=''
		json_add_object "$class"
		if [ -n "$read_error" ]; then
			json_add_string read_state unknown
			json_add_string read_error "$read_error"
		else
			json_add_string read_state verified
		fi
		json_add_string read_command "AT+QNWPREFCFG=\"$band_key\""
		json_add_string read_response "$(zbt_band_diagnostic "$response")"
		json_add_array available_band
		for band in $available; do
			case "$band" in ''|*[!0-9]*) continue ;; esac
			add_avalible_band_entry "$band" "${class}_$band"
		done
		json_close_array
		json_add_array lock_band
		for band in $values; do json_add_string "" "$band"; done
		json_close_array
		json_close_object
	done
}
zbt_set_lockband_nr() {
	local selected response actual band available band_key capability values read_error attempt
	res='ERROR: Invalid band selection'
	zbt_band_key "$band_class" || return 0
	printf '%s\n' "$lock_band" | grep -Eq '^[1-9][0-9]*(,[1-9][0-9]*)*$' || return 0
	zbt_port_matches "$config_section" "$at_port" || { res='ERROR: AT port does not belong to this modem'; return 0; }
	available=" $(uci -q get "qmodem.$config_section.$capability" | tr '/' ' ') "
	selected=$(printf '%s' "$lock_band" | tr ',' '\n' | sort -nu)
	for band in $selected; do
		case "$available" in *" $band "*) ;; *) res='ERROR: Band not in this modem capability list'; return 0 ;; esac
	done
	lock_band=$(printf '%s\n' "$selected" | tr '\n' ':' | sed 's/:$//')
	# One persistent write only. An uncertain response must never cause an
	# automatic rewrite, factory reset, MBN change, or peer modem restart.
	if ! response=$(at "$at_port" "AT+QNWPREFCFG=\"$band_key\",$lock_band") ||
	   ! zbt_band_ok "$response"; then
		res="ERROR: Modem rejected band command or did not acknowledge it; no success reported. Reply: $(zbt_band_diagnostic "$response")"
		return 0
	fi
	for attempt in 1 2 3; do
		[ "$attempt" = 1 ] || sleep 1
		if zbt_read_band && [ "$values" = "$selected" ]; then
			res='OK (readback verified)'
			return 0
		fi
	done
	if [ -n "$read_error" ]; then
		res="ERROR: Band command acknowledged, but $band_key readback is unknown. Requested: $lock_band. $read_error Reply: $(zbt_band_diagnostic "$response")"
	else
		actual=$(printf '%s\n' "$values" | tr '\n' ':' | sed 's/:$//')
		res="ERROR: Band readback differs for $band_key. Requested: $lock_band; modem reports: $actual. The current modem values will be reloaded; no reset or retry write was performed."
	fi
}
