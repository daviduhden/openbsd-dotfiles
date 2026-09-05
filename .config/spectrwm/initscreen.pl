#!/usr/bin/perl
#
# Screen setup script for spectrwm
# This script is called by spectrwm on startup to configure
# connected displays using xrandr.
#
# It sets up one internal display and one external display
# (if connected) side by side.
#
# Sandbox (OpenBSD only, via base OpenBSD::Pledge/OpenBSD::Unveil):
#   unveil    xrandr(1), the dynamic linker, the shared
#             libraries (X11 lives under /usr/X11R6/lib), the
#             Xauthority file and the X server socket.
#   pledge    "proc exec" (plus implied stdio); the xrandr child
#             runs unpledged and does the socket work itself.
#             A sandbox misconfiguration kills the script with
#             an explicit error; diagnose with ktrace(1) or the
#             'U' flag in lastcomm(1).
#
# The X server is assumed to listen on the local unix socket
# (/tmp/.X11-unix); a remote DISPLAY (TCP) will not work under
# the sandbox, which matches the default xenodm setup.
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;
use if $^O eq 'openbsd', 'OpenBSD::Pledge';
use if $^O eq 'openbsd', 'OpenBSD::Unveil';

my $xrandr = '/usr/X11R6/bin/xrandr';

my @candidates = qw(eDP eDP-1 eDP-0 LVDS LVDS-1 LVDS-0);

# Exit silently when xrandr is unavailable.
exit 0 unless -x $xrandr;

# Locate the Xauthority file before restricting the filesystem.
my $xauthority;
if (defined $ENV{XAUTHORITY} && $ENV{XAUTHORITY} ne '') {
    $xauthority = $ENV{XAUTHORITY};
} elsif (-e ($ENV{HOME} // '') . '/.Xauthority') {
    $xauthority = ($ENV{HOME} // '') . '/.Xauthority';
}

if ($^O eq 'openbsd') {
    unveil($xrandr, 'x') or die "unveil xrandr: $!";
    unveil('/usr/libexec/ld.so', 'rx') or die "unveil ld.so: $!";
    unveil('/usr/lib', 'r')         or die "unveil /usr/lib: $!";
    unveil('/usr/X11R6/lib', 'r')   or die "unveil /usr/X11R6/lib: $!";
    if (defined $xauthority) {
        unveil($xauthority, 'r') or die "unveil xauthority: $!";
    }
    unveil('/tmp/.X11-unix', 'w') or die "unveil X socket dir: $!";
    unveil() or die "unable to lock unveil: $!";
    pledge('proc', 'exec') or die "unable to pledge: $!";
}

my $out;
open my $fh, '-|', $xrandr, '--query' or exit 0;
{
    local $/;
    $out = <$fh> // '';
}
close $fh;

my @connected;
for my $line (split("\n", $out)) {
    push @connected, $1 if $line =~ /^(\S+) connected/;
}
exit 0 unless @connected;

# Prefer common internal panel names first
my $internal;
for my $candidate (@candidates) {
    for my $output (@connected) {
        if ($output eq $candidate) {
            $internal = $candidate;
            last;
        }
    }
    last if defined $internal;
}

# Fall back to the first connected output if no internal match
# was found
$internal = $connected[0] unless defined $internal;

# Choose the first other connected output as external
my $external;
for my $output (@connected) {
    if ($output ne $internal) {
        $external = $output;
        last;
    }
}

system($xrandr, '--output', $internal, '--auto');

if (defined $external) {
    system($xrandr, '--output', $external, '--auto',
        '--right-of', $internal);
}
