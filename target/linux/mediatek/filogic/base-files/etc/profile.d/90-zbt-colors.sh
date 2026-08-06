# Colorized shell profile for OpenWrt BusyBox ash.
# Ships in /etc/profile.d/ so it runs for every interactive shell
# (SSH login, console login, `su -`, etc.).

case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in
	zbtlink,zbt-z8803be|zbtlink,zbt-z8803be,mt7988a-nand) ;;
	*) return 0 ;;
esac

# Colorful prompt: root@hostname ~/path $
# \e[1;31m red (user) \e[1;33m yellow (@ and cwd) \e[1;36m cyan (host)
# \e[1;35m magenta (prompt char) \e[0m reset
export PS1='\[\e[1;31m\]\u\[\e[1;33m\]@\[\e[1;36m\]\h \[\e[1;33m\]\w \[\e[1;35m\]\$ \[\e[0m\]'

# History
export HISTSIZE=99999
export HISTFILE='/root/.ash_history'
export HISTCONTROL=ignoreboth

# Color ls / grep
alias ls='ls --color=auto'
alias ll='ls --color=auto -lh'
alias la='ls --color=auto -lAh'
alias l='ls --color=auto -CF'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Router shortcuts
alias lg='logread | tail -50'
alias lf='logread -f'
alias ports='netstat -tulnp'
alias reload='uci commit && wifi reload 2>/dev/null; echo done'
alias meminfo='free -h && cat /proc/meminfo | grep -E "^MemFree|^Buffers|^Cached"'
alias cpuinfo='top -bn1 | head -6'
alias tempinfo='for z in /sys/class/thermal/thermal_zone*; do printf "%s: %s\n" "$(basename "$z")" "$(($(cat "$z/temp" 2>/dev/null)/1000))C"; done'
alias modem='ls /dev/cdc-wdm* /dev/ttyUSB* /dev/wwan* 2>/dev/null; lsusb 2>/dev/null | grep -iE "quectel|fibocom|sierra|telit|simcom|meiglink|huawei" || echo "(no modem enumerated)"'
alias myip='ip -4 addr show $(ip route show default 2>/dev/null | awk "/^default/{print \$5; exit}") 2>/dev/null | awk "/inet /{print \$2}"'
