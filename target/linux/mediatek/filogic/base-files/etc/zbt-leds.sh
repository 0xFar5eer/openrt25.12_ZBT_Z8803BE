#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ZBT-Z8803BE chassis LED state-machine helper.
#
# The front-panel "SYS" indicator is physically three discrete
# single-colour LEDs (red:status / green:wan / blue:power) sharing
# the same housing. Their visible mix communicates router state to
# the user. This script is the single source of truth for that mix:
# every other LED-touching code path on this board (init script,
# hotplug iface, future fault watchdogs) calls in here with a state
# name, and the state -> trigger/colour mapping lives in exactly one
# place so changes to the colour scheme don't have to chase a dozen
# call sites.
#
# State semantics (matches the user-facing spec):
#
#   boot      Orange blinking (red+green together, fast).
#             "Router is up, services are starting, no internet
#             determination has happened yet." Set by the early
#             init script before networks come up. Cleared by the
#             first hotplug iface event that re-evaluates state.
#
#   online    Green blinking (slow heartbeat-style: mostly on with
#             a brief off-pulse). "Default route exists; the
#             router is reaching the internet through wired WAN,
#             cellular WWAN, or both." Tx/rx isn't directly
#             rendered because the user wanted a constant blink as
#             a liveness indicator rather than an activity meter.
#
#   offline   Blue solid. "Router has power and finished booting
#             but has no default route." Distinct from boot
#             (different colour) and from fault (different colour
#             *and* not flashing).
#
#   fault    Red solid. "Something is broken at a level beyond
#             'no internet' — modem detection failed, watchdog
#             tripped, etc." Reserved for explicit calls; we don't
#             auto-trigger this from connectivity loss.
#
#   off       All three off. Available for low-power / quiet modes
#             and for tests; not used by the default state machine.
#
# Implementation notes:
#
#   * Triggers and brightness writes are done idempotently: writing
#     the same value to a sysfs node is a no-op, so this script can
#     be called repeatedly without flicker.
#
#   * Every sysfs write is wrapped in 2>/dev/null. Sysfs nodes can
#     legitimately be missing (rescue boot, kernel without one of
#     the trigger drivers compiled in) and the right answer is
#     "don't crash the LED state machine" rather than "exit early
#     and leave the chassis in an indeterminate mix".
#
#   * Trigger ordering matters: writing delay_on/delay_off only
#     takes effect once trigger=timer is set, because non-timer
#     triggers don't expose those nodes. We write trigger first,
#     then poll briefly for delay_on to appear.

LED_RED="/sys/class/leds/red:status"
LED_GREEN="/sys/class/leds/green:wan"
LED_BLUE="/sys/class/leds/blue:power"

# Per-slot modem LEDs. The DTS exposes the front-panel cellular
# indicators as /sys/class/leds/blue:mobile-1 and blue:mobile-2.
zbt_slot_led_path() {
	local slot="$1"
	case "$slot" in
		1)
			echo /sys/class/leds/blue:mobile-1
			;;
		2)
			echo /sys/class/leds/blue:mobile-2
			;;
	esac
}

# Set the named LED to "trigger=timer" with the given on/off
# durations in milliseconds. The kernel exposes delay_on/delay_off
# only once trigger=timer is active, hence the trigger write must
# happen first; we then loop briefly to give the kernel a moment to
# create the new sysfs nodes before writing the durations. The cap
# at 20 iterations (~200 ms total) keeps the script bounded — past
# that the kernel either doesn't have ledtrig-timer compiled in or
# the LED driver itself doesn't implement blink_set, neither of
# which we can recover from at runtime.
zbt_led_blink() {
	local led="$1" on_ms="$2" off_ms="$3"
	[ -d "$led" ] || return 0
	echo "timer" > "$led/trigger" 2>/dev/null
	local i=0
	while [ ! -e "$led/delay_on" ] && [ "$i" -lt 20 ]; do
		i=$((i + 1))
		# Tight retry loop; usleep avoids the full-second
		# minimum of busybox sleep(1).
		usleep 10000 2>/dev/null || break
	done
	[ -e "$led/delay_on" ] || return 0
	echo "$on_ms" > "$led/delay_on" 2>/dev/null
	echo "$off_ms" > "$led/delay_off" 2>/dev/null
}

# Drive the named LED to a hard-on state via trigger=default-on.
# We use the dedicated trigger rather than just writing brightness=
# 255, because brightness writes get overridden the next time
# /etc/init.d/led restarts and reads /etc/config/system. Trigger
# writes are persistent until something else overwrites them.
zbt_led_solid() {
	local led="$1"
	[ -d "$led" ] || return 0
	echo "default-on" > "$led/trigger" 2>/dev/null
}

# Drive the named LED to off (trigger=none, brightness=0 as belt-
# and-suspenders against drivers that don't honour trigger=none
# atomically — this happens on a couple of mediatek SoC boards).
zbt_led_off() {
	local led="$1"
	[ -d "$led" ] || return 0
	echo "none" > "$led/trigger" 2>/dev/null
	echo 0 > "$led/brightness" 2>/dev/null
}

state="${1:-}"
case "$state" in
	boot)
		# Fast 200/200 blink: "I'm busy" cadence, distinct
		# from the slower "online" cadence.
		zbt_led_blink "$LED_RED"   200 200
		zbt_led_blink "$LED_GREEN" 200 200
		zbt_led_off   "$LED_BLUE"
		;;
	online)
		# 800/100: mostly-on with a brief off-pulse, reads
		# clearly as "blinking green" while showing a strong
		# steady presence so the user can tell at a glance the
		# router is healthy.
		zbt_led_off   "$LED_RED"
		zbt_led_blink "$LED_GREEN" 800 100
		zbt_led_off   "$LED_BLUE"
		;;
	offline)
		# Blue solid. Different from boot (colour) and fault
		# (colour + not flashing) so a user landing in front of
		# the router can disambiguate at a glance.
		zbt_led_off   "$LED_RED"
		zbt_led_off   "$LED_GREEN"
		zbt_led_solid "$LED_BLUE"
		;;
	fault)
		# Red solid. Reserved for explicit fault triggers;
		# never set automatically from connectivity loss
		# (that's the offline state).
		zbt_led_solid "$LED_RED"
		zbt_led_off   "$LED_GREEN"
		zbt_led_off   "$LED_BLUE"
		;;
	off)
		zbt_led_off "$LED_RED"
		zbt_led_off "$LED_GREEN"
		zbt_led_off "$LED_BLUE"
		;;
	slot)
		# Per-modem-slot LED state machine for the front-panel
		# blue:mobile-1 / blue:mobile-2 indicators. The user-facing spec is:
		#
		#   modem powered, no SIM / no tower    -> red solid
		#   LTE network connected               -> orange blink
		#                                          (with activity)
		#   5G NR network connected             -> blue blink
		#                                          (with activity)
		#
		# Hardware reality: the current Z8803BE DTS declares only
		# one GPIO per slot (single-colour LED, very likely blue
		# based on the matching pattern in sibling Zbtlink boards
		# such as zbt-z8102ax-v2). Until additional colour pins
		# are mapped, we approximate the four user states with
		# distinct blink cadences on the one available LED:
		#
		#   off       -> trigger=none, brightness=0
		#                ("modem unpowered / not present")
		#   no_signal -> trigger=default-on, solid
		#                ("powered but unregistered, closest
		#                 visual analog to 'red solid'")
		#   lte       -> trigger=timer 1500/1500, slow blink
		#                ("LTE connected, calm cadence")
		#   nr5g      -> trigger=timer 200/200, fast blink
		#                ("5G NR active, energetic cadence")
		#   wwan      -> trigger=netdev tx/rx on wwanN, link-driven
		#                blink that follows actual modem traffic
		#                (used when caller wants the "with
		#                 activity" qualifier rather than a fixed
		#                 cadence)
		#
		# Once the additional colour GPIOs are mapped (see TODOs
		# in the DTS) this block extends naturally: replace each
		# zbt_led_* call with multi-LED orchestration without
		# changing the public state names.
		slot="$2"
		substate="$3"
		led=$(zbt_slot_led_path "$slot")
		[ -n "$led" ] || { logger -t zbt-leds "slot $slot: no LED node"; exit 0; }
		case "$substate" in
			off)
				zbt_led_off "$led"
				;;
			no_signal)
				zbt_led_solid "$led"
				;;
			lte)
				zbt_led_blink "$led" 1500 1500
				;;
			nr5g)
				zbt_led_blink "$led" 200 200
				;;
			wwan)
				# netdev trigger with link/tx/rx so the LED
				# tracks actual modem traffic. Caller passes
				# the netdev name as $4 (e.g. "wwan0").
				dev="$4"
				[ -n "$dev" ] || { logger -t zbt-leds "slot $slot: wwan state needs device arg"; exit 1; }
				echo netdev > "$led/trigger" 2>/dev/null
				echo "$dev"  > "$led/device_name" 2>/dev/null
				echo 1 > "$led/link" 2>/dev/null
				echo 1 > "$led/tx"   2>/dev/null
				echo 1 > "$led/rx"   2>/dev/null
				;;
			*)
				logger -t zbt-leds "slot $slot: unknown substate $substate"
				exit 1
				;;
		esac
		;;
	"")
		# Print usage on bare invocation. Useful when sshing in
		# and forgetting which states exist.
		cat <<USAGE
usage: $0 <state> [args]

SYS LED states (apply to red:status / green:wan / blue:power):
  boot                  orange blink (loading, set by /etc/init.d/zbt-leds)
  online                green blink (default route present)
  offline               blue solid (no default route)
  fault                 red solid (explicit fault)
  off                   all SYS LEDs off

Per-slot modem LED states (apply to blue:mobile-1 / blue:mobile-2):
  slot <1|2> off                     LED off (modem absent / unpowered)
  slot <1|2> no_signal               solid (modem present but not registered)
  slot <1|2> lte                     slow blink (LTE network connected)
  slot <1|2> nr5g                    fast blink (5G NR active)
  slot <1|2> wwan <netdev>           netdev trigger (link/tx/rx on netdev)
USAGE
		exit 1
		;;
	*)
		logger -t zbt-leds "unknown state: $state"
		exit 1
		;;
esac

exit 0
