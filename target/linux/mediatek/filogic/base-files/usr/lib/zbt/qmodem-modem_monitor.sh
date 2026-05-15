#!/bin/sh
. /lib/functions.sh
. /usr/share/qmodem/modem_util.sh
MONITOR_COOLDOWN_FILE="/tmp/zbt-qmodem-monitor-action.lock"
MONITOR_COOLDOWN_HELPER="/usr/sbin/zbt-modem-monitor-cooldown"
MONITOR_COOLDOWN_S_DEFAULT=300
MONITOR_COOLDOWN_S=$MONITOR_COOLDOWN_S_DEFAULT
# Envs
# Modem_ID
# Modem_ID=$1
# Method=$2
# Interval=$3
# Threshold=$4
# params1=$5
# params2=$6
parse_args(){
    while [ $# -gt 0 ]; do
        case $1 in
            --modem_id)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Modem_ID=$2
                shift 2
                ;;
            --method)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Method=$2
                shift 2
                ;;
            --interval)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Interval=$2
                shift 2
                ;;
            --threshold)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Threshold=$2
                shift 2
                ;;
            --ping-type)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Ping_Type=$2
                shift 2
                ;;
            --ping-dest)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Ping_Dest=$2
                shift 2
                ;;
            --ping-ip-version)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Ping_IP_Version=$2
                shift 2
                ;;
            --http-url)
                [ $# -ge 2 ] || { log "Missing value for $1"; exit 1; }
                Http_Url=$2
                shift 2
                ;;
            *)
                log "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    [ -z "$Modem_ID" ] && log "Modem_ID is empty" && exit 1
    [ -z "$Method" ] && log "Method is empty" && exit 1
    [ -z "$Interval" ] && log "Interval is empty" && Interval=12
    [ -z "$Threshold" ] && log "Threshold is empty" && Threshold=5
    case "$Modem_ID" in *[!A-Za-z0-9_]*|"") log "Invalid Modem_ID: $Modem_ID"; exit 1 ;; esac
    case "$Interval" in *[!0-9]*|"") log "Invalid interval: $Interval"; Interval=12 ;; esac
    case "$Threshold" in *[!0-9]*|"") log "Invalid threshold: $Threshold"; Threshold=5 ;; esac
    [ "$Interval" -gt 0 ] || Interval=12
    [ "$Threshold" -gt 0 ] || Threshold=5
}


log(){
    logger -t qmodem_monitor "$Modem_ID($Method): $@"
    #echo "$Modem_ID($Method): $@"
}

record_modem_event(){
    [ -x /usr/sbin/zbt-modem-events ] || return 0
    /usr/sbin/zbt-modem-events record "$@" >/dev/null 2>&1 || true
}

load_monitor_cooldown(){
    config_load qmodem 2>/dev/null || true
    config_get MONITOR_COOLDOWN_S main zbt_monitor_cooldown "$MONITOR_COOLDOWN_S_DEFAULT"
    case "$MONITOR_COOLDOWN_S" in *[!0-9]*|"") MONITOR_COOLDOWN_S=$MONITOR_COOLDOWN_S_DEFAULT ;; esac
    [ "$MONITOR_COOLDOWN_S" -gt 0 ] || MONITOR_COOLDOWN_S=$MONITOR_COOLDOWN_S_DEFAULT
}

monitor_cooldown_active(){
    local uptime_s now lock_mtime age remaining
    if [ -x "$MONITOR_COOLDOWN_HELPER" ]; then
        remaining=$("$MONITOR_COOLDOWN_HELPER" active 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            log "Cooldown active: ${remaining}s remaining; skip monitor actions"
            record_modem_event monitor monitor_cooldown warning "$Modem_ID" "Monitor action skipped by cooldown" "remaining=${remaining}s"
            return 0
        fi
    fi
    uptime_s=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    case "$uptime_s" in *[!0-9]*|"") uptime_s=0 ;; esac
    if [ "$uptime_s" -lt "$MONITOR_COOLDOWN_S" ]; then
        log "Cooldown active: router uptime ${uptime_s}s < ${MONITOR_COOLDOWN_S}s; skip monitor actions"
        record_modem_event monitor monitor_cooldown warning "$Modem_ID" "Monitor action skipped by boot cooldown" "uptime=${uptime_s}s cooldown=${MONITOR_COOLDOWN_S}s"
        return 0
    fi
    [ -f "$MONITOR_COOLDOWN_FILE" ] || return 1
    lock_mtime=$(stat -c %Y "$MONITOR_COOLDOWN_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    case "$lock_mtime" in *[!0-9]*|"") lock_mtime=0 ;; esac
    case "$now" in *[!0-9]*|"") now=0 ;; esac
    age=$(( now - lock_mtime ))
    [ "$age" -ge 0 ] || age=0
    if [ "$age" -lt "$MONITOR_COOLDOWN_S" ]; then
        log "Cooldown active: last monitor action ${age}s ago < ${MONITOR_COOLDOWN_S}s; skip monitor actions"
        record_modem_event monitor monitor_cooldown warning "$Modem_ID" "Monitor action skipped by action cooldown" "last_action_age=${age}s cooldown=${MONITOR_COOLDOWN_S}s"
        return 0
    fi
    return 1
}

mark_monitor_action(){
    if [ -x "$MONITOR_COOLDOWN_HELPER" ]; then
        "$MONITOR_COOLDOWN_HELPER" mark-action "$Modem_ID" "monitor_action" >/dev/null 2>&1 || true
        return 0
    fi
    touch "$MONITOR_COOLDOWN_FILE" 2>/dev/null || true
}

update_cfg(){
	config_load qmodem
	config_get AT_PORT "$Modem_ID" at_port
	config_get ALIAS "$Modem_ID" alias
	config_get USE_UBUS "$Modem_ID" use_ubus
	[ "$USE_UBUS" = "1" ] && use_ubus_flag="-u"
    log "loaded config for modem $Modem_ID: at_port=$AT_PORT, alias=$ALIAS, use_ubus=$USE_UBUS"
}

update_netcfg(){
	# Resolve NET_DEV (the netdev passed to curl --interface / ping -I)
	# from /etc/config/network using the modem's alias as the section
	# name when set, falling back to the modem-id otherwise.
	#
	# This routine has three independent fixes layered in:
	#
	# 1) "-" treated as set: qmodem stores "no alias" as the literal
	#    dash character (visible in logs as `alias=-`), not as an
	#    empty string. The original [ -n "$ALIAS" ] tested truthy for
	#    "-", taking the alias branch and looking up network.-.ifname
	#    which never exists. Treat "-" as empty.
	#
	# 2) ifname -> device fallback: modern OpenWrt netifd (21.02+)
	#    canonicalises layer-2 device names on `option device`. The
	#    legacy `option ifname` is no longer written for new wwan
	#    interfaces created by qmodem. Falling back to `option device`
	#    when ifname is empty makes the script work on current
	#    OpenWrt without operator-side migration.
	#
	# 3) Alias -> modem-id fallback: the alias is intended as a
	#    human-readable display name (e.g. "modem1"), not as a hard
	#    requirement that a matching network section must exist. If
	#    the alias-named lookup yields nothing, fall back to the
	#    modem-id named section (which qmodem itself created and
	#    keeps in sync). This makes a sensible alias=modem1 setting
	#    work without requiring the operator to also create a
	#    matching network.modem1 section that would conflict with
	#    the real network.<modem_id> interface.
	#
	# Without these three fixes layered together, NET_DEV ends up
	# empty in the common deployment shape (modern OpenWrt + qmodem
	# default UCI), curl runs without --interface, probes leak via
	# the system default route (often the OTHER WAN on a multi-uplink
	# router), and any flakiness on that other path becomes a chronic
	# false-positive that escalates monitor_action=run_scripts into
	# reboot dispatches against a healthy modem every ~6 minutes.
	config_load network
	if [ -n "$ALIAS" ] && [ "$ALIAS" != "-" ]; then
		config_get NET_DEV "$ALIAS" ifname
		[ -z "$NET_DEV" ] && config_get NET_DEV "$ALIAS" device
		if [ -n "$NET_DEV" ]; then
			Ifv4="$ALIAS"
		else
			# Alias is a display name only; the real netifd
			# section is named after the modem-id.
			config_get NET_DEV "$Modem_ID" ifname
			[ -z "$NET_DEV" ] && config_get NET_DEV "$Modem_ID" device
			Ifv4="$Modem_ID"
		fi
	else
		config_get NET_DEV "$Modem_ID" ifname
		[ -z "$NET_DEV" ] && config_get NET_DEV "$Modem_ID" device
		Ifv4="$Modem_ID"
	fi
    Ifv6="$Ifv4"v6
    v4_info=$(ifstatus "$Ifv4")
    v6_info=$(ifstatus "$Ifv6")
    dns_v4=$(printf '%s\n' "$v4_info" | jq -r --arg "key" "dns-server" '.[$key][0]')
    dns_v6=$(printf '%s\n' "$v6_info" | jq -r --arg "key" "dns-server" '.[$key][0]')
    gateway_v4=$(printf '%s\n' "$v4_info" | jq -r --arg "key" "route" '.[$key][] | select(.target == "0.0.0.0") | .nexthop')
    gateway_v6=$(printf '%s\n' "$v6_info" | jq -r --arg "key" "route" '.[$key][] | select(.target == "::") | .nexthop')
    is_up_v4=$(printf '%s\n' "$v4_info" | jq -r --arg "key" "up" '.[$key]')
    is_up_v6=$(printf '%s\n' "$v6_info" | jq -r --arg "key" "up" '.[$key]')
}

wait_until_ready(){
    #nesseary variable: NET_DEV
    if [ -z "$NET_DEV" ]; then
        log "NET_DEV is empty"
        return 1
    fi
    return 0
}

# Monitor type

# Method: ping - Ping IP address to check connectivity
# Usage: ping <Target> or ping <Modem_ID>
# Parameters:
# <Type> - The type of target to ping. Can be "ip" or "modem".
# <Target> - The IP address or V4/V6 Interface name to ping.
# <Modem_ID> - The ID of the modem to use for pinging.
_ping() {
    Type=$1
    Target=$2
    case $Type in
        ip)
            ping -c 1 "$Target" -I "$NET_DEV"
            status=$?
            ;;
        gateway)
            case $Target in
                4)
                    ping -c 1 "$gateway_v4" -I "$NET_DEV"
                    status=$?
                ;;
                6)
                    ping -c 1 "$gateway_v6" -I "$NET_DEV"
                    status=$?
                ;;
                *)
                    log "Invalid target type $Target"
                    status=1
                ;;
            esac
        ;;
        dns)
        case $Target in
            4)
                ping -c 1 "$dns_v4" -I "$NET_DEV"
                status=$?
                ;;
            6)
                ping -c 1 "$dns_v6" -I "$NET_DEV"
                status=$?
                ;;
            *)
                log "Invalid target type $Target"
                status=1
                ;;
        esac
        ;;
        *)
                log "Invalid type $Type"
                status=1
        ;;
    esac
    if [ "$status" -ne 0 ]; then
        log "Ping failed"
    fi
    return $status
}


# Method curl - Download file using curl
# Usage: curl <URL>
_curl() {
  url=$1
  # timeout 10s
  res=$(curl --connect-timeout 10 --max-time 15 --interface "$NET_DEV" "$url" -o /dev/null --silent --show-error)
  status=$?
  if [ "$status" -ne 0 ]; then
    log "Curl failed: $res"
  fi
  return $status
}

# Method: signal - Get signal strength
# Usage: signal <Modem_ID>

# Method: operator registion - Get operator registration status
# Usage: operator <Modem_ID>

# Actions

# Action: log - Log the output to syslog
# Usage: log <MESSAGE>

# Action: notify - Send a notification
# Usage: notify <TITLE> <MESSAGE>

# Action: run_script - Run a custom script
# Usage: run_script <SCRIPT_PATH> [ARGUMENTS...]
run_scripts(){
    config_load qmodem
    config_list_foreach "$Modem_ID" script _run_script
}

_run_script(){
    local script_path=$1
    shift
    log "Run script: $script_path $@"
    case "$script_path" in
        /*) ;;
        *) log "Refusing non-absolute script path: $script_path"; return 1 ;;
    esac
    [ -x "$script_path" ] || { log "Script is not executable: $script_path"; return 1; }
    "$script_path" "$@"
}


# Action: send_at_commands - Send AT commands to modem
# Usage: send_at_commands <Modem_ID>
send_at_commands() {
  config_load qmodem
  config_list_foreach "$Modem_ID" at_command _send_at_command
}

_send_at_command(){
    local at_command
    at_command=$1
    log "Send AT command: $at_command"
    res=$(at "$AT_PORT" "$at_command")
    log "AT command response: $res"
}

# Action: switch_sim_slot - Switch SIM slot
# Usage: switch_sim_slot <Modem_ID>
switch_sim_slot() {
  is_supported=$(ubus call qmodem get_sim_switch_capabilities "{\"config_section\":\"$Modem_ID\"}" | jq -r '.supportSwitch')
  if [ "$is_supported" = "1" ]; then
    current_slot=$(ubus call qmodem get_sim_slot "{\"config_section\":\"$Modem_ID\"}" | jq -r '.sim_slot')
    available_slots=$(ubus call qmodem get_sim_switch_capabilities "{\"config_section\":\"$Modem_ID\"}" | jq -r '.simSlots[]')
    for slot in $available_slots; do
        if [ "$slot" != "$current_slot" ]; then
            new_slot=$slot
            break
        fi
    done
    ubus call qmodem set_sim_slot "{\"config_section\":\"$Modem_ID\",\"slot\":$new_slot}"
    log "Switch SIM slot from $current_slot to $new_slot"
  else
    log "Switching SIM slot is not supported for modem $Modem_ID"
  fi
}

# Parameters:
# <Modem_ID> - The ID of the modem to perform the action on.
# <Interval> - The interval in seconds between each monitoring check.
# <Threshold> - The condition to trigger the action.


loop(){
    wait_until_ready || return 1
    case $Method in
        ping)
            case $Ping_Type in
                ip)
                    _ping "$Ping_Type" "$Ping_Dest"
                    status=$?
                    ;;
                gateway|dns)
                    _ping "$Ping_Type" "$Ping_IP_Version"
                    status=$?
                    ;;
                *)
                    log "Invalid ping type: $Ping_Type"
                    status=1
                    ;;
            esac
            ;;
        curl)
            _curl "$Http_Url"
            status=$?
            ;;
        *)
            log "Invalid method"
            status=1
            ;;
    esac
    return $status
}

run_action(){
    Action=$1
    case $Action in
        switch_sim_slot)
            switch_sim_slot
            ;;
        send_at_commands)
            send_at_commands
            ;;
        run_scripts)
            run_scripts
            ;;
        *)
            log "Invalid action $Action"
            ;;
    esac
}

run_actions(){
    config_load qmodem
    config_list_foreach "$Modem_ID" monitor_action run_action
}

no_sim_present(){
    [ -n "$AT_PORT" ] && [ -e "$AT_PORT" ] || return 1
    local out
    if command -v tom_modem >/dev/null 2>&1; then
        out=$(tom_modem -d "$AT_PORT" -o a -c "AT+CPIN?" -t 5 2>&1 || true)
        case "$out" in *"+CME ERROR: 10"*|*"SIM not inserted"*|*"SIM NOT INSERTED"*|*"NO SIM"*|*"No SIM"*) return 0 ;; esac
    fi
    if command -v sms_tool >/dev/null 2>&1; then
        out=$(sms_tool -d "$AT_PORT" -t 5 at "AT+CPIN?" 2>&1 || true)
        case "$out" in *"+CME ERROR: 10"*|*"SIM not inserted"*|*"SIM NOT INSERTED"*|*"NO SIM"*|*"No SIM"*) return 0 ;; esac
    fi
    if command -v sms_tool_q >/dev/null 2>&1; then
        out=$(sms_tool_q -d "$AT_PORT" at "AT+CPIN?" 2>&1 || true)
        case "$out" in *"+CME ERROR: 10"*|*"SIM not inserted"*|*"SIM NOT INSERTED"*|*"NO SIM"*|*"No SIM"*) return 0 ;; esac
    fi
    out=$(at "$AT_PORT" "AT+CPIN?" 2>&1 || true)
    case "$out" in *"+CME ERROR: 10"*|*"SIM not inserted"*|*"SIM NOT INSERTED"*|*"NO SIM"*|*"No SIM"*) return 0 ;; esac
    return 1
}

record_no_sim_suspended(){
    [ -f "$NO_SIM_STATE_FILE" ] && return 0
    log "No SIM present; suspend monitor probes"
    record_modem_event monitor monitor_no_sim info "$Modem_ID" "Monitor suspended because SIM is missing" "method=${Method} netdev=${NET_DEV:-none}"
    touch "$NO_SIM_STATE_FILE" 2>/dev/null || true
}

record_sim_resumed(){
    [ -f "$NO_SIM_STATE_FILE" ] || return 0
    rm -f "$NO_SIM_STATE_FILE" 2>/dev/null || true
    log "SIM present; resume monitor probes"
    record_modem_event monitor monitor_recovered ok "$Modem_ID" "Monitor resumed because SIM is present" "method=${Method} netdev=${NET_DEV:-none}"
}

parse_args "$@"
NO_SIM_STATE_FILE="/tmp/zbt-qmodem-monitor-no-sim-${Modem_ID}"
update_cfg
load_monitor_cooldown
update_netcfg
log "Start monitoring $Modem_ID($Method) with interval $Interval and threshold $Threshold"
failed_count=0
while true; do
    update_netcfg
    if no_sim_present; then
        record_no_sim_suspended
        failed_count=0
        sleep "$Interval"
        continue
    fi
    record_sim_resumed
    # wait_until_ready
    # status=$?
    # if [ "$status" -ne 0 ]; then
    #     continue
    # fi
    loop
    status=$?
    if [ "$status" -ne 0 ]; then
        if no_sim_present; then
            record_no_sim_suspended
            failed_count=0
            sleep "$Interval"
            continue
        fi
        failed_count=$((failed_count + 1))
        log "Failed count: $failed_count Threshold: $Threshold"
        record_modem_event monitor monitor_check_failed warning "$Modem_ID" "Monitor probe failed" "count=${failed_count}/${Threshold} method=${Method} netdev=${NET_DEV:-none} url=${Http_Url:-}"
    else
        if [ "$failed_count" -gt 0 ]; then
            record_modem_event monitor monitor_recovered ok "$Modem_ID" "Monitor probe recovered" "after_failed_checks=${failed_count} method=${Method} netdev=${NET_DEV:-none}"
        fi
        failed_count=0
    fi
    sleep "$Interval"

    if [ "$failed_count" -ge "$Threshold" ]; then
        if no_sim_present; then
            record_no_sim_suspended
            failed_count=0
            sleep "$Interval"
            continue
        fi
        log "$Method failed $failed_count times"
        record_modem_event monitor monitor_threshold danger "$Modem_ID" "Monitor threshold reached" "failed_checks=${failed_count} threshold=${Threshold} method=${Method} netdev=${NET_DEV:-none} url=${Http_Url:-}"
        if monitor_cooldown_active; then
            failed_count=0
        else
            mark_monitor_action
            record_modem_event monitor monitor_action danger "$Modem_ID" "Monitor dispatching configured action" "failed_checks=${failed_count} action=run_scripts"
            run_actions
        fi
        failed_count=0
        sleep 60
    fi
done
