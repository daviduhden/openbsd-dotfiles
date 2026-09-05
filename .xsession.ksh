#!/bin/ksh
#
# Minimal .xsession for OpenBSD + spectrwm
#
# This script is executed by the X display manager (xenodm)
# to start the X session.
# It sets up the environment, keyboard layout, X resources,
# wallpaper, notifications, and starts the window manager.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

# -------------------------------------------------
# Environment
# -------------------------------------------------

# Locale
export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# XDG base directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"

# -------------------------------------------------
# Keyboard
# -------------------------------------------------

# XKB layout, written by install.ksh (es or us). Keep the
# KEYBOARD_LAYOUT= line intact so that re-running the installer
# can update it.
KEYBOARD_LAYOUT=es

# nodeadkeys makes the grave key report 'grave' instead of
# 'dead_grave', which the spectrwm move bindings rely on. The US
# layout has no dead keys, so it is set without a variant.
if [ "$KEYBOARD_LAYOUT" = es ]; then
	setxkbmap es nodeadkeys
else
	setxkbmap us
fi

# -------------------------------------------------
# X resources
# -------------------------------------------------

[ -r "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# -------------------------------------------------
# Cursor
# -------------------------------------------------

xsetroot -cursor_name left_ptr

# -------------------------------------------------
# Wallpapers
# -------------------------------------------------

if [ -x /usr/local/bin/openbsd-wallpaper ]; then
	/usr/local/bin/openbsd-wallpaper &
fi

# -------------------------------------------------
# Notifications (dunst)
# -------------------------------------------------

if command -v dunst >/dev/null 2>&1; then
	dunst &
fi

# -------------------------------------------------
# Start window manager
# -------------------------------------------------

exec spectrwm -c "$HOME/.config/spectrwm/spectrwm.conf"
