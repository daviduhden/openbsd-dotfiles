#!/usr/bin/perl
#
# Sort packages.txt alphabetically (comments preserved at top)
# Usage: sort-packages.pl [path/to/packages.txt]
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

use strict;
use warnings;
use File::Basename qw(dirname);
use File::Temp     qw(tempfile);
use Cwd            qw(abs_path);

# Script directory
my $script_path = abs_path($0)
  or die "Cannot resolve script path: $!\n";
my $script_dir = dirname($script_path);

# Packages file
my $pkg_file = $ARGV[0] // "$script_dir/packages.txt";

-f $pkg_file
  or die "packages file not found: $pkg_file\n";

# Read the file in one pass, then close it before doing any
# processing or writing.
my @lines;
{
    open my $in, '<', $pkg_file
      or die "Cannot open $pkg_file: $!\n";
    @lines = <$in>;
    close $in or die "Cannot close $pkg_file: $!\n";
}

my @comments;
my @entries;

for my $line (@lines) {
    chomp $line;    # remove newline for consistent sorting
    if ( $line =~ /^\s*#/ ) {
        push @comments, $line;
    }
    elsif ( $line =~ /\S/ ) {
        push @entries, $line;
    }
}

# Sort entries bytewise (like LC_ALL=C) and remove duplicates
my %seen;
my @sorted_entries = sort { $a cmp $b } grep { !$seen{$_}++ } @entries;

# Write atomically in the same directory and preserve the original
# mode and ownership, including when run as root on a user-owned file.
my $file_mode = ( stat $pkg_file )[2];
my $file_uid  = ( stat $pkg_file )[4];
my $file_gid  = ( stat $pkg_file )[5];
defined $file_mode
  or die "Cannot stat $pkg_file: $!\n";
defined $file_uid && defined $file_gid
  or die "Cannot stat owner of $pkg_file: $!\n";
my $mode = $file_mode & oct('7777');
my ( $out, $temporary ) =
  tempfile( '.packages-XXXXXX', DIR => dirname($pkg_file), UNLINK => 1 );

# Print comments first, then sorted entries. A failed write must abort
# before the temporary file replaces the original. The temporary file
# keeps File::Temp's private mode until it is complete.
for my $comment (@comments) {
    print {$out} "$comment\n"
      or die "Cannot write $temporary: $!\n";
}
for my $entry (@sorted_entries) {
    print {$out} "$entry\n"
      or die "Cannot write $temporary: $!\n";
}

close $out or die "Cannot close $temporary: $!\n";
chown $file_uid, $file_gid, $temporary
  or die "Cannot set ownership on $temporary: $!\n";
chmod $mode, $temporary
  or die "Cannot set permissions on $temporary: $!\n";
rename $temporary, $pkg_file
  or die "Cannot replace $pkg_file: $!\n";

print "📦 Sorted: $pkg_file\n"
  or die "Cannot write to standard output: $!\n";
