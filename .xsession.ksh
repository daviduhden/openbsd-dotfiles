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

# Locale (por si el display manager no lo exporta bien)
export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# XDG base dirs (algunos programas lo agradecen)
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"

# -------------------------------------------------
# Keyboard
# -------------------------------------------------

# Spanish layout without dead keys
setxkbmap es nodeadkeys

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
# Prevent screen blanking / DPMS (optional)
# -------------------------------------------------

xset s off
xset -dpms
xset s noblank

# -------------------------------------------------
# Start window manager
# -------------------------------------------------

exec spectrwm -c "$HOME/.config/spectrwm/spectrwm.conf"
