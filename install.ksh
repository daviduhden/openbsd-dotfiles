#!/bin/ksh
#
# Installation script for OpenBSD dotfiles
#
# This script installs the OpenBSD dotfiles for a specified user.
# It requires root (superuser) privileges to run.
# It installs necessary packages,
# configures doas, asks for the X keyboard layout (es or us),
# and sets up configuration files for spectrwm
# and dunst.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

set -e

# -------------------------------------------------
# PATH (predictable execution)
# -------------------------------------------------

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_FILE="$SCRIPT_DIR/packages.txt"
set -A PKGS --

log() { print "[INFO] [OK] $*"; }
warn() { print "[WARN] [WARN] $*" >&2; }
error() { print "[ERROR] [ERROR] $*" >&2; }

confirm() {
	print "$1 [y/N]: \c"
	read -r answer
	case "$answer" in
	[yY] | [yY][eE][sS]) return 0 ;;
	*) return 1 ;;
	esac
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root (superuser)."
		exit 1
	fi
}

load_packages() {
	set -A PKGS --

	if [ ! -s "$PKG_FILE" ]; then
		error "Package list not found or empty: $PKG_FILE"
		exit 1
	fi

	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		PKGS[${#PKGS[@]}]="$pkg"
	done <<EOF
$(awk 'NF && $1 !~ /^#/' "$PKG_FILE")
EOF

	if [ ${#PKGS[@]} -eq 0 ]; then
		error "Package list contained no packages: $PKG_FILE"
		exit 1
	fi
}

ask_target_user() {
	default_user="${DOAS_USER:-}"
	if [ "$default_user" = root ]; then
		default_user=""
	fi
	if [ -n "$default_user" ]; then
		print "Enter target username [$default_user]: \c"
	else
		print "Enter target username: \c"
	fi
	read -r TARGET_USER

	if [ -z "$TARGET_USER" ]; then
		TARGET_USER="$default_user"
	fi
	[ -n "$TARGET_USER" ] || {
		error "A non-root target username is required."
		exit 1
	}
	if [ "$TARGET_USER" = root ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
		error "Target user '$TARGET_USER' does not exist or is root."
		exit 1
	fi

	TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
	TARGET_GROUP="$(id -gn "$TARGET_USER")"

	if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
		error "Could not determine HOME for user '$TARGET_USER'"
		exit 1
	fi

	export HOME="$TARGET_HOME"
	log "Installing dotfiles for user: '$TARGET_USER'"
	log "Using HOME: $HOME"
}

ask_keyboard_layout() {
	# A valid KEYBOARD_LAYOUT environment variable (es or us)
	# preselects the layout for non-interactive use.
	if [ -n "${KEYBOARD_LAYOUT:-}" ]; then
		case "$KEYBOARD_LAYOUT" in
		es | us)
			log "Keyboard layout from environment: $KEYBOARD_LAYOUT"
			return
			;;
		*)
			error "Invalid KEYBOARD_LAYOUT '$KEYBOARD_LAYOUT' (must be 'es' or 'us')."
			exit 1
			;;
		esac
	fi

	print "Select X keyboard layout:"
	print "  1. Spanish - Spain (es) [default]"
	print "  2. English - United States (us)"
	print "Enter choice [1]: \c"
	read -r choice
	case "$choice" in
	"" | 1 | es)
		KEYBOARD_LAYOUT=es
		;;
	2 | us)
		KEYBOARD_LAYOUT=us
		;;
	*)
		error "Invalid keyboard layout selection: '$choice'"
		exit 1
		;;
	esac
	log "Keyboard layout selected: $KEYBOARD_LAYOUT"
}

configure_doas() {
	if ! confirm "Grant $TARGET_USER persistent doas access as root?"; then
		warn "Skipping doas configuration."
		return
	fi
	log "Configuring doas for $TARGET_USER ..."
	DOAS_RULE="permit persist $TARGET_USER as root"
	if ! awk -v rule="$DOAS_RULE" '
		{
			line = $0
			sub(/^[[:space:]]*/, "", line)
			sub(/[[:space:]]*#.*/, "", line)
			if (line == rule) found = 1
		}
		END { exit !found }
	' /etc/doas.conf 2>/dev/null; then
		doas_tmp=$(mktemp /tmp/doas.conf.XXXXXX)
		if [ -f /etc/doas.conf ]; then
			cp /etc/doas.conf "$doas_tmp"
		fi
		print >>"$doas_tmp"
		print -r -- "$DOAS_RULE" >>"$doas_tmp"
		if ! doas -C "$doas_tmp"; then
			rm -f "$doas_tmp"
			error "The generated doas configuration is invalid."
			exit 1
		fi
		install -b -o root -g wheel -m 600 "$doas_tmp" /etc/doas.conf
		rm -f "$doas_tmp"
		log "Added rule to /etc/doas.conf"
	else
		log "Rule already present in /etc/doas.conf"
	fi
}

install_packages() {
	load_packages
	log "Installing packages from $PKG_FILE ..."
	for pkg in "${PKGS[@]}"; do
		pkg_add "$pkg"
	done
}

create_directories() {
	log "Creating configuration directories ..."
	install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 700 \
		"$HOME/.config/spectrwm" \
		"$HOME/.config/dunst"
}

install_spectrwm() {
	log "Installing spectrwm configuration ..."
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.config/spectrwm/spectrwm.conf" \
		"$HOME/.config/spectrwm/spectrwm.conf"
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 \
		"$SCRIPT_DIR/.config/spectrwm/initscreen.ksh" \
		"$SCRIPT_DIR/.config/spectrwm/screenshot.ksh" \
		"$SCRIPT_DIR/.config/spectrwm/statusbar.ksh" \
		"$HOME/.config/spectrwm/"
}

install_dunst() {
	log "Installing dunst configuration ..."
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.config/dunst/dunstrc" \
		"$HOME/.config/dunst/dunstrc"
}

install_session_files() {
	log "Installing session files ..."
	install -b -o root -g wheel -m 755 "$SCRIPT_DIR/xenodm/Xsetup_0.sh" \
		"/etc/X11/xenodm/Xsetup_0"
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 \
		"$SCRIPT_DIR/.xsession.ksh" "$HOME/.xsession"
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.Xresources" "$HOME/.Xresources"
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.profile.ksh" "$HOME/.profile"
	apply_keyboard_layout
}

apply_keyboard_layout() {
	# Rewrite the KEYBOARD_LAYOUT= line in ~/.xsession with the
	# selected layout. The substitution replaces the single line,
	# so re-running the installer never duplicates it.
	xsess_tmp=$(mktemp /tmp/xsession.XXXXXX)
	awk -v layout="$KEYBOARD_LAYOUT" '
		/^KEYBOARD_LAYOUT=/ {
			print "KEYBOARD_LAYOUT=" layout
			next
		}
		{ print }
	' "$HOME/.xsession" >"$xsess_tmp"
	if ! grep -q "^KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT\$" "$xsess_tmp"; then
		warn "No KEYBOARD_LAYOUT= line found in ~/.xsession; layout not applied."
	fi
	chown "$TARGET_USER:$TARGET_GROUP" "$xsess_tmp"
	chmod 755 "$xsess_tmp"
	mv "$xsess_tmp" "$HOME/.xsession"
	log "Keyboard layout '$KEYBOARD_LAYOUT' written to ~/.xsession"
}

set_shell() {
	log "Setting shell to the base system ksh for $TARGET_USER ..."
	chsh -s /bin/ksh "$TARGET_USER"
}

main() {
	require_root
	ask_target_user
	configure_doas
	ask_keyboard_layout
	install_packages
	create_directories
	install_spectrwm
	install_dunst
	install_session_files
	set_shell

	log "Installation complete."
	log "Log out and log back in to start spectrwm."
}

main "$@"
