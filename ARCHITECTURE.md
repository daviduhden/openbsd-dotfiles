# Repository Architecture

This document maps the checked-in source files to their parsers, installation
destinations, startup roles, and important dependencies. It is a static map:
the installer is interactive and is not run as part of reviewing this
document.

## Purpose and layout

This repository installs an opinionated OpenBSD workstation configuration.
`install.ksh` is the root-only orchestrator; `packages.txt` supplies its
package inputs; user settings are copied under the selected account's home;
and the checked-in root-target sources are `root/.profile.ksh` and
`xenodm/Xsetup_0.sh`. The installer can also generate `/etc/doas.conf` from
the live file when the optional rule is selected. There are no symlink-based
deployment mechanisms, network
configuration fragments, PF rules, service configuration files, or
repository-local `/etc` templates.

| Source group | Parser or interpreter | Installed destination / role |
| --- | --- | --- |
| `install.ksh` | OpenBSD `/bin/ksh` | Run explicitly as root; installs files and packages |
| `.profile.ksh` | OpenBSD `/bin/ksh` profile syntax | `~/.profile`; sets environment and interactive terminal setup |
| `root/.profile.ksh` | OpenBSD `/bin/ksh` profile syntax | `/root/.profile`; only read by shells that load profiles |
| `.xsession.ksh` | OpenBSD `/bin/ksh` | `~/.xsession`; started by the display manager after graphical login |
| `.Xresources` | X resource database syntax; `!` starts comments | `~/.Xresources`; merged by `.xsession` with `xrdb -merge` |
| `xenodm/Xsetup_0.sh` | `/bin/sh` | `/etc/X11/xenodm/Xsetup_0`; runs at the display manager's login screen |
| `.config/spectrwm/spectrwm.conf` | spectrwm configuration parser | `~/.config/spectrwm/spectrwm.conf` |
| `.config/spectrwm/*.pl` | Base Perl; OpenBSD helpers use `OpenBSD::Unveil` | Status, display setup, and screenshot actions called by spectrwm |
| `.config/dunst/dunstrc` | Dunst INI-style configuration | `~/.config/dunst/dunstrc`; started by `.xsession` if available |
| `.config/*`, `.irssi/*` | Application-specific parsers | Theme and application preferences copied to matching home paths |
| `sort-packages.pl` | Base Perl | Explicitly sorts a package manifest; not run by the installer |
| `tests/perl_helpers_test.ksh` | OpenBSD `/bin/ksh` | Explicit non-root tests using a temporary directory and fake `scrot` |
| `scripts/validate-agent-knowledge.py` | Python 3.11+ | Read-only agent and skill policy validator; does not run the installer |
| `.github/workflows/agent-knowledge-validation.yml` | GitHub Actions | Read-only pull request contract tests and range validation |
| `packages.txt` | Installer's `awk` field extraction | Package names passed individually to `pkg_add --` |

Other tracked files are maintainer or user documentation (`README.md`,
`USAGE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `AGENTS.md`, the local
skills, and `LICENSE`). They are not sourced by runtime configuration.

## Startup and dependency flow

```text
xenodm login screen
  └─ /etc/X11/xenodm/Xsetup_0
       └─ xsetroot + Xenocara root_weave bitmap

successful graphical login
  └─ ~/.xsession (installed from .xsession.ksh)
       ├─ establishes PATH, locale, and XDG directories
       ├─ applies X keyboard layout with setxkbmap
       ├─ merges ~/.Xresources with xrdb
       ├─ sets root cursor; optionally starts openbsd-wallpaper and dunst
       └─ execs spectrwm with ~/.config/spectrwm/spectrwm.conf
            ├─ autorun: initscreen.pl → xrandr, if available
            ├─ bar_action: statusbar.pl → OpenBSD base system data tools
            └─ screenshot bindings: screenshot.pl → scrot and optional notify-send
```

`.profile.ksh` is an independent login-shell profile. It is not loaded by
`.xsession` and this repository has no `.kshrc`; do not infer that interactive
shell configuration is sourced by every shell. `root/.profile.ksh` is
installed as `/root/.profile`, but OpenBSD root normally uses `csh`, which
does not read it. The installer explicitly runs `install.ksh`; the sorter
and regression suite are also opt-in commands, not startup hooks.

The installer reads the package list, prompts for a local non-root user and
keyboard layout, can optionally add a broad persistent `doas` rule, copies
files with `install -b` backups, rewrites layout-dependent locale lines, and
changes the target account's login shell. It creates missing managed
directories for the target user, preserves existing directory metadata, and
refuses symlinked managed directories. It is not transactional. Do not run it
to inspect its behavior or assume earlier operations are rolled back after a
failure.

Its `main` sequence first verifies root, resolves the target account and
keyboard layout, handles the optional doas candidate, then installs packages,
directories, application files, session files, and themes before applying
layout/locale rewrites and changing the target shell. `ask_target_user`
rejects option-like names, UID 0 accounts, missing users, and unusable home
directories; it reads the local passwd entry with `awk`. `ask_keyboard_layout`
accepts only `es` or `us`; a valid environment value skips only that prompt.
`configure_doas` checks for the normalized exact rule, validates a temporary
candidate with `doas -C`, then installs it with a backup. Declining it makes
that step a no-op. The rule grants broad persistent root access.

`load_packages` reads the first field of nonblank, noncomment manifest lines
into a Ksh array; `install_packages` passes each entry after `--` to
`pkg_add`. `ensure_dir` recursively creates missing parent directories under
the target user's ownership, preserves existing directories, and exits on a
managed symlink. The installer functions for spectrwm, dunst, session files,
root profile, and themes map repository paths to the destinations listed
above. `install_user_file` ensures its parent before copying. `apply_layout_file`
rewrites whole matching lines into a same-directory temporary file, restores
owner and mode, and renames it over the installed file. `apply_keyboard_layout`
checks the required lines after rewriting. The `EXIT` trap removes outstanding
temporary paths; HUP, INT, and TERM exit with signal-style statuses and then
run cleanup. `set_shell` is the last persistent installer operation.

In `statusbar.pl`, `run_capture` executes argv directly (without a shell),
discards expected stderr, captures stdout, and returns no value on execution
or child failure. `get_cpu` computes usage from in-process tick deltas;
`get_volume`, `get_mem`, `get_bat`, and `get_net` parse named command output
into optional display fields. `first_active_iface` is the fallback when no
usable default-route interface is selected. `get_traffic` locates byte
counters by `netstat` header names and calculates rates from successive
samples; `rate` formats those rates with binary units. `service_running`
checks a service through `rcctl check` and bases its result on the child's
exit status. Unavailable devices and services are intentionally omitted or
represented as offline, while output failure ends the loop.

`sort-packages.pl` accepts an optional manifest path, otherwise resolves
`packages.txt` beside itself. It holds input lines in memory, retains
comment lines in their original order at the top, sorts nonblank entries by
Perl's bytewise string comparison and removes exact duplicates. It writes to
a same-directory `File::Temp` file, copies mode and ownership, then renames
the completed file atomically. A failed read, write, metadata update, or
rename is reported with `die`; the temporary file is configured for cleanup.
The test driver exercises the sorter and screenshot status mapping in a
temporary directory, substituting a fake `scrot` and disabling OpenBSD
unveil only in its generated test copy.

## Runtime configuration groups

The runtime inventory below names every tracked runtime file beneath
`.config/` and `.irssi/`; the parser or interpreter is the application that
consumes it. These files are copied, not sourced by the shell.

| File | Parser | Purpose and notable relationship |
| --- | --- | --- |
| `.config/cmus/rc` | cmus | Selects the shipped Dracula colorscheme; cmus may rewrite this file on exit |
| `.config/cmus/dracula.theme` | cmus theme parser | Assigns the player's interface roles to ANSI palette indexes |
| `.config/dunst/dunstrc` | Dunst | Notification placement, text, icon lookup, behavior, shortcuts, and urgency colors |
| `.config/fastfetch/config.jsonc` | Fastfetch JSONC | Selects logo and display colors and the ordered system-information modules |
| `.config/git/config` | Git config | Enables terminal colors and maps branch, status, diff, decoration, and interactive colors |
| `.config/kak/kakrc` | Kakoune | Loads the repository's Dracula colorscheme |
| `.config/kak/colors/dracula.kak` | Kakoune | Defines palette options and syntax, diff, markup, selection, and UI faces |
| `.config/mpv/mpv.conf` | mpv | Sets OSD and subtitle colors; OSC colors are kept in a separate file |
| `.config/mpv/script-opts/osc.conf` | mpv OSC script | Sets on-screen controller colors and box alpha |
| `.config/neomutt/neomuttrc` | NeoMutt | Sources the companion theme using an explicit home-relative path |
| `.config/neomutt/dracula.muttrc` | NeoMutt | Applies ANSI colors to interface roles, message patterns, headers, and body patterns |
| `.config/profanity/profrc` | Profanity | Selects the theme file under `themes/` |
| `.config/profanity/themes/dracula` | Profanity | Maps chat, roster, status, and OTR states to ANSI color names |
| `.config/spectrwm/spectrwm.conf` | spectrwm | Defines programs, appearance, bar, autorun, key bindings, and workspaces |
| `.config/spectrwm/statusbar.pl` | Perl invoked as spectrwm `bar_action` | Produces system status fields using OpenBSD base utilities |
| `.config/spectrwm/initscreen.pl` | Perl invoked by spectrwm `autorun` | Selects connected display outputs through `xrandr` |
| `.config/spectrwm/screenshot.pl` | Perl invoked by key bindings | Captures a full screen or selected region through `scrot` |
| `.config/telescope/config` | Telescope | Enables terminal colors and sets the fill column |
| `.config/tig/config` | tig | Disables Git's own colors and defines tig's ANSI view colors |
| `.config/vifm/vifmrc` | vifm | Selects the companion colorscheme; retains vifm's built-in defaults |
| `.config/vifm/colors/dracula.vifm` | vifm | Assigns file and interface roles to terminal color names |
| `.config/zathura/zathurarc` | Zathura | Sets clipboard/title behavior, UI colors, loading display, and recoloring |
| `.irssi/dracula.theme` | irssi | Overrides named chat-format abstracts; explicit `/theme` activation is required |

### Shell environment

The user and root profile files set a predictable base/Xenocara/ports `PATH`,
hostname fallback, prompt, locale, editor and pager variables, terminal
color variables, history path, vi command editing, and `umask 022`. Only the
`tset` invocation is guarded by the interactive-shell flag. The installed
user profile sets the preferred editor variables but does not install or
invoke those editors.

The X session independently sets its `PATH`, clears inherited `LC_ALL`,
exports locale defaults and XDG directory variables, selects `es` or `us`
keyboard behavior, and starts the graphical session. The installer rewrites
`KEYBOARD_LAYOUT`, `LANG`, and `LC_CTYPE` as whole lines; `LC_COLLATE=C`
remains unchanged. The Spanish `nodeadkeys` variant supplies the `grave`
keysym expected by spectrwm bindings.

### X11 and window manager

`.Xresources` provides the 16-entry ANSI palette, xterm settings, and xlock
and nsxiv colors. ANSI-themed terminal applications inherit this palette;
true-color themes such as Kakoune, mpv, and zathura carry their own RGB
values. `.config/spectrwm/spectrwm.conf` configures command dispatch, native
bar formatting, appearance, workspace count, keyboard bindings, and the
two helper hooks. Its bindings are keysym-oriented and were written for the
Spanish layout; the optional US layout does not remap every binding.

`initscreen.pl` queries `xrandr`, prefers a known internal-panel name, then
uses the first other connected output as an external display. It invokes
`--auto` and places that output to the right. A missing or failing `xrandr`
query is non-fatal. `statusbar.pl` consumes base utility output and prints
one line per cycle; CPU, audio, and throughput update every cycle, memory,
battery, and network state every fifth cycle, and Tor state every fifteenth.
`STATUSBAR_INTERVAL` accepts a positive decimal interval and
`STATUSBAR_BATTERY_LOW` sets a clamped percentage threshold. The bar process
keeps counter baselines in memory. On OpenBSD, it creates `~/.sndio` with
mode 0700 if absent and locks its pathname view with `unveil`; failures to
unveil are fatal. It remains unpledged because it starts external programs.

`screenshot.pl` accepts `full` or `window`, builds a timestamped PNG path
under `~/Pictures/Screenshots`, creates that directory if needed, invokes
`scrot` without a shell, propagates its exit or signal status, and optionally
calls `notify-send`. Its OpenBSD unveil view is locked before launching the
capture program; the helper assumes the local X11 Unix socket and an
accessible Xauthority file. Both screenshot and display helpers use
absolute Xenocara or `/usr/local` executable paths.

### Application and theme settings

The application files are copied by explicit installer entries rather than
being linked into place. Their parser comment forms differ: most accept `#`,
`.Xresources` uses `!`, vifm uses `"`, and `config.jsonc` permits JSONC
comments. Do not add comments to a format unless its own parser accepts them.

The shared theme relationship is that terminal-based themes refer to
8/16-color names provided by `.Xresources`; true-color applications define
their own palette. `.config/git/config` is placed under the XDG Git config
path, which Git reads in addition to its home config. `.irssi/dracula.theme`
is copied but activation is explicit in irssi. cmus may rewrite its `rc`
file when it exits, so the repository copy selects the theme rather than
acting as a complete generated runtime state.

## OpenBSD dependencies and privilege boundaries

The installer depends on base `ksh`, `awk`, `id`, `install`, `chsh`, and
`pkg_add`, plus `doas -C` when the optional rule is requested. It reads the
local `/etc/passwd` database because OpenBSD base does not provide
`getent(1)`. The target account must already exist and have a non-root UID
and a usable home directory. `pkg_add`, file installation, optional doas
configuration, and shell changes require root and have persistent effects.

The Perl desktop helpers use base Perl modules and OpenBSD's base
`OpenBSD::Unveil` conditionally. Their data comes from `sysctl`, `vmstat`,
`apm`, `sndioctl`, `netstat`, `ifconfig`, and `rcctl`; the status helper also
allows the `rcctl` Tor check's shell and rc scripts. They do not configure
network interfaces, PF, services, or kernel parameters. `sort-packages.pl`
reads one manifest, sorts entries bytewise, removes duplicate entries, and
replaces that file atomically from a same-directory temporary file while
preserving mode and ownership. It is a deliberate file-writing utility and
should only be pointed at the intended manifest or a copy.

There are no checked-in credentials, SSH client/server policy files, firewall
rules, address assignments, resolver settings, or service startup fragments
in the tracked runtime inventory. This statement describes repository
contents; it does not assess the host's live configuration.

## Inventory and review status

The tracked runtime inventory contains 23 files under `.config` and
`.irssi` (including three Perl helpers), four profile/session/X resource
source files, one system-session script, four primary Ksh scripts, one Ksh
test driver, and one additional Perl script (`sort-packages.pl`). Within that
set, the configuration formats are reviewed in the preceding sections; the
shell and Perl implementations
are already annotated at their main control-flow and security boundaries.
The following files contain no runtime code and are listed for completeness:
`packages.txt` is a manifest, and `tests/perl_helpers_test.ksh` is a test
driver.

No parser-specific validators are bundled for the third-party application
formats. The safe repository checks are syntax-only checks for shell and
Perl plus a whitespace/diff review. Do not run the installer or apply these
files to the host as a documentation check.
