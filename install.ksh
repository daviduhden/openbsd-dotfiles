#!/bin/ksh
#
# Installation script for OpenBSD dotfiles
#
# This script installs the OpenBSD dotfiles for a specified user.
# It requires root (superuser) privileges to run.
# It installs necessary packages,
# configures doas, and sets up configuration files for spectrwm and dunst.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_FILE="$SCRIPT_DIR/packages.txt"

# -------------------------------------------------
# PATH (predictable execution)
# -------------------------------------------------

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH

# -------------------------------------------------
# Colors and logging
# -------------------------------------------------

if [ -t 1 ] && [ "${NO_COLOR:-}" != "1" ]; then
	GREEN="\033[32m"
	YELLOW="\033[33m"
	RED="\033[31m"
	RESET="\033[0m"
else
	GREEN=""
	YELLOW=""
	RED=""
	RESET=""
fi

log() { print "${GREEN}[INFO]${RESET} ✅ $*"; }
warn() { print "${YELLOW}[WARN]${RESET} ⚠️ $*" >&2; }
error() { print "${RED}[ERROR]${RESET} ❌ $*" >&2; }

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root (superuser)."
		exit 1
	fi
}

load_packages() {
	unset PKGS
	typeset -a PKGS

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
	print "Enter target username (leave empty for current user): \c"
	read -r TARGET_USER

	if [ -z "$TARGET_USER" ]; then
		TARGET_USER="$(id -un)"
	fi

	TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

	if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
		error "Could not determine HOME for user '$TARGET_USER'"
		exit 1
	fi

	export HOME="$TARGET_HOME"
	log "Installing dotfiles for user: '$TARGET_USER'"
	log "Using HOME: $HOME"
}

configure_doas() {
	log "Configuring doasers for $TARGET_USER …"
	DOAS_RULE="permit persist $TARGET_USER as root"
	if ! grep -qF "$DOAS_RULE" /etc/doas.conf 2>/dev/null; then
		sh -c "echo '$DOAS_RULE' >> /etc/doas.conf"
		log "Added rule to /etc/doas.conf"
	else
		log "Rule already present in /etc/doas.conf"
	fi
}

install_packages() {
	load_packages
	log "Installing packages from $PKG_FILE …"
	for pkg in "${PKGS[@]}"; do
		pkg_add -- "$pkg"
	done
}

create_directories() {
	log "Creating configuration directories …"
	mkdir -p \
		"$HOME/.config/spectrwm" \
		"$HOME/.config/dunst"
}

install_spectrwm() {
	log "Installing spectrwm configuration …"
	rm -rf "$HOME/.config/spectrwm/*"
	install -m 644 "$SCRIPT_DIR/.config/spectrwm/spectrwm.conf" "$HOME/.config/spectrwm/spectrwm.conf"
	install -m 755 "$SCRIPT_DIR/.config/spectrwm/initscreen.ksh" "$SCRIPT_DIR/.config/spectrwm/screenshot.ksh" \
		"$HOME/.config/spectrwm/"
}

install_dunst() {
	log "Installing dunst configuration …"
	install -m 644 "$SCRIPT_DIR/.config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
}

install_session_files() {
	log "Installing session files …"
	install -m 755 "$SCRIPT_DIR/.xsession" "$HOME/.xsession"
	install -m 755 "$SCRIPT_DIR/.Xresources" "$HOME/.Xresources"
	install -m 644 "$SCRIPT_DIR/.profile" "$HOME/.profile"
}

update_profile_home() {
	profile_path="$HOME/.profile"

	if [ ! -f "$profile_path" ]; then
		warn "Profile file not found at $profile_path; skipping HOME update"
		return
	fi

	tmp_profile=$(mktemp "${profile_path}.XXXXXX") || exit 1

	if sed "s|^: \${HOME='[^']*'}|: \${HOME='$HOME'}|" "$profile_path" >"$tmp_profile"; then
		mv "$tmp_profile" "$profile_path"
	else
		rm -f "$tmp_profile"
		error "Failed to update HOME in $profile_path"
		exit 1
	fi
}

fix_ownership() {
	if [ "$(id -u)" -eq 0 ]; then
		log "Fixing ownership for $TARGET_USER …"
		chown -R "$TARGET_USER:$TARGET_USER" "$HOME/.config"
		chown "$TARGET_USER:$TARGET_USER" "$HOME/.xsession" "$HOME/.profile"
	fi
}

set_shell() {
	log "Setting shell to ksh93 for $TARGET_USER …"
	chsh -s /usr/local/bin/ksh93 "$TARGET_USER"
}

main() {
	require_root
	ask_target_user
	configure_doas
	install_packages
	create_directories
	install_spectrwm
	install_dunst
	install_session_files
	update_profile_home
	fix_ownership
	set_shell

	log "Installation complete."
	log "Log out and log back in to start spectrwm."
}

main "$@"
