# OpenBSD dotfiles

This repository installs a personal OpenBSD/Xenocara desktop based on `ksh`, `xenodm`, `spectrwm` and `dunst`. It is an opinionated workstation configuration, not a generic unattended installer.

## What the installer changes

Run it from the repository root:

```sh
$ doas ./install.ksh
```

The script requires root and an existing, non-root local target account (it
reads `/etc/passwd`). A name with UID 0 (including an alias such as `toor`)
is rejected, and the home directory must exist and must not be `/`. When invoked through `doas`,
`DOAS_USER` is offered as the default. It then:

- prompts for the target account;
- asks for the X keyboard layout: Spanish - Spain (`es`, the default) or
  English - United States (`us`); the choice is written into the installed
  `~/.xsession`, and the matching locale (`es_ES.UTF-8` or `en_US.UTF-8`)
  is written into `~/.xsession`, `~/.profile` and `/root/.profile`
  (`LC_COLLATE=C` is kept);
- optionally adds `permit persist user as root` to `/etc/doas.conf`, after
  checking the complete candidate file with `doas -C`;
- installs every non-comment entry in `packages.txt` with `pkg_add`;
- installs the spectrwm and dunst files under the target user's
  `~/.config`, including the status script used by the native spectrwm bar;
- writes the Dracula theme files under `~/.config` (and `~/.irssi`), see
  [Dracula themes](#dracula-themes);
- installs `.xsession`, `.Xresources` and `.profile` for that user;
- installs the root profile to `/root/.profile`;
- replaces `/etc/X11/xenodm/Xsetup_0` with the included neutral root-weave
  setup;
- changes the user's login shell to the base-system `/bin/ksh`.

The installer remains interactive when the layout is preselected: it still
asks for the target user and for doas permission. `doas` resets the
environment by default, so pass the layout explicitly when needed:
`doas env KEYBOARD_LAYOUT=us ./install.ksh` (or configure
`keepenv`/`setenv`). Any value other than `es` or `us` is rejected before
doas is changed.

Existing target files are backed up with the `.old` suffix by OpenBSD
`install(1)`. Existing directories are left with their current mode and
ownership; new directories are created for the target user. Symlinked
managed directories are refused. Unrelated files in `~/.config` are
preserved, and ownership changes are limited to files and directories
installed by this script. Review `.old` files before a later installation
overwrites an earlier backup. Re-running the installer is idempotent for
the keyboard layout: the single `KEYBOARD_LAYOUT=` line in `~/.xsession`
is rewritten, never duplicated.

The installer is not transactional. A failure after the package, doas or
file-installation steps leaves those earlier changes in place and may leave
a partial configuration; inspect the error and the affected `.old` files
before retrying.

The doas rule is deliberately interactive because it grants broad root
access. Decline it if the account should have command-specific rules
instead. The package installation and login-shell change are not separately
prompted.

`/root/.profile` is read only by shells that read `.profile` (ksh). The
OpenBSD root account normally uses `csh`, so the root profile has no effect
for a normal root login unless root is switched to ksh or starts ksh
explicitly.

For the full operator guide, see [USAGE.md](USAGE.md).

## Session behaviour

`.xsession` first sets a predictable `PATH` covering the base system,
Xenocara and the `/usr/local` port prefix (xenodm may start the session
with a minimal environment), clears any inherited `LC_ALL`, exports the
locale selected by the installer, applies the keyboard layout
(`setxkbmap es nodeadkeys` or `setxkbmap us`, chosen through the
`KEYBOARD_LAYOUT` line), loads X resources, starts `openbsd-wallpaper` and
`dunst` when present, then executes spectrwm. An unknown
`KEYBOARD_LAYOUT` value aborts the session instead of silently falling
back to `us`. The session does not disable the X screen saver or DPMS.
`Mod4+Shift+L` invokes `xlock`; no automatic idle lock is configured.

The status bar is spectrwm's native bar. Workspaces and the focused window
title are rendered by spectrwm itself, and the date and time come from the
`bar_format` string; the `bar_action` script
[`.config/spectrwm/statusbar.pl`](.config/spectrwm/statusbar.pl) adds
CPU, audio volume, memory, battery/AC, network, throughput and Tor status on
staggered refresh tiers (CPU, volume and throughput every 2 seconds, the rest
every 10 to 30 seconds), using only OpenBSD base utilities. Each field is
tagged with a single-codepoint emoji, rendered through the `Noto Color Emoji`
(`noto-emoji` package) fallback declared in `bar_font`; the calendar and
clock markers in `bar_format` use the same fallback. There is no external
bar: Lemonbar is neither installed nor started.

On OpenBSD, the spectrwm helper scripts (`statusbar.pl`, `initscreen.pl`,
`screenshot.pl`) restrict their own pathname access through
`OpenBSD::Unveil` from base Perl. They unveil the executables, devices and
files each script needs, then lock the view. They stay unpledged because
they execute external programs. The locked unveil view is inherited across
`execve(2)`; children receive the unveiled library paths and may apply
their own pledge policy. There is no launcher syscall ceiling. A failing
`unveil` call aborts the script with an explicit error rather than being
ignored.

The clipboard command uses an explicit `sh -c` wrapper so the pipeline is
interpreted consistently regardless of how spectrwm dispatches
`program[...]` entries. Screenshots use `Mod4+Print` for all monitors and
`Mod4+Shift+Print` for an interactive selection.

The configuration assumes the package prefix `/usr/local`. Dunst uses its recursive Freedesktop icon lookup with the `hicolor` theme instead of a Linux-specific `/usr/share/icons` path.

## Dracula themes

The palette is Dracula everywhere, and every theme file lives in this
repository. Themes that rely on the terminal use the 8/16 ANSI colour
names, which `.Xresources` maps to the Dracula colours; zathura,
kakoune and mpv use true-colour values.

| Application | File |
| --- | --- |
| xterm | `.Xresources` (`color0`-`color15`, foreground, background, cursor) |
| dmenu | `program[menu]` in `.config/spectrwm/spectrwm.conf` |
| spectrwm | `.config/spectrwm/spectrwm.conf` |
| dunst | `.config/dunst/dunstrc` |
| xlock / nsxiv | `XLock.*` / `Nsxiv.*` in `.Xresources` |
| less / ls / tree | `LESS_TERMCAP_*` / `LSCOLORS`+`LS_COLORS` in `.profile.ksh` |
| vifm | `.config/vifm/vifmrc` + `colors/dracula.vifm` |
| kakoune | `.config/kak/kakrc` + `colors/dracula.kak` |
| NeoMutt | `.config/neomutt/neomuttrc` + `dracula.muttrc` |
| tig | `.config/tig/config` |
| zathura | `.config/zathura/zathurarc` |
| cmus | `.config/cmus/rc` + `dracula.theme` |
| mpv | `.config/mpv/mpv.conf` + `script-opts/osc.conf` |
| profanity | `.config/profanity/profrc` + `themes/dracula` |
| fastfetch | `.config/fastfetch/config.jsonc` |
| telescope | `.config/telescope/config` |
| git | `.config/git/config` (read before `~/.gitconfig`) |
| irssi | `.irssi/dracula.theme` |

`ls` colour output is enabled by the installer (`CLICOLOR=1` with a
Dracula `LSCOLORS`); set `CLICOLOR=0` in `.profile.ksh` to turn it off.
The installed `~/.profile` is replaced on every installer run, so the
repository copy is authoritative.
The vifm configuration is intentionally minimal (it only selects the
colourscheme), so vifm's default file associations are not shipped.
irssi regenerates `~/.irssi/config`, so only its theme file is shipped:
load it once with `/theme dracula` and keep it with `/save`. htop needs
no theme file: it uses the terminal's ANSI palette, which is already
Dracula.

Chromium is the one themed application the installer cannot configure:
browser themes are installed from the Web Store. Add the
[Dracula Chrome theme](https://chrome.google.com/webstore/detail/dracula-chrome-theme-dark/gfapcejdoghpoidkfodoiiffaaibpaem)
manually; see [draculatheme.com/google-chrome](https://draculatheme.com/google-chrome).

## Static maintenance checks

On OpenBSD, useful non-executing checks are:

```sh
$ for f in install.ksh .profile.ksh root/.profile.ksh .xsession.ksh; do
    ksh -n "$f" || exit 1
done
$ for f in .config/spectrwm/*.pl sort-packages.pl; do
    perl -c "$f" || exit 1
done
$ sh -n xenodm/Xsetup_0.sh
$ doas -C /etc/doas.conf   # read access, normally root
```

`ksh -n` and `perl -c` inspect only their first file operand, which is why
the checks above use a loop. The Perl helper regression tests run in a
temporary directory with a fake `scrot` and need no root privileges:

```sh
$ ksh tests/perl_helpers_test.ksh
```

The suite covers `sort-packages.pl` and `screenshot.pl`; `statusbar.pl` and
`initscreen.pl` have no automated coverage yet. Spectrwm and Dunst should
also be started from a terminal after upgrades so that either program can
report configuration keys removed by a newer package version.

## References

- [doas(1)](https://man.openbsd.org/doas.1) and [doas.conf(5)](https://man.openbsd.org/doas.conf.5)
- [install(1)](https://man.openbsd.org/install.1)
- [spectrwm upstream manual](https://github.com/conformal/spectrwm/blob/master/spectrwm.1)
- [Dunst configuration manual](https://github.com/dunst-project/dunst/blob/master/docs/dunst.5.pod)

## License

See [LICENSE](LICENSE). Installed files keep the repository-relative license
notice; keep a checkout or a copy of `LICENSE` when redistributing them.
