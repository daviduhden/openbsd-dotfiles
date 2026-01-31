#!/bin/sh
#
# Xenodm Xsetup script to set root window properties
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

prefix="/usr/X11R6"
exec_prefix="${prefix}"

${exec_prefix}/bin/xsetroot -fg \#6f6f6f -bg \#bfbfbf -bitmap ${prefix}/include/X11/bitmaps/root_weave

if test -x /usr/local/bin/openbsd-wallpaper; then
	/usr/local/bin/openbsd-wallpaper
fi
