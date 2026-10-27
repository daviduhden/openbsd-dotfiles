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
#   every cycle    CPU usage, audio volume, network throughput
#   every 5th      memory, battery/AC state, network state
#   every 15th     Tor state
#
# The line contains, in order: CPU usage, audio volume, memory
# usage, battery or AC state, network state, network throughput
# and Tor status.
# Each field starts with a single-codepoint emoji (no ZWJ, no
# variation selectors) so spectrwm's per-character Xft fallback
# can select Noto Color Emoji reliably. All values come from
# OpenBSD base utilities; their output is parsed here in Perl.
# Missing hardware or services are omitted silently.
#
# Only the status line is written to stdout; all expected
# command failures are handled at their source so that
# diagnostics never reach the bar.
#
# Sandbox (OpenBSD only, via base OpenBSD::Unveil):
#   unveil    the data-gathering tools and the files needed by
#             the rcctl(8) Tor check chain, the sndiod(8) control
#             sockets and session cookie, the dynamic linker and
#             the shared libraries; locked before the loop.
#   The launcher stays unpledged because it executes external programs.
#   The locked view is inherited across execve(2); children need the
#   unveiled library paths and may apply their own pledge policy.
#
# Optional arguments, useful for testing and manual runs:
#   statusbar.pl [iterations]      limit the number of cycles
#   STATUSBAR_INTERVAL=seconds     override the 2-second cycle
#   STATUSBAR_BATTERY_LOW=percent  low-battery threshold (default 15)
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;
use POSIX ();
use if $^O eq 'openbsd', 'OpenBSD::Unveil';

$SIG{PIPE} = 'DEFAULT';    # exit when spectrwm closes the pipe
$| = 1;                    # flush every line immediately

$ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';

my $interval = 2;
if ( defined $ENV{STATUSBAR_INTERVAL}
    && $ENV{STATUSBAR_INTERVAL} =~ /^(\d+(?:\.\d+)?)$/ )
{
    $interval = $1;
    $interval = 2 if $interval <= 0;
}

my $low_battery = 15;
if ( defined $ENV{STATUSBAR_BATTERY_LOW}
    && $ENV{STATUSBAR_BATTERY_LOW} =~ /^(\d{1,3})$/ )
{
    $low_battery = $1;
    $low_battery = 100 if $low_battery > 100;
}

my $max_iterations = 0;
if ( @ARGV && $ARGV[0] =~ /^\d+$/ ) {
    $max_iterations = $ARGV[0];
}

my $is_openbsd = ( ( POSIX::uname() )[0] // '' ) eq 'OpenBSD';

# Absolute paths to the data-gathering tools.
my %CMD = (
    sysctl   => '/sbin/sysctl',
    vmstat   => '/usr/bin/vmstat',
    apm      => '/usr/sbin/apm',
    netstat  => '/usr/bin/netstat',
    ifconfig => '/sbin/ifconfig',
    rcctl    => '/usr/sbin/rcctl',
    sndioctl => '/usr/bin/sndioctl',
);

# /dev/null is opened before the sandbox; children dup2() this
# descriptor to discard stdout/stderr without opening files, so it
# deliberately lives for the whole process.
open my $null_fh, '<', '/dev/null'    ## no critic (RequireBriefOpen)
  or die "cannot open /dev/null: $!";

# The sndio session cookie lives in ~/.sndio. The directory is
# created private to the user (0700) here, before the first unveil(2)
# restricts the filesystem view: unveiling it afterwards as a
# directory makes the rule cover the cookie inside it. Left undef
# when there is no HOME to build the path from.
my $sndio_dir;
if ( $^O eq 'openbsd' && defined $ENV{HOME} && length $ENV{HOME} ) {
    $sndio_dir = "$ENV{HOME}/.sndio";
    mkdir $sndio_dir, 0700 unless -d $sndio_dir;
}

if ( $^O eq 'openbsd' ) {

    # data-gathering tools (executed every cycle)
    unveil( $CMD{sysctl},   'x' ) or die "unveil sysctl: $!";
    unveil( $CMD{vmstat},   'x' ) or die "unveil vmstat: $!";
    unveil( $CMD{apm},      'x' ) or die "unveil apm: $!";
    unveil( $CMD{netstat},  'x' ) or die "unveil netstat: $!";
    unveil( $CMD{ifconfig}, 'x' ) or die "unveil ifconfig: $!";

    # apm(8) talks to apmd(8) and falls back to /dev/apm
    unveil( '/var/run/apmdev', 'w' ) or die "unveil apmdev: $!";
    unveil( '/dev/apm',        'r' ) or die "unveil /dev/apm: $!";

    # sndioctl(1) controls the audio device through sndiod(8): the
    # connection is a Unix socket in /tmp/sndio (system server) or
    # /tmp/sndio-<euid> (per-user server), and the session cookie is
    # read from, and created in, ~/.sndio. connect(2) to the sockets
    # needs 'w' on their directory. $sndio_dir was created above,
    # before the first unveil(2) restricted the filesystem view, so
    # the rule covers the cookie inside it.
    unveil( $CMD{sndioctl},  'x' ) or die "unveil sndioctl: $!";
    unveil( '/tmp/sndio',    'w' ) or die "unveil /tmp/sndio: $!";
    unveil( "/tmp/sndio-$>", 'w' ) or die "unveil per-user sndio socket: $!";
    if ( defined $sndio_dir ) {
        unveil( $sndio_dir, 'rwc' ) or die "unveil .sndio: $!";
    }

    # Tor check chain: rcctl(8) is a ksh script that sources
    # rc.subr, parses rc.conf, validates the action with grep(1)
    # and id(1), and runs /etc/rc.d/tor which execs pgrep(1)
    unveil( $CMD{rcctl},          'rx' ) or die "unveil rcctl: $!";
    unveil( '/bin/ksh',           'x' )  or die "unveil ksh: $!";
    unveil( '/etc/rc.d/tor',      'rx' ) or die "unveil rc.d/tor: $!";
    unveil( '/etc/rc.d/rc.subr',  'r' )  or die "unveil rc.subr: $!";
    unveil( '/etc/rc.conf',       'r' )  or die "unveil rc.conf: $!";
    unveil( '/etc/rc.conf.local', 'r' )  or die "unveil rc.conf.local: $!";
    unveil( '/usr/bin/grep',      'x' )  or die "unveil grep: $!";
    unveil( '/usr/bin/id',        'x' )  or die "unveil id: $!";
    unveil( '/usr/bin/pgrep',     'x' )  or die "unveil pgrep: $!";

    # dynamically linked children need the linker and the
    # shared libraries (versioned names, so the directory)
    unveil( '/usr/libexec/ld.so', 'rx' ) or die "unveil ld.so: $!";
    unveil( '/usr/lib',           'r' )  or die "unveil /usr/lib: $!";
    unveil() or die "unable to lock unveil: $!";
}

# This script runs no X11 clients; keep the children away from
# the display.
delete $ENV{DISPLAY};
delete $ENV{XAUTHORITY};

# State held across iterations (CPU baseline and throughput
# counters stay in this process; no temporary files).
my ( $cpu_total, $cpu_idle, $cpu_have_prev ) = ( 0, 0, 0 );
my $traffic_iface;
my $traffic_prev_iface;
my ( $traffic_rx, $traffic_tx, $traffic_time );

# Run a command without a shell, capturing its standard output.
# The command's stderr is discarded: the failures are expected
# (missing hardware, unset interfaces) and must not reach the
# X session log on every cycle. Returns undef when the command
# cannot be executed or exits unsuccessfully.
sub run_capture {
    my ($cmd) = @_;
    my $pid = open( my $fh, '-|' );
    return unless defined $pid;
    if ( $pid == 0 ) {
        open STDIN,  '<&', $null_fh or exit 1;
        open STDERR, '>&', $null_fh or exit 1;
        exec @{$cmd};
        exit 1;
    }
    my $out = do { local $/ = undef; <$fh> };
    close $fh or return;
    chomp $out;
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
    my $out = run_capture( [ $CMD{sysctl}, '-n', 'kern.cp_time' ] );
    return unless defined $out;
    my @v = split( ' ', $out );
    return if @v < 5;
    for (@v) {
        return unless /^\d+$/;
    }
    my $total = 0;
    $total += $_ for @v;
    my $idle = $v[-1];
    my $field;
    if (   $cpu_have_prev
        && $total >= $cpu_total
        && $idle >= $cpu_idle
        && $total > $cpu_total )
    {
        my $pct = sprintf( '%.0f',
            100 * ( $total - $cpu_total - ( $idle - $cpu_idle ) ) /
              ( $total - $cpu_total ) );
        $field = "🖥 ${pct}%";
    }
    $cpu_total     = $total;
    $cpu_idle      = $idle;
    $cpu_have_prev = 1;
    return $field;
}

# --- Audio volume, from sndioctl ---------------------------
# sndioctl(1) is the unprivileged sndio(7) control utility
# (mixerctl(8) is root-only for the common controls since
# OpenBSD 6.7). The level is a 0..1 fraction printed with three
# decimals; the mute switch is a separate 0/1 control, so the
# whole control list is read in one call and both lines are
# picked out by name. A missing sndiod(8) or audio hardware
# makes the call fail and the field is omitted. The icon
# reflects the mute state and, when unmuted, the level.
sub get_volume {
    my $out = run_capture( [ $CMD{sndioctl} ] );
    return unless defined $out;
    my ( $level, $mute );
    for my $line ( split /\n/, $out ) {
        if ( $line =~ /^output\.level=(\d+(?:\.\d+)?)/ ) {
            $level = $1;
        }
        elsif ( $line =~ /^output\.mute=(\d+)/ ) {
            $mute = $1;
        }
    }
    return unless defined $level;
    return if $level > 1;
    my $icon;
    if ($mute) {
        $icon = '🔇';
    }
    elsif ( $level < 0.34 ) {
        $icon = '🔈';
    }
    elsif ( $level < 0.67 ) {
        $icon = '🔉';
    }
    else {
        $icon = '🔊';
    }
    return sprintf( '%s %.0f%%', $icon, $level * 100 );
}

# --- Memory usage, as used/total ---------------------------
# vmstat prints the free-list size in the "fre" column, in MB
# with an 'M' suffix; the column is located through the header
# so the parse survives layout changes, and the suffix is
# required so that other formats are rejected instead of being
# misread. used = total - free, which includes the file cache.
sub get_mem {
    return unless $is_openbsd;
    my $total = run_capture( [ $CMD{sysctl}, '-n', 'hw.physmem' ] );
    return unless defined $total && $total =~ /^(\d+)$/;
    $total = $1;
    my $vm = run_capture( [ $CMD{vmstat} ] );
    return unless defined $vm;
    my @lines = split( /\n/, $vm );
    return if @lines < 3;
    my @hdr = split( ' ', $lines[1] );
    my ( $col, $i ) = ( undef, 0 );

    for my $name (@hdr) {
        if ( $name eq 'fre' ) {
            $col = $i;
            last;
        }
        $i++;
    }
    return unless defined $col;
    my @data = split( ' ', $lines[2] );
    my $fre  = $data[$col];
    return unless defined $fre && $fre =~ /^(\d+)M$/;
    $fre = $1;
    my $tmb = $total / 1_048_576;
    return if $fre >= $tmb;
    my $umb = $tmb - $fre;

    if ( $tmb >= 1024 ) {
        return sprintf( '🧠 %.1fG/%.0fG', $umb / 1024, $tmb / 1024 );
    }
    return sprintf( '🧠 %.0fM/%.0fM', $umb, $tmb );
}

# --- Battery / AC state (apm) ------------------------------
# apm has no combined flag for level and AC state, so two calls
# are used; both run only every fifth cycle.
sub get_bat {
    my $pct = run_capture( [ $CMD{apm}, '-l' ] );
    return unless defined $pct && $pct =~ /^(\d{1,3})$/;
    $pct = $1;
    return if $pct > 100;
    my $ac = run_capture( [ $CMD{apm}, '-a' ] );
    return "🔌 ${pct}%" if defined $ac && $ac eq '1';
    return "🪫 ${pct}%" if $pct <= $low_battery;
    return "🔋 ${pct}%";
}

# --- Network: active interface, SSID and address -----------
# The interface carrying the default route is preferred. If the
# default route points through a tunnel-like interface (VPN),
# a physical interface is shown instead; when there is no
# default route at all, the first interface that reports
# "status: active" is used.
sub first_active_iface {
    my $out = run_capture( [ $CMD{ifconfig} ] );
    return unless defined $out;
    my ( $name, $active ) = ( undef, 0 );
    for my $line ( split( /\n/, $out ) ) {
        if ( $line =~ /^([a-zA-Z][a-zA-Z0-9]*):/ ) {
            return $name if $active && defined $name && $name ne 'lo0';
            ( $name, $active ) = ( $1, 0 );
        }
        elsif ( $line =~ /status: active/ ) {
            $active = 1;
        }
    }
    return ( $active && defined $name && $name ne 'lo0' ) ? $name : undef;
}

sub get_net {
    my $iface;
    my $routes = run_capture( [ $CMD{netstat}, '-rn' ] );
    if ( defined $routes ) {
        for my $line ( split( /\n/, $routes ) ) {
            if ( $line =~ /^default\s/ ) {
                my @f = split( ' ', $line );
                $iface = $f[-1];
                last;
            }
        }
    }
    if ( !defined $iface
        || $iface =~ /^(?:lo|enc|pflog|tun|tap|wg|ppp|gif|gre|pair)/ )
    {
        $iface = undef;
    }
    $iface = first_active_iface() unless defined $iface;
    return                        unless defined $iface;

    my $info = run_capture( [ $CMD{ifconfig}, $iface ] );
    return unless defined $info;

    my ( $ip, $ssid );
    for my $line ( split( /\n/, $info ) ) {
        if ( !defined $ip && $line =~ /^\s*inet (\S+)/ ) {

            # primary IPv4 address
            $ip = $1;
        }
        elsif ( !defined $ip
            && $line =~ /^\s*inet6 (\S+)/
            && $1    !~ /^fe80:/
            && $1 ne '::1' )
        {
            # on IPv6-only links, the first global IPv6 address
            $ip = $1;
        }
        elsif ( !defined $ssid
            && $line =~ /^\s*ieee80211:/
            && $line =~ / (?:nwid|join) ("[^"]*"|\S+)/ )
        {
            # associated nwid; ifconfig quotes names with spaces
            $ssid = $1;
            $ssid =~ s/^"//;
            $ssid =~ s/"$//;
        }
    }
    my $field =
        ( defined $ssid ? '📶' : '🔗' )
      . " $iface "
      . ( defined $ssid ? "$ssid " : '' )
      . ( defined $ip   ? $ip      : 'no ip' );
    return { field => $field, iface => $iface };
}

# --- Network throughput, from interface byte counters ------
# netstat -nib prints a header row with named columns and one or
# more data rows per interface. Locate Ibytes/Obytes by header
# name instead of assuming a fixed column count, then prefer the
# <Link> row. The deltas are computed against the previous sample
# held in memory; counter resets and interface changes restart the
# baseline.
sub rate {

    # Format a byte-per-second rate with binary K/M/G thresholds. Values
    # below 10 retain one decimal when needed; larger values round to an
    # integer to keep the native bar compact.
    my ($n) = @_;
    my ( $d, $u );
    if ( $n >= 1_073_741_824 ) {
        ( $d, $u ) = ( 1_073_741_824, 'G' );
    }
    elsif ( $n >= 1_048_576 ) {
        ( $d, $u ) = ( 1_048_576, 'M' );
    }
    elsif ( $n >= 1024 ) {
        ( $d, $u ) = ( 1024, 'K' );
    }
    else {
        return sprintf( '%dB', int($n) );
    }
    my $v = $n / $d;
    return sprintf( '%d%s',   int( $v + 0.5 ), $u ) if $v >= 10;
    return sprintf( '%d%s',   int($v),         $u ) if $v == int($v);
    return sprintf( '%.1f%s', $v,              $u );
}

sub get_traffic {
    return unless defined $traffic_iface;
    if ( defined $traffic_rx && $traffic_prev_iface ne $traffic_iface ) {
        $traffic_rx = $traffic_tx = $traffic_time = undef;
    }
    my $now = time();
    my $out = run_capture( [ $CMD{netstat}, '-nib', '-I', $traffic_iface ] );
    return unless defined $out;
    my @lines = split( /\n/, $out );
    return if @lines < 2;

    my ( $header, $start );
    for my $i ( 0 .. $#lines ) {
        next
          unless $lines[$i] =~ /\bIbytes\b/
          && $lines[$i] =~ /\bObytes\b/;
        $header = $lines[$i];
        $start  = $i + 1;
        last;
    }
    return unless defined $header && defined $start;

    my @hdr = split( ' ', $header );
    my ( $rx_col, $tx_col );
    for my $i ( 0 .. $#hdr ) {
        $rx_col = $i if $hdr[$i] eq 'Ibytes';
        $tx_col = $i if $hdr[$i] eq 'Obytes';
    }
    return unless defined $rx_col && defined $tx_col;

    my $row;
    for my $i ( $start .. $#lines ) {
        my @f = split( ' ', $lines[$i] );
        next if @f <= $rx_col || @f <= $tx_col;
        if ( !defined $row || ( defined $f[2] && $f[2] eq '<Link>' ) ) {
            $row = \@f;
            last if defined $f[2] && $f[2] eq '<Link>';
        }
    }
    return unless defined $row;

    my ( $rx, $tx ) = ( $row->[$rx_col], $row->[$tx_col] );
    return
         unless defined $rx
      && defined $tx
      && $rx =~ /^\d+$/
      && $tx =~ /^\d+$/;
    my $field;

    if (   defined $traffic_rx
        && $now > $traffic_time
        && $rx >= $traffic_rx
        && $tx >= $traffic_tx )
    {
        my $elapsed = $now - $traffic_time;
        $field = '📥 '
          . rate( ( $rx - $traffic_rx ) / $elapsed ) . ' 📤 '
          . rate( ( $tx - $traffic_tx ) / $elapsed );
    }
    $traffic_rx         = $rx;
    $traffic_tx         = $tx;
    $traffic_time       = $now;
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

    # The handle must stay open while the child is configured and
    # its output is drained; the line-count heuristic flags it.
    my $pid = open( my $fh, '-|' );    ## no critic (RequireBriefOpen)
    return 0 unless defined $pid;
    if ( $pid == 0 ) {
        open STDIN,  '<&', $null_fh or exit 1;
        open STDOUT, '>&', $null_fh or exit 1;
        open STDERR, '>&', $null_fh or exit 1;
        exec $CMD{rcctl}, 'check', $svc;
        exit 1;
    }

    # Drain the pipe; only rcctl's exit status matters.
    while (<$fh>) { }
    close $fh or return 0;
    return $? == 0;
}

my $cycle = 0;
while (1) {
    my @fields;
    ++$cycle;

    my $cpu = get_cpu();
    push @fields, $cpu if defined $cpu && $cpu ne '';

    my $vol = get_volume();
    push @fields, $vol if defined $vol && $vol ne '';

    if ( $cycle % 5 == 1 ) {
        my $mem = get_mem();
        push @fields, $mem if defined $mem;
        my $bat = get_bat();
        push @fields, $bat if defined $bat;
        my $net = get_net();
        if ($net) {
            push @fields, $net->{field};
            $traffic_iface = $net->{iface};
        }
        else {
            push @fields, '❌ offline';
            $traffic_iface = undef;
        }
    }

    my $traffic = get_traffic();
    push @fields, $traffic if defined $traffic && $traffic ne '';

    push @fields, '🧅' if $cycle % 15 == 1 && service_running('tor');

    print join( '  ', @fields ), "\n"
      or exit 1;

    last if $max_iterations && $cycle >= $max_iterations;

    # select(2) keeps fractional STATUSBAR_INTERVAL values working;
    # Perl's sleep() truncates them to whole seconds.
    select undef, undef, undef, $interval;    ## no critic (ProhibitSleepViaSelect)
}
