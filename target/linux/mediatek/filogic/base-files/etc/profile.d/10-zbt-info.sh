# Prints live kernel + hardware info after the static banner.
# Runs on every interactive shell via /etc/profile -> /etc/profile.d/*.sh.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in
	zbtlink,zbt-z8803be|zbtlink,zbt-z8803be,mt7988a-nand) ;;
	*) return 0 ;;
esac

# Kernel
_zbt_k="$(uname -r 2>/dev/null)"
# Uptime (just the "up X" portion)
_zbt_up="$(uptime 2>/dev/null | sed 's/.*up[[:space:]]*//;s/,.*user.*$//;s/,[[:space:]]*load.*$//')"
# Load average
_zbt_ld="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
# RAM free
_zbt_mt="$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t)printf "%d / %d MiB", (t-a)/1024, t/1024}' /proc/meminfo 2>/dev/null)"

printf ' Linux %s  -  up %s  -  load %s  -  ram %s\n' \
    "${_zbt_k:-?}" "${_zbt_up:-?}" "${_zbt_ld:-?}" "${_zbt_mt:-?}"
printf ' Credits: pttuan, sjanulonoks (fan/testing), FUjr/QModem, OneB1t\n'
printf ' Donate : ERC20/BEP20 (USDT, USDC, ETH, BNB) 0xd1122130ad6e9ab948212087a90797e3129bfc1c\n'
printf '          TRC20 (TRX, USDT)              TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2\n'
printf '          BTC                            12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m\n'
printf '          LTC                            LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK\n'
printf ' -----------------------------------------------------\n'

unset _zbt_k _zbt_up _zbt_ld _zbt_mt
