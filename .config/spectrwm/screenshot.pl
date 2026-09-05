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
# Sandbox (OpenBSD only, via base OpenBSD::Pledge/OpenBSD::Unveil):
#   unveil    scrot(1), optionally notify-send(1), the target
#             directory, the Xauthority file, the X server
#             socket, the dynamic linker and the shared
#             libraries (including /usr/local/lib for the
#             scrot dependencies).
#   pledge    "proc exec" (plus implied stdio); the scrot child
#             runs unpledged and does the X11 and file work
#             itself. Directory creation and timestamp
#             formatting happen before the sandbox. A sandbox
#             misconfiguration kills the script with an explicit
#             error; diagnose with ktrace(1) or the 'U' flag in
#             lastcomm(1).
#
# The X server is assumed to listen on the local unix socket
# (/tmp/.X11-unix); a remote DISPLAY (TCP) will not work under
# the sandbox, which matches the default xenodm setup.
#
# See the LICENSE file at the top of the project tree for
# copyright and license details.

use strict;
use warnings;
use POSIX qw(strftime);
use File::Basename qw(basename);
use File::Path qw(make_path);
use if $^O eq 'openbsd', 'OpenBSD::Pledge';
use if $^O eq 'openbsd', 'OpenBSD::Unveil';

my $scrot  = '/usr/local/bin/scrot';
my $notify = '/usr/local/bin/notify-send';

my $dir = ($ENV{HOME} // '') . '/Pictures/Screenshots';
my $mode = @ARGV ? $ARGV[0] : 'full';

if ($mode ne 'full' && $mode ne 'window') {
    print STDERR "Usage: ", basename($0), " [full|window]\n";
    exit 1;
}

if (!-x $scrot) {
    print STDERR "scrot is required but not found at $scrot\n";
    exit 1;
}

# All filesystem and timezone access happens before the sandbox.
make_path($dir);
my $stamp = strftime('%Y-%m-%d_%H-%M-%S', localtime);
my $outfile = "${dir}/screenshot_${mode}_${stamp}.png";
my $have_notify = -x $notify;
my $have_local_lib = -d '/usr/local/lib';

# Locate the Xauthority file before restricting the filesystem.
my $xauthority;
if (defined $ENV{XAUTHORITY} && $ENV{XAUTHORITY} ne '') {
    $xauthority = $ENV{XAUTHORITY};
} elsif (-e ($ENV{HOME} // '') . '/.Xauthority') {
    $xauthority = ($ENV{HOME} // '') . '/.Xauthority';
}

if ($^O eq 'openbsd') {
    unveil($scrot, 'x') or die "unveil scrot: $!";
    if ($have_notify) {
        unveil($notify, 'x') or die "unveil notify-send: $!";
    }
    unveil($dir, 'rwc') or die "unveil $dir: $!";
    if (defined $xauthority) {
        unveil($xauthority, 'r') or die "unveil xauthority: $!";
    }
    unveil('/tmp/.X11-unix', 'w') or die "unveil X socket dir: $!";
    unveil('/usr/libexec/ld.so', 'rx') or die "unveil ld.so: $!";
    unveil('/usr/lib', 'r')       or die "unveil /usr/lib: $!";
    unveil('/usr/X11R6/lib', 'r') or die "unveil /usr/X11R6/lib: $!";
    if ($have_local_lib) {
        unveil('/usr/local/lib', 'r') or die "unveil /usr/local/lib: $!";
    }
    unveil() or die "unable to lock unveil: $!";
    pledge('proc', 'exec') or die "unable to pledge: $!";
}

my @args = ('-m', $outfile);
if ($mode eq 'window') {
    # brief pause to allow selection to start cleanly
    sleep 0.2;
    @args = ('-s', $outfile);
}

my $rc = system($scrot, @args);
if ($rc != 0) {
    exit($rc == -1 ? 1 : $rc >> 8);
}

if ($have_notify) {
    system($notify, 'Screenshot saved', $outfile);
}

print "Saved: $outfile\n";
