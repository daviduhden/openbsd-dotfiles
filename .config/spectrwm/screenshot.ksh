#!/bin/ksh
#
# Simple screenshot script for spectrwm
#
# Usage:
#   screenshot.ksh          # Take a full-screen screenshot
#   screenshot.ksh full     # Take a full-screen screenshot
#   screenshot.ksh window   # Take a screenshot of a selected window/area
#
# Requires 'scrot' to be installed
# Saves screenshots to ~/Pictures/Screenshots/
# Creates the directory if it doesn't exist
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

set -e

SCREENSHOT_DIR="${HOME}/Pictures/Screenshots"
NOTIFY_CMD="$(command -v notify-send 2>/dev/null || true)"

if ! command -v scrot >/dev/null 2>&1; then
	echo "scrot is required but not found in PATH" >&2
	exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

mode=${1:-full}
stamp=$(date +%Y-%m-%d_%H-%M-%S)
outfile="${SCREENSHOT_DIR}/screenshot_${mode}_${stamp}.png"

case "$mode" in
full)
	scrot -m "$outfile"
	;;
window)
	# brief pause to allow selection to start cleanly
	sleep 0.2
	scrot -s "$outfile"
	;;
*)
	echo "Usage: $(basename "$0") [full|window]" >&2
	exit 1
	;;
esac

if [ -n "$NOTIFY_CMD" ]; then
	"$NOTIFY_CMD" "Screenshot saved" "$outfile"
fi

echo "Saved: $outfile"
