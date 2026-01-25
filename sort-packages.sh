#!/bin/sh
#
# Sort packages.txt alphabetically (comments preserved at top)
# Usage: sort-packages.sh [path/to/packages.txt]
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_FILE=${1:-"$SCRIPT_DIR/packages.txt"}

if [ ! -f "$PKG_FILE" ]; then
	echo "packages file not found: $PKG_FILE" >&2
	exit 1
fi

comments_tmp=$(mktemp "${PKG_FILE##*/}.comments.XXXXXX")
list_tmp=$(mktemp "${PKG_FILE##*/}.list.XXXXXX")
sorted_tmp=$(mktemp "${PKG_FILE##*/}.sorted.XXXXXX")

cleanup() {
	rm -f "$comments_tmp" "$list_tmp" "$sorted_tmp"
}
trap cleanup EXIT

awk '
	NR == 1 && /^#/ { print > cfile; next }
	/^#/ { print > cfile; next }
	NF { print > lfile }
' cfile="$comments_tmp" lfile="$list_tmp" "$PKG_FILE"

LC_ALL=C sort -u "$list_tmp" >"$sorted_tmp"

{
	cat "$comments_tmp"
	cat "$sorted_tmp"
} >"$PKG_FILE"

cleanup
trap - EXIT

echo "Sorted: $PKG_FILE"
