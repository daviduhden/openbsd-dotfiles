#!/bin/ksh
#
# Regression tests for the Perl helpers that can be exercised without
# OpenBSD-specific hardware or services:
#
#   * sort-packages.pl: sorting, duplicate removal, comment handling,
#     mode preservation, cleanup and failure reporting.
#   * screenshot.pl: exit-status propagation when scrot fails or is
#     killed (the sandbox is disabled in the test copy so that the fake
#     scrot can run on any platform).
#
# Usage: ksh tests/perl_helpers_test.ksh
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

set -eu

SRC=$(cd "$(dirname "$0")/.." && pwd)
TESTDIR=$(mktemp -d /tmp/perl-helpers-test.XXXXXX) || exit 1
trap 'rm -rf "$TESTDIR"' EXIT INT TERM

PASSES=0
FAILS=0

ok() {
	PASSES=$((PASSES + 1))
	print "ok - $1"
}

notok() {
	FAILS=$((FAILS + 1))
	print "FAIL - $1"
}

check_status() { # expected actual description
	if [ "$1" -eq "$2" ]; then
		ok "$3"
	else
		notok "$3 (expected $1, got $2)"
	fi
}

# ------------------------------------------------------------
# sort-packages.pl
# ------------------------------------------------------------
test_sort_packages() {
	file="$TESTDIR/packages.txt"
	{
		print '# header'
		print '# second'
		print 'zlib'
		print 'bzip2'
		print ''
		print 'zlib'
		print 'alpha'
	} >"$file"
	chmod 640 "$file"

	set +e
	perl "$SRC/sort-packages.pl" "$file" \
		>"$TESTDIR/sort.out" 2>"$TESTDIR/sort.err"
	status=$?
	set -e
	check_status 0 "$status" "sort-packages exits successfully"

	if [ -s "$TESTDIR/sort.err" ]; then
		notok "sort-packages writes no errors"
	else
		ok "sort-packages writes no errors"
	fi

	{
		print '# header'
		print '# second'
		print 'alpha'
		print 'bzip2'
		print 'zlib'
	} >"$TESTDIR/expected"
	if cmp -s "$TESTDIR/expected" "$file"; then
		ok "comments and sorted, de-duplicated entries"
	else
		notok "comments and sorted, de-duplicated entries"
		diff -u "$TESTDIR/expected" "$file" || true
	fi

	mode=$(perl -e 'printf "%o", (stat($ARGV[0]))[2] & oct("7777")' "$file")
	check_status 640 "$mode" "original mode is preserved"

	if [ -z "$(find "$TESTDIR" -name '.packages-*' -print)" ]; then
		ok "no temporary file is left behind"
	else
		notok "no temporary file is left behind"
	fi

	set +e
	perl "$SRC/sort-packages.pl" "$TESTDIR/missing.txt" \
		>"$TESTDIR/missing.out" 2>"$TESTDIR/missing.err"
	status=$?
	set -e
	if [ "$status" -ne 0 ]; then
		ok "missing input is reported as an error"
	else
		notok "missing input is reported as an error"
	fi
	if grep -q 'not found' "$TESTDIR/missing.err"; then
		ok "missing input produces a diagnostic"
	else
		notok "missing input produces a diagnostic"
	fi
}

# ------------------------------------------------------------
# screenshot.pl exit-status handling
# ------------------------------------------------------------
prepare_screenshot() {
	sed \
		-e "s|/usr/local/bin/scrot|$TESTDIR/scrot|" \
		-e "s|/usr/local/bin/notify-send|$TESTDIR/notify-send|" \
		-e "s/\\\$\\^O eq 'openbsd'/0/g" \
		"$SRC/.config/spectrwm/screenshot.pl" >"$TESTDIR/screenshot.pl"
	chmod +x "$TESTDIR/screenshot.pl"
	mkdir -p "$TESTDIR/home"
}

write_scrot() { # shell body
	{
		print '#!/bin/sh'
		print "$1"
	} >"$TESTDIR/scrot"
	chmod +x "$TESTDIR/scrot"
}

run_screenshot() {
	set +e
	HOME="$TESTDIR/home" perl "$TESTDIR/screenshot.pl" "$@" \
		>"$TESTDIR/shot.out" 2>"$TESTDIR/shot.err"
	status=$?
	set -e
}

test_screenshot_status() {
	prepare_screenshot

	write_scrot 'exit 0'
	run_screenshot full
	check_status 0 "$status" "successful screenshot exits 0"
	if grep -q 'Saved:' "$TESTDIR/shot.out"; then
		ok "successful screenshot reports the saved file"
	else
		notok "successful screenshot reports the saved file"
	fi

	write_scrot 'exit 3'
	run_screenshot full
	check_status 3 "$status" "scrot exit status is propagated"
	if grep -q 'Saved:' "$TESTDIR/shot.out"; then
		notok "failed screenshot does not report success"
	else
		ok "failed screenshot does not report success"
	fi

	write_scrot 'kill -TERM $$'
	run_screenshot full
	check_status 143 "$status" "scrot signal is reported as 128+signal"
	if grep -q 'Saved:' "$TESTDIR/shot.out"; then
		notok "signalled screenshot does not report success"
	else
		ok "signalled screenshot does not report success"
	fi

	write_scrot 'exit 0'
	run_screenshot bogus
	check_status 1 "$status" "invalid mode exits 1"
	if grep -q 'Usage:' "$TESTDIR/shot.err"; then
		ok "invalid mode prints usage"
	else
		notok "invalid mode prints usage"
	fi

	set +e
	HOME='' perl "$TESTDIR/screenshot.pl" full \
		>"$TESTDIR/shot.out" 2>"$TESTDIR/shot.err"
	status=$?
	set -e
	check_status 1 "$status" "unset HOME exits 1"
	if grep -q 'HOME is not set' "$TESTDIR/shot.err"; then
		ok "unset HOME is diagnosed"
	else
		notok "unset HOME is diagnosed"
	fi
}

test_sort_packages
test_screenshot_status

print ""
print "passed: $PASSES"
print "failed: $FAILS"
[ "$FAILS" -eq 0 ]
