#!/bin/ksh
#
# System status script for the native spectrwm status bar.
#
# Configured as spectrwm's bar_action, this script loops forever
# and prints one status line per cycle; spectrwm reads each line
# and shows it at the +A slot of bar_format (verbatim, because
# bar_action_expand is off). spectrwm starts the script once and
# reads its standard output, so the loop below controls the
# refresh rate.
#
# Refresh tiers (cycle = 2 seconds):
#   every cycle    CPU usage, network throughput
#   every 5th      memory, battery/AC state, network state
#   every 15th     Tor state
#
# The line contains, in order: CPU usage, memory usage, battery
# or AC state, network state, network throughput and Tor status.
# All values come from OpenBSD base utilities (sysctl, vmstat,
# apm, ifconfig, netstat, rcctl). Missing hardware or services
# are omitted silently; the output is plain ASCII.
#
# Only the status line is written to stdout; all expected
# command failures are redirected at their source so that
# diagnostics never reach the bar.
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

OS=$(uname -s)

cycle=0

# --- CPU usage, from kern.cp_time deltas -------------------
# cp_time lists the CPU ticks per state (user nice sys [spin]
# intr idle); all states are summed and the last one is idle,
# which keeps the parse valid across OpenBSD versions that
# added states. awk prints "CPU nn%" when the previous sample
# is usable and the new totals on the next line; the first
# sample and counter resets print an empty field instead.
cpu_ticks_total=""
cpu_ticks_idle=""

cpu_line() {
	status_cpu=""
	[ "$OS" = OpenBSD ] || return
	cpu_out=$(sysctl -n kern.cp_time 2>/dev/null | awk \
		-v pt="$cpu_ticks_total" -v pi="$cpu_ticks_idle" '{
		if (NF < 5 || $0 ~ /[^0-9 ]/)
			exit
		t = 0
		for (i = 1; i <= NF; i++)
			t += $i
		i = $NF
		if (pt != "" && t >= pt && i >= pi && t > pt)
			printf "CPU %.0f%%\n", 100 * (t - pt - (i - pi)) / (t - pt)
		else
			print ""
		print t, i
	}')
	[ -n "$cpu_out" ] || return
	cpu_ticks_total=""
	cpu_ticks_idle=""
	{
		read -r status_cpu
		read -r cpu_ticks_total cpu_ticks_idle
	} <<EOF
$cpu_out
EOF
}

# --- Memory usage, as used/total ---------------------------
# vmstat prints the free-list size in the "fre" column, in MB
# with an 'M' suffix; the column is located through the header
# so the parse survives layout changes, and the suffix is
# required so that other formats are rejected instead of being
# misread. used = total - free, which includes the file cache.
mem_line() {
	status_mem=""
	[ "$OS" = OpenBSD ] || return
	mem_total=$(sysctl -n hw.physmem 2>/dev/null)
	case "$mem_total" in
	''|*[!0-9]*) return ;;
	esac
	status_mem=$(vmstat 2>/dev/null | awk -v t="$mem_total" '
		NR == 2 {
			for (i = 1; i <= NF; i++)
				if ($i == "fre")
					col = i
			next
		}
		NR == 3 && col != "" {
			fre = $col
			if (fre !~ /M$/)
				exit
			sub(/M$/, "", fre)
			if (fre !~ /^[0-9]+$/)
				exit
			tmb = t / 1048576
			fmb = fre + 0
			if (fmb >= tmb)
				exit
			umb = tmb - fmb
			if (tmb >= 1024)
				printf "MEM %.1fG/%.0fG", umb / 1024, tmb / 1024
			else
				printf "MEM %.0fM/%.0fM", umb, tmb
			exit
		}')
}

# --- Battery / AC state (apm) ------------------------------
# apm has no combined flag for level and AC state, so two calls
# are used; both run only every fifth cycle.
bat_line() {
	status_bat=""
	bat_pct=$(apm -l 2>/dev/null)
	case "$bat_pct" in
	[0-9]|[0-9][0-9]|100) ;;
	*) return ;;
	esac
	bat_ac=$(apm -a 2>/dev/null)
	if [ "$bat_ac" = 1 ]; then
		status_bat="AC ${bat_pct}%"
	else
		status_bat="BAT ${bat_pct}%"
	fi
}

# --- Network: active interface, SSID and address -----------
# The interface carrying the default route is preferred. If the
# default route points through a tunnel-like interface (VPN),
# a physical interface is shown instead; when there is no
# default route at all, the first interface that reports
# "status: active" is used.
net_line() {
	status_net=""
	status_iface=""
	net_iface=$(netstat -rn 2>/dev/null |
		awk '/^default/ { print $NF; exit }')
	case "$net_iface" in
	''|lo*|enc*|pflog*|tun*|tap*|wg*|ppp*|gif*|gre*|pair*)
		net_iface=""
		;;
	esac
	if [ -z "$net_iface" ]; then
		net_iface=$(ifconfig 2>/dev/null | awk '
			/^[a-zA-Z][a-zA-Z0-9]*:/ {
				if (active && name != "lo0") {
					print name
					exit
				}
				name = $1
				sub(":", "", name)
				active = 0
				next
			}
			/status: active/ { active = 1 }
			END { if (active && name != "lo0") print name }
		')
	fi
	if [ -z "$net_iface" ]; then
		status_net="NET offline"
		return
	fi
	net_info=$(ifconfig "$net_iface" 2>/dev/null)
	# primary IPv4 address; on IPv6-only links, the first
	# global IPv6 address (skipping link-local fe80:: and ::1)
	net_ip=$(print -r -- "$net_info" |
		awk '/^[[:space:]]*inet / { print $2; exit }')
	if [ -z "$net_ip" ]; then
		net_ip=$(print -r -- "$net_info" |
			awk '/^[[:space:]]*inet6 / && $2 !~ /^fe80:/ && $2 != "::1" {
				print $2
				exit
			}')
	fi
	# associated nwid, only present on wireless interfaces;
	# ifconfig quotes names that contain spaces
	net_ssid=$(print -r -- "$net_info" |
		awk '/^[[:space:]]*ieee80211:/ {
			line = $0
			if (sub(/^.* (nwid|join) /, "", line)) {
				if (line ~ /^"/) {
					sub(/^"/, "", line)
					sub(/".*/, "", line)
				} else
					sub(/ .*/, "", line)
				print line
			}
			exit
		}')
	status_iface=$net_iface
	status_net="NET ${net_iface} ${net_ssid:+$net_ssid }${net_ip:-no ip}"
}

# --- Network throughput, from interface byte counters ------
# netstat -nib prints the link row with "Ibytes Obytes" as the
# last two columns. awk computes the per-second deltas against
# the previous sample (held in shell variables) and prints the
# formatted rates plus the new counters; counter resets and
# interface changes restart the baseline.
traffic_line() {
	status_traffic=""
	[ -n "$status_iface" ] || return
	traffic_now=$(date +%s)
	if [ "$traffic_prev_iface" != "$status_iface" ]; then
		traffic_prev_iface=$status_iface
		traffic_prev_rx=""
	fi
	traffic_out=$(netstat -nib -I "$status_iface" 2>/dev/null | awk \
		-v pr="$traffic_prev_rx" -v pt="$traffic_prev_tx" \
		-v ptime="$traffic_prev_time" -v now="$traffic_now" '
		NR == 2 {
		if (NF != 6 || $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/)
			exit
		rx = $5 + 0
		tx = $6 + 0
		if (pr != "" && now > ptime && rx >= pr && tx >= pt)
			printf "dn %s up %s\n", rate((rx - pr) / (now - ptime)),
			    rate((tx - pt) / (now - ptime))
		else
			print ""
		print rx, tx
		exit
		}
	function rate(n) {
		if (n >= 1073741824) {
			d = 1073741824
			u = "G"
		} else if (n >= 1048576) {
			d = 1048576
			u = "M"
		} else if (n >= 1024) {
			d = 1024
			u = "K"
		} else
			return sprintf("%dB", n)
		v = n / d
		if (v >= 10)
			return sprintf("%d%s", int(v + 0.5), u)
		if (v == int(v))
			return sprintf("%d%s", v, u)
		return sprintf("%.1f%s", v, u)
	}')
	[ -n "$traffic_out" ] || return
	traffic_prev_rx=""
	traffic_prev_tx=""
	traffic_prev_time=""
	{
		read -r status_traffic
		read -r traffic_prev_rx traffic_prev_tx
	} <<EOF
$traffic_out
EOF
	case "$traffic_prev_rx$traffic_prev_tx" in
	''|*[!0-9]*)
		traffic_prev_rx=""
		;;
	*)
		traffic_prev_time=$traffic_now
		;;
	esac
}

# --- Tor daemon state --------------------------------------
# rcctl check tor works unprivileged, but reports "service tor
# does not exist" on stderr when the package is absent; the
# executable test skips that call entirely.
tor_line() {
	status_tor=""
	[ -x /etc/rc.d/tor ] || return
	rcctl check tor >/dev/null 2>&1 && status_tor="TOR"
}

while :; do
	status_cpu=""
	status_mem=""
	status_bat=""
	status_net=""
	status_traffic=""
	status_tor=""

	((cycle += 1))

	cpu_line
	if ((cycle % 5 == 1)); then
		mem_line
		bat_line
		net_line
	fi
	traffic_line
	if ((cycle % 15 == 1)); then
		tor_line
	fi

	line=""
	for field in "$status_cpu" "$status_mem" "$status_bat" \
		"$status_net" "$status_traffic" "$status_tor"; do
		if [ -n "$field" ]; then
			if [ -n "$line" ]; then
				line="$line  $field"
			else
				line=$field
			fi
		fi
	done
	print -r -- "$line"
	sleep 2
done
