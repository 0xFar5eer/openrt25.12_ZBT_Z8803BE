#!/bin/sh
# Only LED-class attributes are written here: never modem power, SIM or AT.
. /usr/lib/zbt/dual-modem.sh

zbt_led_detect() {
	zbt_slot "$1" || return 1
	ZBT_LED_PATH="${ZBT_SYSFS:-/sys}/class/leds/$ZBT_LED"
	ZBT_LED_POWER=$(cat "${ZBT_SYSFS:-/sys}/class/gpio/$ZBT_POWER/value" 2>/dev/null) || ZBT_LED_POWER=unknown
	ZBT_LED_DEVICE=$(zbt_netdev "$1") || ZBT_LED_DEVICE=''
	ZBT_LED_STATE=off
	# An enumerated modem is evidence of power even if a named GPIO cannot
	# be read. Do not make a working modem's LED depend on that read alone.
	if [ -d "${ZBT_SYSFS:-/sys}/bus/usb/devices/$ZBT_USB" ] || [ "$ZBT_LED_POWER" = 1 ]; then
		ZBT_LED_STATE=waiting
		if [ -n "$ZBT_LED_DEVICE" ] &&
			ip addr show dev "$ZBT_LED_DEVICE" scope global 2>/dev/null | grep -qE 'inet6? '; then
			ZBT_LED_STATE=data
		fi
	fi
}

zbt_led_read() { cat "$ZBT_LED_PATH/$1" 2>/dev/null; }
zbt_led_write() {
	# Refuse to create an attribute if a trigger did not expose it.
	[ -e "$ZBT_LED_PATH/$1" ] || return 1
	printf '%s\n' "$2" > "$ZBT_LED_PATH/$1"
}
zbt_led_trigger() { zbt_led_read trigger | sed -n 's/.*\[\([^]]*\)\].*/\1/p'; }
zbt_led_supports() {
	zbt_led_read trigger | tr '[] ' '\n' | grep -qx "$1"
}

# The automatic cellular indicator is the safe default. If an administrator
# adds this LED to LuCI's System -> LED Configuration, that explicit system
# rule owns it instead. This makes both 5G LEDs genuinely user-configurable
# without two services repeatedly overwriting the same sysfs attributes.
zbt_led_name_user_managed() {
	local wanted="$1"
	local section
	for section in $(uci -q show system 2>/dev/null | sed -n 's/^system\.\([^.=]*\)=led$/\1/p'); do
		[ "$(uci -q get "system.$section.sysfs" 2>/dev/null)" = "$wanted" ] || continue
		# Seeded inventory rows use trigger=none as an automatic sentinel.
		# Selecting another trigger in LuCI turns the row into a user rule.
		if [ "$(uci -q get "system.$section.zbt_automatic" 2>/dev/null)" = 1 ] &&
			[ "$(uci -q get "system.$section.trigger" 2>/dev/null)" = none ]; then
			continue
		fi
		return 0
	done
	return 1
}

zbt_led_user_managed() { zbt_led_name_user_managed "$ZBT_LED"; }

zbt_led_apply_fallback() {
	local trigger maximum carrier
	[ -d "$ZBT_LED_PATH" ] || return 1
	trigger=$(zbt_led_trigger)
	carrier=$(cat "${ZBT_SYSFS:-/sys}/class/net/$ZBT_LED_DEVICE/carrier" 2>/dev/null)
	maximum=$(zbt_led_read max_brightness)
	case "$maximum" in ''|*[!0-9]*|0) maximum=1 ;; esac
	case "$ZBT_LED_STATE:$trigger" in
		off:none) [ "$(zbt_led_read brightness)" = 0 ] && return 0 ;;
		waiting:timer)
			[ "$(zbt_led_read delay_on)" = 1000 ] && [ "$(zbt_led_read delay_off)" = 1000 ] && return 0 ;;
		data:netdev)
			[ "$carrier" = 1 ] && [ "$(zbt_led_read device_name)" = "$ZBT_LED_DEVICE" ] &&
				[ "$(zbt_led_read link)" = 1 ] && [ "$(zbt_led_read rx)" = 1 ] &&
				[ "$(zbt_led_read tx)" = 1 ] && return 0 ;;
	esac
	zbt_led_write trigger none || return 1
	if [ "$ZBT_LED_STATE" = off ]; then
		zbt_led_write brightness 0
		return $?
	fi
	# Restore brightness explicitly, including after the generic LED service
	# cleared it. Never assume a successfully selected trigger is configured.
	zbt_led_write brightness "$maximum" || return 1
	if [ "$ZBT_LED_STATE" = data ] && zbt_led_supports netdev; then
		if [ "$carrier" = 1 ] && zbt_led_write trigger netdev &&
			zbt_led_write device_name "$ZBT_LED_DEVICE" &&
			zbt_led_write link 1 && zbt_led_write rx 1 && zbt_led_write tx 1; then
			return 0
		fi
	elif [ "$ZBT_LED_STATE" = waiting ] && zbt_led_supports timer; then
		if zbt_led_write trigger timer && zbt_led_write delay_on 1000 && zbt_led_write delay_off 1000; then
			return 0
		fi
	fi
	# Unsupported trigger / unreliable WWAN carrier: visible steady fallback,
	# not an extinguished LED. Status reports this instead of claiming activity.
	zbt_led_write trigger none && zbt_led_write brightness "$maximum"
}

zbt_led_apply() {
	local helper slot substate
	[ -d "$ZBT_LED_PATH" ] || return 1
	zbt_led_user_managed && return 0

	case "$ZBT_SECTION" in
		4_1) slot=1 ;;
		2_1) slot=2 ;;
		*) return 1 ;;
	esac
	case "$ZBT_LED_STATE" in
		off) substate=off ;;
		waiting) substate=no_signal ;;
		data) substate=wwan ;;
		*) return 1 ;;
	esac

	# Far5eer v25.12.021 drives these active-low GPIO LEDs through this
	# helper. Use that proven path in production; retain the bounded direct
	# writer only as a rescue fallback if a damaged image lacks the helper.
	helper=${ZBT_LED_HELPER:-/etc/zbt-leds.sh}
	if [ -x "$helper" ]; then
		if [ "$substate" = wwan ]; then
			[ -n "$ZBT_LED_DEVICE" ] || return 1
			"$helper" slot "$slot" wwan "$ZBT_LED_DEVICE"
		else
			"$helper" slot "$slot" "$substate"
		fi
		return $?
	fi
	zbt_led_apply_fallback
}
