#!/bin/ksh
#
# Simple system monitor script for spectrwm on OpenBSD
# Displays memory, CPU usage, CPU speed,
# battery status, and current date/time.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

OS=$(uname -s)
PAGE_SIZE=$(getconf PAGE_SIZE 2>/dev/null || echo 4096)

print_mem() {
	if [ "$OS" = "OpenBSD" ] && command -v sysctl >/dev/null 2>&1; then
		total_bytes=$(sysctl -n hw.physmem)
		total_mb=$((total_bytes / 1024 / 1024))
		free_pages=$(vmstat | awk 'NR==3 {print $5}')
		free_mb=$((free_pages * PAGE_SIZE / 1024 / 1024))
		used_mb=$((total_mb - free_mb))
		printf 'Mem:%s/%sMB  ' "$used_mb" "$total_mb"
	else
		printf 'Mem:n/a  '
	fi
}

print_cpu() {
	if [ "$OS" = "OpenBSD" ] && command -v iostat >/dev/null 2>&1; then
		idle=$(iostat -C -c 2 2>/dev/null | awk 'NR==3 {print $NF}')
		[ -n "$idle" ] && printf 'CPU:%s%%  ' "$((100 - idle))" || printf 'CPU:n/a  '
	else
		printf 'CPU:n/a  '
	fi
}

print_cpuspeed() {
	if [ "$OS" = "OpenBSD" ] && command -v sysctl >/dev/null 2>&1; then
		speed=$(sysctl -n hw.cpuspeed 2>/dev/null)
		[ -n "$speed" ] && printf 'CPU:%sMHz  ' "$speed" || printf 'CPU:n/a  '
	else
		printf 'CPU:n/a  '
	fi
}

print_bat() {
	if [ "$OS" = "OpenBSD" ] && command -v apm >/dev/null 2>&1; then
		level=$(apm -l 2>/dev/null)
		ac=$(apm -a 2>/dev/null)
		if [ "$level" != "-1" ] && [ "$ac" != "-1" ]; then
			[ "$ac" -eq 1 ] && printf 'AC:%s%%  ' "$level" || printf 'Bat:%s%%  ' "$level"
			return
		fi
	fi
	printf 'Bat:n/a  '
}

print_date() {
	date '+%A %d %B %H:%M'
}

while :; do
	print_mem
	print_cpu
	print_cpuspeed
	print_bat
	print_date
	echo ""
	sleep 2
done
