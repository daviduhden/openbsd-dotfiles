#!/usr/bin/perl
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
# All values come from OpenBSD base utilities; their output is
# parsed here in Perl. Missing hardware or services are omitted
# silently; the output is plain ASCII.
#
# Only the status line is written to stdout; all expected
# command failures are handled at their source so that
# diagnostics never reach the bar.
#
# Sandbox (OpenBSD only, via base OpenBSD::Pledge/OpenBSD::Unveil):
#   unveil    the data-gathering tools and the files needed by
#             the rcctl(8) Tor check chain, the dynamic linker
#             and the shared libraries; locked before the loop.
#   pledge    "proc exec" (plus implied stdio). Children run
#             unpledged, so no network/route promises are needed
#             in this process. A sandbox misconfiguration kills
#             the script with an explicit error instead of being
#             silently ignored; diagnose with ktrace(1) or the
#             'U' flag in lastcomm(1).
#
# Optional arguments, useful for testing and manual runs:
#   statusbar.pl [iterations]      limit the number of cycles
#   STATUSBAR_INTERVAL=seconds     override the 2-second cycle
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;
use POSIX ();
use if $^O eq 'openbsd', 'OpenBSD::Pledge';
use if $^O eq 'openbsd', 'OpenBSD::Unveil';

$SIG{PIPE} = 'DEFAULT';    # exit when spectrwm closes the pipe
$| = 1;                    # flush every line immediately

$ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';

my $interval = 2;
if (defined $ENV{STATUSBAR_INTERVAL}
    && $ENV{STATUSBAR_INTERVAL} =~ /^(\d+(?:\.\d+)?)$/) {
    $interval = $1;
    $interval = 2 if $interval <= 0;
}

my $max_iterations = 0;
if (@ARGV && $ARGV[0] =~ /^\d+$/) {
    $max_iterations = $ARGV[0];
}

my $is_openbsd = ((POSIX::uname())[0] // '') eq 'OpenBSD';

# Absolute paths to the data-gathering tools.
my %CMD = (
    sysctl   => '/sbin/sysctl',
    vmstat   => '/usr/bin/vmstat',
    apm      => '/usr/sbin/apm',
    netstat  => '/usr/bin/netstat',
    ifconfig => '/sbin/ifconfig',
    rcctl    => '/usr/sbin/rcctl',
);

# /dev/null is opened before the sandbox; children dup2() this
# descriptor to discard stdout/stderr without opening files.
open my $null_fh, '<', '/dev/null' or die "cannot open /dev/null: $!";

if ($^O eq 'openbsd') {
    # data-gathering tools (executed every cycle)
    unveil($CMD{sysctl},   'x')  or die "unveil sysctl: $!";
    unveil($CMD{vmstat},   'x')  or die "unveil vmstat: $!";
    unveil($CMD{apm},      'x')  or die "unveil apm: $!";
    unveil($CMD{netstat},  'x')  or die "unveil netstat: $!";
    unveil($CMD{ifconfig}, 'x')  or die "unveil ifconfig: $!";
    # apm(8) talks to apmd(8) and falls back to /dev/apm
    unveil('/var/run/apmdev', 'w') or die "unveil apmdev: $!";
    unveil('/dev/apm', 'r')        or die "unveil /dev/apm: $!";
    # Tor check chain: rcctl(8) is a ksh script that sources
    # rc.subr, parses rc.conf, validates the action with grep(1)
    # and id(1), and runs /etc/rc.d/tor which execs pgrep(1)
    unveil($CMD{rcctl},     'rx') or die "unveil rcctl: $!";
    unveil('/bin/ksh',      'x')  or die "unveil ksh: $!";
    unveil('/etc/rc.d/tor', 'rx') or die "unveil rc.d/tor: $!";
    unveil('/etc/rc.d/rc.subr', 'r') or die "unveil rc.subr: $!";
    unveil('/etc/rc.conf',  'r')  or die "unveil rc.conf: $!";
    unveil('/etc/rc.conf.local', 'r') or die "unveil rc.conf.local: $!";
    unveil('/usr/bin/grep', 'x')  or die "unveil grep: $!";
    unveil('/usr/bin/id',   'x')  or die "unveil id: $!";
    unveil('/usr/bin/pgrep', 'x') or die "unveil pgrep: $!";
    # dynamically linked children need the linker and the
    # shared libraries (versioned names, so the directory)
    unveil('/usr/libexec/ld.so', 'rx') or die "unveil ld.so: $!";
    unveil('/usr/lib', 'r') or die "unveil /usr/lib: $!";
    unveil() or die "unable to lock unveil: $!";
    pledge('proc', 'exec') or die "unable to pledge: $!";
}

# This script runs no X11 clients; keep the children away from
# the display.
delete $ENV{DISPLAY};
delete $ENV{XAUTHORITY};

# State held across iterations (CPU baseline and throughput
# counters stay in this process; no temporary files).
my ($cpu_total, $cpu_idle, $cpu_have_prev) = (0, 0, 0);
my $traffic_iface;
my $traffic_prev_iface;
my ($traffic_rx, $traffic_tx, $traffic_time);

# Run a command without a shell, capturing its standard output.
# The command's stderr is discarded: the failures are expected
# (missing hardware, unset interfaces) and must not reach the
# X session log on every cycle. Returns undef when the command
# cannot be executed.
sub run_capture {
    my ($cmd) = @_;
    my $pid = open(my $fh, '-|');
    return unless defined $pid;
    if ($pid == 0) {
        open STDERR, '>&', $null_fh or exit 1;
        exec @$cmd;
        exit 1;
    }
    my $out = do { local $/; <$fh> };
    close $fh;
    chomp($out);
    return $out;
}

# --- CPU usage, from kern.cp_time deltas -------------------
# cp_time lists the CPU ticks per state (user nice sys [spin]
# intr idle); all states are summed and the last one is idle,
# which keeps the parse valid across OpenBSD versions that
# added states. The first sample and counter resets are not
# displayed instead of showing a bogus percentage.
sub get_cpu {
    return unless $is_openbsd;
    my $out = run_capture([ $CMD{sysctl}, '-n', 'kern.cp_time' ]);
    return unless defined $out;
    my @v = split(' ', $out);
    return unless @v >= 5;
    for (@v) {
        return unless /^\d+$/;
    }
    my $total = 0;
    $total += $_ for @v;
    my $idle = $v[-1];
    my $field;
    if ($cpu_have_prev && $total >= $cpu_total
        && $idle >= $cpu_idle && $total > $cpu_total) {
        my $pct = sprintf('%.0f', 100 *
            ($total - $cpu_total - ($idle - $cpu_idle)) /
            ($total - $cpu_total));
        $field = "CPU ${pct}%";
    }
    $cpu_total = $total;
    $cpu_idle = $idle;
    $cpu_have_prev = 1;
    return $field;
}

# --- Memory usage, as used/total ---------------------------
# vmstat prints the free-list size in the "fre" column, in MB
# with an 'M' suffix; the column is located through the header
# so the parse survives layout changes, and the suffix is
# required so that other formats are rejected instead of being
# misread. used = total - free, which includes the file cache.
sub get_mem {
    return unless $is_openbsd;
    my $total = run_capture([ $CMD{sysctl}, '-n', 'hw.physmem' ]);
    return unless defined $total && $total =~ /^(\d+)$/;
    $total = $1;
    my $vm = run_capture([ $CMD{vmstat} ]);
    return unless defined $vm;
    my @lines = split("\n", $vm);
    return unless @lines >= 3;
    my @hdr = split(' ', $lines[1]);
    my ($col, $i) = (undef, 0);
    for my $name (@hdr) {
        if ($name eq 'fre') {
            $col = $i;
            last;
        }
        $i++;
    }
    return unless defined $col;
    my @data = split(' ', $lines[2]);
    my $fre = $data[$col];
    return unless defined $fre && $fre =~ /^(\d+)M$/;
    $fre = $1;
    my $tmb = $total / 1048576;
    return if $fre >= $tmb;
    my $umb = $tmb - $fre;
    if ($tmb >= 1024) {
        return sprintf('MEM %.1fG/%.0fG', $umb / 1024, $tmb / 1024);
    }
    return sprintf('MEM %.0fM/%.0fM', $umb, $tmb);
}

# --- Battery / AC state (apm) ------------------------------
# apm has no combined flag for level and AC state, so two calls
# are used; both run only every fifth cycle.
sub get_bat {
    my $pct = run_capture([ $CMD{apm}, '-l' ]);
    return unless defined $pct && $pct =~ /^(\d{1,3})$/;
    $pct = $1;
    return if $pct > 100;
    my $ac = run_capture([ $CMD{apm}, '-a' ]);
    return "AC ${pct}%" if defined $ac && $ac eq '1';
    return "BAT ${pct}%";
}

# --- Network: active interface, SSID and address -----------
# The interface carrying the default route is preferred. If the
# default route points through a tunnel-like interface (VPN),
# a physical interface is shown instead; when there is no
# default route at all, the first interface that reports
# "status: active" is used.
sub first_active_iface {
    my $out = run_capture([ $CMD{ifconfig} ]);
    return unless defined $out;
    my ($name, $active) = (undef, 0);
    for my $line (split("\n", $out)) {
        if ($line =~ /^([a-zA-Z][a-zA-Z0-9]*):/) {
            return $name if $active && $name ne 'lo0';
            ($name, $active) = ($1, 0);
        } elsif ($line =~ /status: active/) {
            $active = 1;
        }
    }
    return ($active && $name ne 'lo0') ? $name : undef;
}

sub get_net {
    my $iface;
    my $routes = run_capture([ $CMD{netstat}, '-rn' ]);
    if (defined $routes) {
        for my $line (split("\n", $routes)) {
            if ($line =~ /^default\s/) {
                my @f = split(' ', $line);
                $iface = $f[-1];
                last;
            }
        }
    }
    if (!defined $iface
        || $iface =~ /^(?:lo|enc|pflog|tun|tap|wg|ppp|gif|gre|pair)/) {
        $iface = undef;
    }
    $iface = first_active_iface() unless defined $iface;
    return unless defined $iface;

    my $info = run_capture([ $CMD{ifconfig}, $iface ]);
    return unless defined $info;

    my ($ip, $ssid);
    for my $line (split("\n", $info)) {
        if (!defined $ip && $line =~ /^\s*inet (\S+)/) {
            # primary IPv4 address
            $ip = $1;
        } elsif (!defined $ip && $line =~ /^\s*inet6 (\S+)/
            && $1 !~ /^fe80:/ && $1 ne '::1') {
            # on IPv6-only links, the first global IPv6 address
            $ip = $1;
        } elsif (!defined $ssid && $line =~ /^\s*ieee80211:/
            && $line =~ / (?:nwid|join) ("[^"]*"|\S+)/) {
            # associated nwid; ifconfig quotes names with spaces
            $ssid = $1;
            $ssid =~ s/^"//;
            $ssid =~ s/"$//;
        }
    }
    my $field = "NET $iface "
        . ($ssid ? "$ssid " : '')
        . (defined $ip ? $ip : 'no ip');
    return { field => $field, iface => $iface };
}

# --- Network throughput, from interface byte counters ------
# netstat -nib prints the link row with "Ibytes Obytes" as the
# last two columns. The deltas are computed against the previous
# sample held in memory; counter resets and interface changes
# restart the baseline.
sub rate {
    my ($n) = @_;
    my ($d, $u);
    if ($n >= 1073741824) {
        ($d, $u) = (1073741824, 'G');
    } elsif ($n >= 1048576) {
        ($d, $u) = (1048576, 'M');
    } elsif ($n >= 1024) {
        ($d, $u) = (1024, 'K');
    } else {
        return sprintf('%dB', int($n));
    }
    my $v = $n / $d;
    return sprintf('%d%s', int($v + 0.5), $u) if $v >= 10;
    return sprintf('%d%s', int($v), $u) if $v == int($v);
    return sprintf('%.1f%s', $v, $u);
}

sub get_traffic {
    return unless defined $traffic_iface;
    if (defined $traffic_rx && $traffic_prev_iface ne $traffic_iface) {
        $traffic_rx = $traffic_tx = $traffic_time = undef;
    }
    my $now = time();
    my $out = run_capture([ $CMD{netstat}, '-nib', '-I', $traffic_iface ]);
    return unless defined $out;
    my @lines = split("\n", $out);
    return unless @lines >= 2;
    my @f = split(' ', $lines[1]);
    return unless @f == 6 && $f[4] =~ /^\d+$/ && $f[5] =~ /^\d+$/;
    my ($rx, $tx) = ($f[4], $f[5]);
    my $field;
    if (defined $traffic_rx && $now > $traffic_time
        && $rx >= $traffic_rx && $tx >= $traffic_tx) {
        my $elapsed = $now - $traffic_time;
        $field = 'dn ' . rate(($rx - $traffic_rx) / $elapsed)
            . ' up ' . rate(($tx - $traffic_tx) / $elapsed);
    }
    $traffic_rx = $rx;
    $traffic_tx = $tx;
    $traffic_time = $now;
    $traffic_prev_iface = $traffic_iface;
    return $field;
}

# --- Tor daemon state --------------------------------------
# rcctl check tor works unprivileged; when the package is
# absent it fails and its stderr is discarded by the child's
# /dev/null redirect, so no existence check is needed here (a
# stat(2) would additionally require the rpath promise).
sub service_running {
    my ($svc) = @_;
    my $pid = open(my $fh, '-|');
    return 0 unless defined $pid;
    if ($pid == 0) {
        open STDOUT, '>&', $null_fh or exit 1;
        open STDERR, '>&', $null_fh or exit 1;
        exec $CMD{rcctl}, 'check', $svc;
        exit 1;
    }
    1 while <$fh>;
    close $fh;
    return $? == 0;
}

my $cycle = 0;
while (1) {
    my @fields;
    ++$cycle;

    my $cpu = get_cpu();
    push @fields, $cpu if defined $cpu && $cpu ne '';

    if ($cycle % 5 == 1) {
        my $mem = get_mem();
        push @fields, $mem if defined $mem;
        my $bat = get_bat();
        push @fields, $bat if defined $bat;
        my $net = get_net();
        if ($net) {
            push @fields, $net->{field};
            $traffic_iface = $net->{iface};
        } else {
            push @fields, 'NET offline';
            $traffic_iface = undef;
        }
    }

    my $traffic = get_traffic();
    push @fields, $traffic if defined $traffic && $traffic ne '';

    push @fields, 'TOR' if $cycle % 15 == 1 && service_running('tor');

    print join('  ', @fields), "\n";

    last if $max_iterations && $cycle >= $max_iterations;
    sleep $interval;
}
