#!/bin/ksh
#
# User profile for OpenBSD
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/X11R6/bin:/usr/local/sbin:/usr/local/bin
export PATH

# Set HOSTNAME
if [ -z "${HOSTNAME:-}" ]; then
	HOSTNAME=$(uname -n)
fi
export HOSTNAME

# Pick prompt symbol
if [ "$(id -u)" -eq 0 ]; then
	PSCHAR='#'
else
	PSCHAR='$'
fi

# Prompt
export PS1='${LOGNAME}@${HOSTNAME%%.*}:${PWD} ${PSCHAR} '

# Locale and tools
export LANG='es_ES.UTF-8'
export LC_CTYPE='es_ES.UTF-8'
export LC_COLLATE='C'
export EDITOR=vi
export VISUAL=kak
export FCEDIT=$EDITOR
export PAGER=less
export LESS='-iMRS -x2'

# less(1) colours (Dracula)
LESS_TERMCAP_mb=$(printf '%b' '\033[1;35m')
LESS_TERMCAP_md=$(printf '%b' '\033[1;35m')
LESS_TERMCAP_me=$(printf '%b' '\033[0m')
LESS_TERMCAP_se=$(printf '%b' '\033[0m')
LESS_TERMCAP_so=$(printf '%b' '\033[7;35m')
LESS_TERMCAP_ue=$(printf '%b' '\033[0m')
LESS_TERMCAP_us=$(printf '%b' '\033[4;36m')
export LESS_TERMCAP_mb LESS_TERMCAP_md LESS_TERMCAP_me
export LESS_TERMCAP_se LESS_TERMCAP_so LESS_TERMCAP_ue LESS_TERMCAP_us

# ls(1) colours (Dracula): bold ANSI colours from the terminal palette
export CLICOLOR=1
export LSCOLORS='ExGxFxDxCxDxDxBxBxExEx'

# GNU ls/tree colours (Dracula); used by tree(1)
export LS_COLORS='di=1;34:ln=1;36:so=1;35:pi=1;33:ex=1;32:bd=1;33:cd=1;33:su=1;31:sg=1;31:tw=1;34:ow=1;34'

# History and editing mode
HISTFILE=$HOME/.ksh_history
HISTSIZE=20000
set -o vi

# Default umask
umask 022

# Only run this block for interactive shells
case "$-" in
*i*) # interactive shell
	if [ -x /usr/bin/tset ]; then
		eval "$(/usr/bin/tset -IsQ '-munknown:?vt220' "$TERM")"
	fi
	;;
esac
