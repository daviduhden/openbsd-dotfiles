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
		printf 'Memory: %s/%s MB | ' "$used_mb" "$total_mb"
	else
		printf 'Memory: N/A | '
	fi
}

print_cpu() {
	if [ "$OS" = "OpenBSD" ] && command -v iostat >/dev/null 2>&1; then
		idle=$(iostat -C -c 2 2>/dev/null | awk 'NR==3 {print $NF}')
		if [ -n "$idle" ]; then
			printf 'CPU: %s%% used | ' "$((100 - idle))"
		else
			printf 'CPU: N/A | '
		fi
	else
		printf 'CPU: N/A | '
	fi
}

print_cpuspeed() {
	if [ "$OS" = "OpenBSD" ] && command -v sysctl >/dev/null 2>&1; then
		speed=$(sysctl -n hw.cpuspeed 2>/dev/null)
		if [ -n "$speed" ]; then
			printf 'CPU Freq: %s MHz | ' "$speed"
		else
			printf 'CPU Freq: N/A | '
		fi
	else
		printf 'CPU Freq: N/A | '
	fi
}

print_bat() {
	if [ "$OS" = "OpenBSD" ] && command -v apm >/dev/null 2>&1; then
		level=$(apm -l 2>/dev/null)
		ac=$(apm -a 2>/dev/null)
		if [ "$level" != "-1" ] && [ "$ac" != "-1" ]; then
			if [ "$ac" -eq 1 ]; then
				printf 'Power: AC (%s%%)' "$level"
			else
				printf 'Battery: %s%%' "$level"
			fi
			return
		fi
	fi
	printf 'Battery: N/A'
}

while :; do
	print_mem
	print_cpu
	print_cpuspeed
	print_bat
	echo ""
	sleep 2
done
