#!/bin/ksh
#
# Regression tests for the spectrwm status bar script and the
# installer keyboard-layout handling.
#
# The status bar script is executed against a directory of mock
# OpenBSD commands that emulate the verified output formats of
# sysctl, vmstat, apm, netstat, ifconfig, rcctl and date. The
# installer tests extract ask_keyboard_layout and
# apply_keyboard_layout from install.ksh and run them against
# canned input.
#
# Usage: ksh tests/statusbar_test.ksh
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

SRC=$(cd "$(dirname "$0")/.." && pwd)
TESTDIR=$(mktemp -d /tmp/statusbar-test.XXXXXX) || exit 1
trap 'rm -rf "$TESTDIR"' EXIT INT TERM

MOCK="$TESTDIR/bin"
STATE="$TESTDIR/state"
export STATE
mkdir -p "$STATE"
PASSES=0
FAILS=0

ok() {
	((PASSES = PASSES + 1))
	print "ok - $1"
}

notok() {
	((FAILS = FAILS + 1))
	print "FAIL - $1"
}

# install a mock command from stdin
mockcmd() {
	name=$1
	cat >"$MOCK/$name"
	chmod +x "$MOCK/$name"
}

reset_mocks() {
	rm -rf "$MOCK"
	mkdir -p "$MOCK"
}

# prepare a copy of the status script for the mock environment:
# absolute tool paths are redirected to the mock binaries, the
# OS detection is forced to OpenBSD and the pledge/unveil
# sandbox is disabled (it would block the mock paths)
prepare_bar() {
	cp "$SRC/.config/spectrwm/statusbar.pl" "$TESTDIR/bar.pl"
	sed -i \
		-e "s#/sbin/sysctl#$MOCK/sysctl#g" \
		-e "s#/usr/bin/vmstat#$MOCK/vmstat#g" \
		-e "s#/usr/sbin/apm#$MOCK/apm#g" \
		-e "s#/usr/bin/netstat#$MOCK/netstat#g" \
		-e "s#/sbin/ifconfig#$MOCK/ifconfig#g" \
		-e "s#/usr/sbin/rcctl#$MOCK/rcctl#g" \
		-e "s/^my \\\$is_openbsd = .*/my \\\$is_openbsd = 1;/" \
		-e "s/\\\$^O eq 'openbsd'/0/g" \
		"$TESTDIR/bar.pl"
}

# run the status script for six cycles under the mock PATH;
# $1 is the cycle interval in seconds
run_bar() {
	prepare_bar
	STATUSBAR_INTERVAL=$1 perl "$TESTDIR/bar.pl" 6 \
		>"$TESTDIR/out" 2>"$TESTDIR/err"
}

# run the status script with /etc/rc.d/tor redirected (for Tor tests)
run_bar_tor() {
	prepare_bar
	sed -i \
		-e "s|/etc/rc.d/\\\$svc|$TESTDIR/rc.d/\\\$svc|" \
		"$TESTDIR/bar.pl"
	STATUSBAR_INTERVAL=0.1 perl "$TESTDIR/bar.pl" 6 \
		>"$TESTDIR/out" 2>"$TESTDIR/err"
}

line() { # line number -> contents
	sed -n "$1p" "$TESTDIR/out"
}

expect_line_contains() { # line, pattern, description
	if line "$1" | grep -q "$2"; then
		ok "$3"
	else
		notok "$3 (line $1: '$(line "$1")')"
	fi
}

expect_line_lacks() { # line, pattern, description
	if line "$1" | grep -q "$2"; then
		notok "$3 (line $1: '$(line "$1")')"
	else
		ok "$3"
	fi
}

expect_no_line_contains() { # pattern, description
	if grep -q "$1" "$TESTDIR/out"; then
		notok "$2"
	else
		ok "$2"
	fi
}

expect_stderr_empty() {
	if [ -s "$TESTDIR/err" ]; then
		notok "stderr must stay empty (got: $(cat "$TESTDIR/err"))"
	else
		ok "stderr stays empty"
	fi
}

expect_no_markup() {
	if grep -q '+@\|+|' "$TESTDIR/out"; then
		notok "no spectrwm markup sequences in output"
	else
		ok "no spectrwm markup sequences in output"
	fi
}

# ------------------------------------------------------------
# CPU tests
# ------------------------------------------------------------
test_cpu_first_sample_and_delta() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
[ "$1" = "-n" ] && shift
S=$STATE/cptime
case "$*" in
"kern.cp_time")
	n=$(cat "$S" 2>/dev/null || echo 0)
	v=$((2000 + n * 500))
	echo "$v $((v + 400)) $((v + 500)) $((v + 600)) $((v + 1500))"
	echo $((n + 1)) >"$S"
	;;
"hw.physmem") echo 8589934592 ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
printf ' procs    memory       page                    disks    traps          cpu\n'
printf ' r   s   avm     fre  flt  re  pi  po  fr  sr w0 w1 w2  int   sys   cs us sy id\n'
printf ' 0   0  30876M   800M   88   0   0   0  62   0  0  0  415 1361  473  2  2 96\n'
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_lacks 1 "CPU" "first sample shows no CPU percentage"
	expect_line_contains 2 "CPU 80%" "CPU delta is computed correctly"
	expect_stderr_empty
	expect_no_markup
}

test_cpu_zero_delta() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
echo "2000 2400 2500 2600 3500"
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_no_line_contains "CPU" "zero delta never shows a CPU percentage"
	expect_stderr_empty
}

test_cpu_counter_reset() {
	reset_mocks
	cat >"$STATE/cpseq" <<'EOF'
2000 2400 2500 2600 3500
100 500 600 700 1600
200 600 700 800 1700
EOF
	mockcmd sysctl <<'EOF'
#!/bin/sh
[ "$1" = "-n" ] && shift
S=$STATE/cpseq
case "$*" in
"kern.cp_time")
	read -r line <"$S" || exit 1
	echo "$line"
	tail -n +2 "$S" >"$S.tmp" && mv "$S.tmp" "$S"
	;;
"hw.physmem") echo 8589934592 ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_lacks 1 "CPU" "reset: first line has no CPU"
	expect_line_lacks 2 "CPU" "reset: decreased counters show no bogus CPU"
	expect_line_contains 3 "CPU 80%" "reset: CPU recovers after the reset"
	expect_stderr_empty
}

test_cpu_malformed_output() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
echo "bogus data here" >&2
exit 1
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_no_line_contains "CPU" "malformed cp_time shows no CPU"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Memory tests
# ------------------------------------------------------------
test_mem_modern_format() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
printf ' procs    memory       page                    disks    traps          cpu\n'
printf ' r   s   avm     fre  flt  re  pi  po  fr  sr w0 w1 w2  int   sys   cs us sy id\n'
printf ' 0   0  30876M   800M   88   0   0   0  62   0  0  0  415 1361  473  2  2 96\n'
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "MEM 7.2G/8G" "memory shows used/total in GiB"
	expect_stderr_empty
}

test_mem_small_machine() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 536870912 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
printf ' procs    memory       page                    disks    traps          cpu\n'
printf ' r   s   avm     fre  flt  re  pi  po  fr  sr w0 w1 w2  int   sys   cs us sy id\n'
printf ' 0   0  30876M   100M   88   0   0   0  62   0  0  0  415 1361  473  2  2 96\n'
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "MEM 412M/512M" "memory shows MiB on small machines"
	expect_stderr_empty
}

test_mem_rejects_old_format() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
printf ' procs    memory       page                    disks    traps          cpu\n'
printf ' r b w    avm     fre  flt  re  pi  po  fr  sr w0 w1 w2  int   sys   cs us sy id\n'
printf ' 0 0 0  30876    800   88   0   0   0  62   0  0  0  415 1361  473  2  2 96\n'
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_no_line_contains "MEM" "unsuffixed fre values are rejected, not misread"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Network tests
# ------------------------------------------------------------
test_net_offline() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") exit 0 ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "NET offline" "no interfaces shows NET offline"
	expect_no_line_contains "dn " "offline: no throughput field"
	expect_stderr_empty
}

test_net_ipv4_wired() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") echo "default            192.0.2.1            UGS       0     0     -     3 em0" ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	index 1 priority 0 llprio 3
	media: Ethernet autoselect (1000baseT full-duplex,master)
	status: active
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "NET em0 192.0.2.10" "wired interface with IPv4 address"
	expect_stderr_empty
}

test_net_ipv6_only() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") echo "default            fe80::1%em0          UGS       0     0     -     3 em0" ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	status: active
	inet6 fe80::aabb:ccff:fedd:eeff%em0 prefixlen 64 scopeid 0x3
	inet6 2001:db8::10 prefixlen 64
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "NET em0 2001:db8::10" "IPv6-only interface shows global address"
	expect_line_lacks 1 "fe80" "link-local IPv6 is not displayed"
	expect_stderr_empty
}

test_net_wifi_ssid_with_spaces() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") echo "default            10.0.0.1             UGS       0     0     -     3 iwm0" ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
iwm0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	ieee80211: nwid "My Home Net" chan 1 bssid ff:ee:dd:cc:bb:aa
	status: active
	inet 10.0.0.2 netmask 0xffffff00 broadcast 10.0.0.255
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "NET iwm0 My Home Net 10.0.0.2" "quoted SSID with spaces is kept whole"
	expect_stderr_empty
}

test_net_tunnel_fallback() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") echo "default            10.9.0.1             UGS       0     0     -     3 tun0" ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
if [ $# -eq 0 ]; then
	cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	status: active
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
IF
else
	cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	status: active
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
IF
fi
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "NET em0 192.0.2.10" "tunnel default route falls back to physical interface"
	expect_line_lacks 1 "tun0" "tunnel interface is not displayed"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Throughput tests
# ------------------------------------------------------------
test_traffic_rates() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
S=$STATE/nib
n=$(cat "$S" 2>/dev/null || echo 0)
case "$*" in
"-rn") echo "default            192.0.2.1            UGS       0     0     -     3 em0" ;;
"-nib -I em0")
	printf 'Name  Mtu   Network       Address              Ibytes    Obytes\n'
	printf 'em0  1500  <Link>        aa:bb:cc:dd:ee:ff   %8d   %8d\n' $((n * 4096)) $((n * 2048))
	echo $((n + 1)) >"$S"
	;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	status: active
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	# real elapsed time is used for the rates (Perl's time()),
	# so the cycle interval must exceed one second
	run_bar 1.5
	expect_line_lacks 1 "dn " "throughput: first sample is omitted"
	expect_line_contains 2 "dn [0-9].*K up [0-9].*K" "throughput rates scale to K"
	expect_stderr_empty
}

test_traffic_counter_reset() {
	reset_mocks
	: >"$STATE/nibseq"
	cat >"$STATE/nibseq" <<'EOF'
10000 5000
200 100
4296 2148
EOF
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
S=$STATE/nibseq
case "$*" in
"-rn") echo "default            192.0.2.1            UGS       0     0     -     3 em0" ;;
"-nib -I em0")
	read -r rx tx <"$S" || exit 1
	printf 'Name  Mtu   Network       Address              Ibytes    Obytes\n'
	printf 'em0  1500  <Link>        aa:bb:cc:dd:ee:ff   %8s   %8s\n' "$rx" "$tx"
	tail -n +2 "$S" >"$S.tmp" && mv "$S.tmp" "$S"
	;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
em0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	status: active
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 1.5
	expect_line_lacks 2 "dn " "throughput: decreased counters show no rate"
	expect_line_contains 3 "dn " "throughput: rate recovers after the reset"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Battery tests
# ------------------------------------------------------------
test_bat_absent() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_no_line_contains "BAT\|AC " "no battery: no BAT/AC field"
	expect_stderr_empty
}

test_bat_on_battery_and_ac() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
case "$1" in
-l) echo 72 ;;
-a) echo 0 ;;
esac
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "BAT 72%" "battery on battery power"
	expect_stderr_empty
}

test_bat_on_ac() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
case "$1" in
-l) echo 93 ;;
-a) echo 1 ;;
esac
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "AC 93%" "charging shows AC state"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Tor tests
# ------------------------------------------------------------
test_tor_absent() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	rm -f "$TESTDIR/rc.d/tor"
	run_bar_tor
	expect_no_line_contains "TOR" "tor absent: no TOR field"
	expect_stderr_empty
}

test_tor_running() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 0
EOF
	mkdir -p "$TESTDIR/rc.d"
	: >"$TESTDIR/rc.d/tor"
	chmod +x "$TESTDIR/rc.d/tor"
	run_bar_tor
	expect_line_contains 1 "TOR" "tor running shows TOR"
	expect_stderr_empty
}

test_tor_stopped() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	mkdir -p "$TESTDIR/rc.d"
	: >"$TESTDIR/rc.d/tor"
	chmod +x "$TESTDIR/rc.d/tor"
	run_bar_tor
	expect_no_line_contains "TOR" "tor stopped shows no TOR"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Markup safety
# ------------------------------------------------------------
test_ssid_markup_passthrough() {
	reset_mocks
	mockcmd sysctl <<'EOF'
#!/bin/sh
case "$*" in
"-n hw.physmem") echo 8589934592 ;;
"-n kern.cp_time") echo "2000 2400 2500 2600 3500" ;;
*) exit 1 ;;
esac
EOF
	mockcmd vmstat <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd apm <<'EOF'
#!/bin/sh
exit 1
EOF
	mockcmd netstat <<'EOF'
#!/bin/sh
case "$*" in
"-rn") echo "default            10.0.0.1             UGS       0     0     -     3 iwm0" ;;
*) exit 1 ;;
esac
EOF
	mockcmd ifconfig <<'EOF'
#!/bin/sh
cat <<'IF'
iwm0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	lladdr aa:bb:cc:dd:ee:ff
	ieee80211: nwid "Evil +@fg=1; Net" chan 1 bssid ff:ee:dd:cc:bb:aa
	status: active
	inet 10.0.0.2 netmask 0xffffff00 broadcast 10.0.0.255
IF
EOF
	mockcmd rcctl <<'EOF'
#!/bin/sh
exit 1
EOF
	run_bar 0.1
	expect_line_contains 1 "Evil +@fg=1; Net" "SSID is passed through verbatim (spectrwm does not expand markup)"
	expect_stderr_empty
}

# ------------------------------------------------------------
# Keyboard layout selection
# ------------------------------------------------------------
test_keyboard_prompt() {
	sed -n '/^ask_keyboard_layout()/,/^}/p' "$SRC/install.ksh" \
		>"$TESTDIR/prompt-fn"
	if ! grep -q '^ask_keyboard_layout()' "$TESTDIR/prompt-fn"; then
		notok "keyboard: could not extract ask_keyboard_layout"
		return
	fi
	cat >"$TESTDIR/prompt.ksh" <<EOF
log() { :; }
error() { exit 1; }
$(cat "$TESTDIR/prompt-fn")
ask_keyboard_layout
print "LAYOUT=\$KEYBOARD_LAYOUT"
EOF
	check_prompt() { # input env expected
		in=$1
		env=$2
		expected=$3
		# the prompt uses print "...\c", so the result may share
		# a line with the prompt text when stdin is piped; grep
		# the LAYOUT= value out instead of matching whole lines
		if [ -n "$env" ]; then
			got=$(print "$in" | KEYBOARD_LAYOUT=$env \
				ksh "$TESTDIR/prompt.ksh" 2>/dev/null |
				grep -o 'LAYOUT=[a-z][a-z]*' | tail -1)
		else
			got=$(print "$in" | env -u KEYBOARD_LAYOUT \
				ksh "$TESTDIR/prompt.ksh" 2>/dev/null |
				grep -o 'LAYOUT=[a-z][a-z]*' | tail -1)
		fi
		[ "$got" = "LAYOUT=$expected" ] || return 1
	}
	if check_prompt "" "" es; then
		ok "keyboard: empty input selects es (default)"
	else
		notok "keyboard: empty input selects es (default)"
	fi
	if check_prompt "1" "" es; then
		ok "keyboard: '1' selects es"
	else
		notok "keyboard: '1' selects es"
	fi
	if check_prompt "2" "" us; then
		ok "keyboard: '2' selects us"
	else
		notok "keyboard: '2' selects us"
	fi
	if check_prompt "es" "" es; then
		ok "keyboard: 'es' selects es"
	else
		notok "keyboard: 'es' selects es"
	fi
	if check_prompt "us" "" us; then
		ok "keyboard: 'us' selects us"
	else
		notok "keyboard: 'us' selects us"
	fi
	if check_prompt "anything" us us; then
		ok "keyboard: KEYBOARD_LAYOUT=us skips the prompt"
	else
		notok "keyboard: KEYBOARD_LAYOUT=us skips the prompt"
	fi
	# invalid interactive input must fail
	if print "3" | env -u KEYBOARD_LAYOUT \
		ksh "$TESTDIR/prompt.ksh" >/dev/null 2>&1; then
		notok "keyboard: invalid interactive input is rejected"
	else
		ok "keyboard: invalid interactive input is rejected"
	fi
	# invalid environment value must fail
	if print "" | KEYBOARD_LAYOUT=xx \
		ksh "$TESTDIR/prompt.ksh" >/dev/null 2>&1; then
		notok "keyboard: invalid environment value is rejected"
	else
		ok "keyboard: invalid environment value is rejected"
	fi
}

test_keyboard_persistence() {
	sed -n '/^apply_keyboard_layout()/,/^}/p' "$SRC/install.ksh" \
		>"$TESTDIR/apply-fn"
	if ! grep -q '^apply_keyboard_layout()' "$TESTDIR/apply-fn"; then
		notok "keyboard: could not extract apply_keyboard_layout"
		return
	fi
	cat >"$TESTDIR/apply.ksh" <<EOF
log() { :; }
warn() { :; }
$(cat "$TESTDIR/apply-fn")
KEYBOARD_LAYOUT=\$1
apply_keyboard_layout
EOF
	cp "$SRC/.xsession.ksh" "$TESTDIR/.xsession"
	HOME=$TESTDIR
	export HOME
	TARGET_USER=$(id -un)
	TARGET_GROUP=$(id -gn)
	export TARGET_USER TARGET_GROUP
	ksh "$TESTDIR/apply.ksh" us
	ksh "$TESTDIR/apply.ksh" us
	if [ "$(grep -c '^KEYBOARD_LAYOUT=' "$TESTDIR/.xsession")" -eq 1 ] &&
		grep -q '^KEYBOARD_LAYOUT=us$' "$TESTDIR/.xsession"; then
		ok "keyboard: repeated install with us stays idempotent"
	else
		notok "keyboard: repeated install with us stays idempotent"
	fi
	ksh "$TESTDIR/apply.ksh" es
	if [ "$(grep -c '^KEYBOARD_LAYOUT=' "$TESTDIR/.xsession")" -eq 1 ] &&
		grep -q '^KEYBOARD_LAYOUT=es$' "$TESTDIR/.xsession" &&
		[ "$(grep -c 'setxkbmap' "$TESTDIR/.xsession")" -eq 2 ]; then
		ok "keyboard: switching to es replaces the line, no duplicates"
	else
		notok "keyboard: switching to es replaces the line, no duplicates"
	fi
	# the generated session script must still be valid ksh
	if ksh -n "$TESTDIR/.xsession"; then
		ok "keyboard: generated .xsession is valid ksh"
	else
		notok "keyboard: generated .xsession is valid ksh"
	fi
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
test_cpu_first_sample_and_delta
test_cpu_zero_delta
test_cpu_counter_reset
test_cpu_malformed_output
test_mem_modern_format
test_mem_small_machine
test_mem_rejects_old_format
test_net_offline
test_net_ipv4_wired
test_net_ipv6_only
test_net_wifi_ssid_with_spaces
test_net_tunnel_fallback
test_traffic_rates
test_traffic_counter_reset
test_bat_absent
test_bat_on_battery_and_ac
test_bat_on_ac
test_tor_absent
test_tor_running
test_tor_stopped
test_ssid_markup_passthrough
test_keyboard_prompt
test_keyboard_persistence

print ""
print "passed: $PASSES"
print "failed: $FAILS"
[ "$FAILS" -eq 0 ]
