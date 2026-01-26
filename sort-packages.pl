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
use Cwd            qw(abs_path);

# Script directory
my $script_dir = dirname( abs_path($0) );

# Packages file
my $pkg_file = $ARGV[0] // "$script_dir/packages.txt";

-f $pkg_file
  or die "packages file not found: $pkg_file\n";

# Read file and separate comments from entries
open my $in, '<', $pkg_file
  or die "Cannot open $pkg_file: $!\n";

my @comments;
my @entries;

while ( my $line = <$in> ) {
    chomp $line;    # remove newline for consistent sorting
    if ( $line =~ /^#/ ) {
        push @comments, $line;
    }
    elsif ( $line =~ /\S/ ) {
        push @entries, $line;
    }
}
close $in;

# Sort entries bytewise (like LC_ALL=C) and remove duplicates
my %seen;
my @sorted_entries = sort { $a cmp $b } grep { !$seen{$_}++ } @entries;

# Write back to the original file
open my $out, '>', $pkg_file
  or die "Cannot write to $pkg_file: $!\n";

# Print comments first, then sorted entries
print $out "$_\n" for @comments;
print $out "$_\n" for @sorted_entries;

close $out;

print "Sorted: $pkg_file\n";
