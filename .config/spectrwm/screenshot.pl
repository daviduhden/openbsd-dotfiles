#!/usr/bin/perl
#
# Simple screenshot script for spectrwm
#
# Usage:
#   screenshot.pl          # Take a full-screen screenshot
#   screenshot.pl full     # Take a full-screen screenshot
#   screenshot.pl window   # Screenshot a selected window/area
#
# Requires 'scrot' to be installed
# Saves screenshots to ~/Pictures/Screenshots/
# Creates the directory if it doesn't exist
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;

use POSIX          qw(strftime);
use File::Basename qw(basename);
use File::Path     qw(make_path);

my $dir  = ( $ENV{HOME} // '' ) . '/Pictures/Screenshots';
my $mode = @ARGV ? $ARGV[0] : 'full';

if ( $mode ne 'full' && $mode ne 'window' ) {
    print STDERR "Usage: ", basename($0), " [full|window]\n";
    exit 1;
}

sub find_in_path {
    my ($prog) = @_;
    for my $dir ( split( /:/, $ENV{PATH} // '' ) ) {
        my $path = "$dir/$prog";
        return $path if -x $path;
    }
    return;
}

my $scrot = find_in_path('scrot');
if ( !defined $scrot ) {
    print STDERR "scrot is required but not found in PATH\n";
    exit 1;
}

make_path($dir);

my $stamp   = strftime( '%Y-%m-%d_%H-%M-%S', localtime );
my $outfile = "${dir}/screenshot_${mode}_${stamp}.png";

my @args = ( '-m', $outfile );
if ( $mode eq 'window' ) {

    # brief pause to allow selection to start cleanly
    sleep 0.2;
    @args = ( '-s', $outfile );
}

my $rc = system( $scrot, @args );
if ( $rc != 0 ) {
    exit( $rc == -1 ? 1 : $rc >> 8 );
}

my $notify = find_in_path('notify-send');
if ( defined $notify ) {
    system( $notify, 'Screenshot saved', $outfile );
}

print "Saved: $outfile\n";
