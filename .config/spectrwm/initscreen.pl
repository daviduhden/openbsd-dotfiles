#!/usr/bin/perl
#
# Screen setup script for spectrwm
# This script is called by spectrwm on startup to configure
# connected displays using xrandr.
#
# It sets up one internal display and one external display
# (if connected) side by side.
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;

my @candidates = qw(eDP eDP-1 eDP-0 LVDS LVDS-1 LVDS-0);

# Exit silently when xrandr is unavailable.
my $out;
open my $fh, '-|', 'xrandr', '--query' or exit 0;
{
    local $/;
    $out = <$fh>;
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

system('xrandr', '--output', $internal, '--auto');

if (defined $external) {
    system('xrandr', '--output', $external, '--auto',
        '--right-of', $internal);
}
