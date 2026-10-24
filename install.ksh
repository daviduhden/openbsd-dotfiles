#!/bin/ksh
#
# Installation script for OpenBSD dotfiles
#
# This script installs the OpenBSD dotfiles for a specified user.
# It requires root (superuser) privileges to run.
# It asks for the target user and the X keyboard layout (es or us),
# optionally configures doas, installs the packages, and sets the
# matching locale (es_ES.UTF-8 or en_US.UTF-8). It also sets up the
# spectrwm and dunst configuration files.
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

DOAS_TMP=
LAYOUT_TMP=

cleanup() {
	if [ -n "$DOAS_TMP" ]; then
		rm -f "$DOAS_TMP"
	fi
	if [ -n "$LAYOUT_TMP" ]; then
		rm -f "$LAYOUT_TMP"
	fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

log() { print "[INFO] $*"; }
warn() { print "[WARN] $*" >&2; }
error() { print "[ERROR] $*" >&2; }

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
$(awk 'NF && $1 !~ /^#/ { print $1 }' "$PKG_FILE")
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
	case "$TARGET_USER" in
	-*)
		error "Target username must not start with '-'."
		exit 1
		;;
	esac

	if ! TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null); then
		error "Target user '$TARGET_USER' does not exist."
		exit 1
	fi
	if [ "$TARGET_UID" -eq 0 ]; then
		error "Target user '$TARGET_USER' has UID 0; choose a non-root account."
		exit 1
	fi

	# OpenBSD base does not provide getent(1); read the local passwd
	# database directly. This also rejects numeric IDs that do not
	# name a real account.
	TARGET_HOME=$(awk -F: -v user="$TARGET_USER" \
		'$1 == user { print $6; exit }' /etc/passwd)
	TARGET_GROUP=$(id -gn "$TARGET_USER")

	if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ] ||
		[ "$TARGET_HOME" = / ]; then
		error "Could not determine a usable HOME for user '$TARGET_USER'"
		exit 1
	fi

	export HOME="$TARGET_HOME"
	log "Installing dotfiles for user: '$TARGET_USER'"
	log "Using HOME: $HOME"
}

ask_keyboard_layout() {
	# A valid KEYBOARD_LAYOUT environment variable (es or us)
	# skips this prompt; the user and doas prompts still run.
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
			sub(/[[:space:]]*#.*/, "", line)
			gsub(/[[:space:]]+/, " ", line)
			sub(/^ /, "", line)
			sub(/ $/, "", line)
			if (line == rule) found = 1
		}
		END { exit !found }
	' /etc/doas.conf 2>/dev/null; then
		DOAS_TMP=$(mktemp /tmp/doas.conf.XXXXXX)
		if [ -f /etc/doas.conf ]; then
			cp /etc/doas.conf "$DOAS_TMP"
		fi
		print >>"$DOAS_TMP"
		print -r -- "$DOAS_RULE" >>"$DOAS_TMP"
		if ! doas -C "$DOAS_TMP"; then
			error "The generated doas configuration is invalid."
			exit 1
		fi
		install -b -o root -g wheel -m 600 "$DOAS_TMP" /etc/doas.conf
		rm -f "$DOAS_TMP"
		DOAS_TMP=
		log "Added rule to /etc/doas.conf"
	else
		log "Rule already present in /etc/doas.conf"
	fi
}

install_packages() {
	load_packages
	log "Installing packages from $PKG_FILE ..."
	for pkg in "${PKGS[@]}"; do
		pkg_add -- "$pkg"
	done
}

# Create one directory component at a time so that every missing
# parent is owned by the target user, not root. Existing directories
# are left untouched (mode and ownership preserved). Refuse symlinked
# managed directories to avoid writing through a link as root.
ensure_dir() {
	typeset dir=$1 mode=$2 parent
	if [ "$dir" = "$HOME" ]; then
		return 0
	fi
	if [ -L "$dir" ]; then
		error "Refusing to use symlinked directory: $dir"
		exit 1
	fi
	if [ -d "$dir" ]; then
		return 0
	fi
	parent=$(dirname "$dir")
	if [ "$parent" != "$dir" ]; then
		ensure_dir "$parent" 755
	fi
	install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m "$mode" "$dir"
}

create_directories() {
	log "Creating configuration directories ..."
	ensure_dir "$HOME/.config" 755
	ensure_dir "$HOME/.config/spectrwm" 700
	ensure_dir "$HOME/.config/dunst" 700
}

install_spectrwm() {
	log "Installing spectrwm configuration ..."
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.config/spectrwm/spectrwm.conf" \
		"$HOME/.config/spectrwm/spectrwm.conf"
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 \
		"$SCRIPT_DIR/.config/spectrwm/initscreen.pl" \
		"$SCRIPT_DIR/.config/spectrwm/screenshot.pl" \
		"$SCRIPT_DIR/.config/spectrwm/statusbar.pl" \
		"$HOME/.config/spectrwm/"
}

install_dunst() {
	log "Installing dunst configuration ..."
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 \
		"$SCRIPT_DIR/.config/dunst/dunstrc" \
		"$HOME/.config/dunst/dunstrc"
}

install_root_profile() {
	log "Installing root profile ..."
	install -b -o root -g wheel -m 644 \
		"$SCRIPT_DIR/root/.profile.ksh" "/root/.profile"
}

install_user_file() {
	# $1 source, $2 destination, $3 mode. Creates the destination
	# directory (owned by the target user) when needed.
	ensure_dir "$(dirname "$2")" 755
	install -b -o "$TARGET_USER" -g "$TARGET_GROUP" -m "$3" "$1" "$2"
}

install_themes() {
	log "Installing Dracula themes ..."

	# vifm
	install_user_file "$SCRIPT_DIR/.config/vifm/vifmrc" \
		"$HOME/.config/vifm/vifmrc" 644
	install_user_file "$SCRIPT_DIR/.config/vifm/colors/dracula.vifm" \
		"$HOME/.config/vifm/colors/dracula.vifm" 644

	# kakoune
	install_user_file "$SCRIPT_DIR/.config/kak/kakrc" \
		"$HOME/.config/kak/kakrc" 644
	install_user_file "$SCRIPT_DIR/.config/kak/colors/dracula.kak" \
		"$HOME/.config/kak/colors/dracula.kak" 644

	# NeoMutt
	install_user_file "$SCRIPT_DIR/.config/neomutt/neomuttrc" \
		"$HOME/.config/neomutt/neomuttrc" 644
	install_user_file "$SCRIPT_DIR/.config/neomutt/dracula.muttrc" \
		"$HOME/.config/neomutt/dracula.muttrc" 644

	# tig
	install_user_file "$SCRIPT_DIR/.config/tig/config" \
		"$HOME/.config/tig/config" 644

	# zathura
	install_user_file "$SCRIPT_DIR/.config/zathura/zathurarc" \
		"$HOME/.config/zathura/zathurarc" 644

	# cmus
	install_user_file "$SCRIPT_DIR/.config/cmus/rc" \
		"$HOME/.config/cmus/rc" 644
	install_user_file "$SCRIPT_DIR/.config/cmus/dracula.theme" \
		"$HOME/.config/cmus/dracula.theme" 644

	# mpv
	install_user_file "$SCRIPT_DIR/.config/mpv/mpv.conf" \
		"$HOME/.config/mpv/mpv.conf" 644
	install_user_file "$SCRIPT_DIR/.config/mpv/script-opts/osc.conf" \
		"$HOME/.config/mpv/script-opts/osc.conf" 644

	# profanity
	install_user_file "$SCRIPT_DIR/.config/profanity/profrc" \
		"$HOME/.config/profanity/profrc" 644
	install_user_file "$SCRIPT_DIR/.config/profanity/themes/dracula" \
		"$HOME/.config/profanity/themes/dracula" 644

	# fastfetch
	install_user_file "$SCRIPT_DIR/.config/fastfetch/config.jsonc" \
		"$HOME/.config/fastfetch/config.jsonc" 644

	# telescope
	install_user_file "$SCRIPT_DIR/.config/telescope/config" \
		"$HOME/.config/telescope/config" 644

	# git (read before ~/.gitconfig, so it never overrides it)
	install_user_file "$SCRIPT_DIR/.config/git/config" \
		"$HOME/.config/git/config" 644

	# irssi (theme file only; activate once with /theme dracula)
	install_user_file "$SCRIPT_DIR/.irssi/dracula.theme" \
		"$HOME/.irssi/dracula.theme" 644
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
}

# Map the selected XKB layout to the matching UTF-8 locale.
layout_locale() {
	case "$1" in
	us) print -r -- 'en_US.UTF-8' ;;
	*) print -r -- 'es_ES.UTF-8' ;;
	esac
}

# Rewrite the layout-dependent lines of one installed file: the
# KEYBOARD_LAYOUT= assignment (when present) and the LANG= and
# LC_CTYPE= exports. Owner and mode are preserved. Idempotent.
apply_layout_file() {
	LAYOUT_TMP=$(mktemp "$(dirname "$1")/.dotfiles.XXXXXX")
	awk -v layout="$KEYBOARD_LAYOUT" -v locale="$LAYOUT_LOCALE" '
		/^KEYBOARD_LAYOUT=/ {
			print "KEYBOARD_LAYOUT=" layout
			next
		}
		/^[[:space:]]*export[[:space:]]+LANG=/ {
			print "export LANG=" locale
			next
		}
		/^[[:space:]]*export[[:space:]]+LC_CTYPE=/ {
			print "export LC_CTYPE=" locale
			next
		}
		{ print }
	' "$1" >"$LAYOUT_TMP"
	chown "$2:$3" "$LAYOUT_TMP"
	chmod "$4" "$LAYOUT_TMP"
	mv "$LAYOUT_TMP" "$1"
	LAYOUT_TMP=
}

apply_keyboard_layout() {
	# When the US layout is selected the environment locale is
	# switched to en_US.UTF-8 as well; LC_COLLATE stays C. The
	# substitutions replace whole lines, so re-running the
	# installer never duplicates them.
	LAYOUT_LOCALE=$(layout_locale "$KEYBOARD_LAYOUT")

	apply_layout_file "$HOME/.xsession" \
		"$TARGET_USER" "$TARGET_GROUP" 755
	if ! grep -Fqx "KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT" "$HOME/.xsession"; then
		error "No matching KEYBOARD_LAYOUT= line in ~/.xsession."
		exit 1
	fi
	apply_layout_file "$HOME/.profile" \
		"$TARGET_USER" "$TARGET_GROUP" 644
	apply_layout_file "/root/.profile" root wheel 644

	for layout_file in "$HOME/.xsession" "$HOME/.profile" "/root/.profile"; do
		if ! grep -Fqx "export LANG=$LAYOUT_LOCALE" "$layout_file"; then
			error "LANG was not applied to $layout_file."
			exit 1
		fi
		if ! grep -Fqx "export LC_CTYPE=$LAYOUT_LOCALE" "$layout_file"; then
			error "LC_CTYPE was not applied to $layout_file."
			exit 1
		fi
	done

	log "Keyboard layout '$KEYBOARD_LAYOUT' and locale '$LAYOUT_LOCALE' applied."
}

set_shell() {
	log "Setting shell to the base system ksh for $TARGET_USER ..."
	chsh -s /bin/ksh "$TARGET_USER"
}

main() {
	require_root
	ask_target_user
	ask_keyboard_layout
	configure_doas
	install_packages
	create_directories
	install_spectrwm
	install_dunst
	install_root_profile
	install_session_files
	install_themes
	apply_keyboard_layout
	set_shell

	log "Installation complete."
	log "Log out and log back in to start spectrwm."
}

main "$@"
