#!/bin/ksh
#
# Screen setup script for spectrwm
# This script is called by spectrwm on startup to configure
# connected displays using xrandr.
#
# It sets up one internal display and one external display
# (if connected) side by side.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

command -v xrandr >/dev/null 2>&1 || exit 0

connected_outputs=$(xrandr --query | awk '/ connected/ {print $1}')

# Prefer common internal panel names first
internal=""
for candidate in eDP eDP-1 eDP-0 LVDS LVDS-1 LVDS-0; do
	if printf '%s\n' "$connected_outputs" | grep -qx "$candidate"; then
		internal=$candidate
		break
	fi
done

# Fall back to the first connected output if no internal match was found
if [ -z "$internal" ]; then
	internal=$(printf '%s\n' "$connected_outputs" | head -n 1)
fi

# Choose the first other connected output as external
external=$(printf '%s\n' "$connected_outputs" | grep -vx "$internal" | head -n 1)

if [ -n "$internal" ]; then
	xrandr --output "$internal" --auto
fi

if [ -n "$external" ] && [ -n "$internal" ]; then
	xrandr --output "$external" --auto --right-of "$internal"
elif [ -n "$external" ]; then
	xrandr --output "$external" --auto
fi
