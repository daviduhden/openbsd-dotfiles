# OpenBSD dotfiles

This repository installs a personal OpenBSD/Xenocara desktop based on `ksh`, `xenodm`, `spectrwm` and `dunst`. It is an opinionated workstation configuration, not a generic unattended installer.

## What the installer changes

Run it from the repository root:

```sh
$ doas ./install.ksh
```

The script requires root and requires an existing, non-root target account. When invoked through `doas`, `DOAS_USER` is offered as the default. It then:

- installs every non-comment entry in `packages.txt` with `pkg_add`;
- optionally adds `permit persist user as root` to `/etc/doas.conf`, after checking the complete candidate file with `doas -C`;
- asks for the X keyboard layout: Spanish - Spain (`es`, the default) or
  English - United States (`us`); the choice is written into the installed
  `~/.xsession`, and the matching locale (`es_ES.UTF-8` or `en_US.UTF-8`)
  is written into `~/.xsession`, `~/.profile` and `/root/.profile`
  (`LC_COLLATE=C` is kept);
- installs the spectrwm and dunst files under the target user's
  `~/.config`, including the status script used by the native spectrwm bar;
- writes the Dracula theme files under `~/.config` (and `~/.irssi`), see
  [Dracula themes](#dracula-themes);
- installs `.xsession`, `.Xresources` and `.profile` for that user;
- installs the root profile to `/root/.profile`;
- replaces `/etc/X11/xenodm/Xsetup_0` with the included neutral root-weave setup;
- changes the user's login shell to the base-system `/bin/ksh`.

Existing target files are backed up with the `.old` suffix by OpenBSD
`install(1)`. Unrelated files in `~/.config` are preserved, and ownership
changes are limited to files and directories installed by this script.
Review `.old` files before a later installation overwrites an earlier
backup. Re-running the installer is idempotent for the keyboard layout: the
single `KEYBOARD_LAYOUT=` line in `~/.xsession` is rewritten, never
duplicated.

The doas rule is deliberately interactive because it grants broad root
access. Decline it if the account should have command-specific rules
instead. The package installation and login-shell change are not separately
prompted.

Non-interactive use: setting the environment variable `KEYBOARD_LAYOUT=es`
or `KEYBOARD_LAYOUT=us` preselects the keyboard layout (and the matching
locale) and skips that prompt; any other value is rejected.

## Session behaviour

`.xsession` first sets a predictable `PATH` covering the base system,
Xenocara and the `/usr/local` port prefix (xenodm may start the session
with a minimal environment), then applies the keyboard layout and the
matching locale selected by the installer (`setxkbmap es nodeadkeys` or
`setxkbmap us`, chosen through the `KEYBOARD_LAYOUT` line), loads X
resources, starts `openbsd-wallpaper` and `dunst` when present, then
executes spectrwm. It does not disable the X screen saver or DPMS.
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
`screenshot.pl`) sandbox themselves with `pledge(2)`/`unveil(2)` through
the `OpenBSD::Pledge` and `OpenBSD::Unveil` modules shipped with base
Perl: they unveil only the executables, devices and files each script
demonstrably needs, lock unveil, and pledge `proc exec` (plus the
implied `stdio`). A failing `pledge`/`unveil` call aborts the script
with an explicit error rather than being ignored.

The spectrwm clipboard command explicitly uses `sh -c` because spectrwm executes configured programs directly and does not interpret a pipeline itself. Screenshots use `Mod4+Print` for all monitors and `Mod4+Shift+Print` for an interactive selection.

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
Dracula `LSCOLORS`); set `CLICOLOR=0` in `~/.profile` to turn it off.
The vifm configuration is intentionally minimal (it only selects the
colourscheme), so vifm's default file associations are not shipped.
irssi regenerates `~/.irssi/config`, so only its theme file is shipped:
load it once with `/theme dracula` and keep it with `/save`. htop needs
no theme file: it uses the terminal's ANSI palette, which is already
Dracula.

## Static maintenance checks

On OpenBSD, useful non-executing checks are:

```sh
$ ksh -n install.ksh .profile.ksh root/.profile.ksh .xsession.ksh
$ perl -c .config/spectrwm/initscreen.pl \
    .config/spectrwm/screenshot.pl .config/spectrwm/statusbar.pl
$ sh -n xenodm/Xsetup_0.sh
$ doas -C /etc/doas.conf
```

Spectrwm and Dunst should also be started from a terminal after upgrades so that either program can report configuration keys removed by a newer package version.

## References

- [doas(1)](https://man.openbsd.org/doas.1) and [doas.conf(5)](https://man.openbsd.org/doas.conf.5)
- [install(1)](https://man.openbsd.org/install.1)
- [spectrwm upstream manual](https://github.com/conformal/spectrwm/blob/master/spectrwm.1)
- [Dunst configuration manual](https://github.com/dunst-project/dunst/blob/master/docs/dunst.5.pod)

## License

See [LICENSE](LICENSE).
