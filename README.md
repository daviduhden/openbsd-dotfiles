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
  `~/.xsession`;
- installs the spectrwm and dunst files under the target user's
  `~/.config`, including the status script used by the native spectrwm bar;
- installs `.xsession`, `.Xresources` and `.profile` for that user;
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
or `KEYBOARD_LAYOUT=us` preselects the keyboard layout and skips that
prompt; any other value is rejected.

## Session behaviour

`.xsession` applies the keyboard layout selected by the installer
(`setxkbmap es nodeadkeys` or `setxkbmap us`, chosen through the
`KEYBOARD_LAYOUT` line), loads X resources, starts `openbsd-wallpaper` and
`dunst` when present, then executes spectrwm. It does not disable the X
screen saver or DPMS. `Mod4+Shift+L` invokes `xlock`; no automatic idle
lock is configured.

The status bar is spectrwm's native bar. Workspaces and the focused window
title are rendered by spectrwm itself, and the date and time come from the
`bar_format` string; the `bar_action` script
[`.config/spectrwm/statusbar.ksh`](.config/spectrwm/statusbar.ksh) adds
CPU, memory, battery/AC, network, throughput and Tor status on staggered
refresh tiers (CPU and throughput every 2 seconds, the rest every 10 to 30
seconds), using only OpenBSD base utilities. There is no external bar:
Lemonbar is neither installed nor started.

The spectrwm clipboard command explicitly uses `sh -c` because spectrwm executes configured programs directly and does not interpret a pipeline itself. Screenshots use `Mod4+Print` for all monitors and `Mod4+Shift+Print` for an interactive selection.

The configuration assumes the package prefix `/usr/local`. Dunst uses its recursive Freedesktop icon lookup with the `hicolor` theme instead of a Linux-specific `/usr/share/icons` path.

## Static maintenance checks

On OpenBSD, useful non-executing checks are:

```sh
$ ksh -n install.ksh .profile.ksh .xsession.ksh \
    .config/spectrwm/initscreen.ksh .config/spectrwm/screenshot.ksh \
    .config/spectrwm/statusbar.ksh
$ sh -n xenodm/Xsetup_0.sh
$ doas -C /etc/doas.conf
```

The mock-based regression suite exercises the status script against the
verified OpenBSD command output formats and the installer keyboard-layout
logic; it needs no root privileges and touches nothing outside its
temporary directory:

```sh
$ ksh tests/statusbar_test.ksh
```

Spectrwm and Dunst should also be started from a terminal after upgrades so that either program can report configuration keys removed by a newer package version.

## References

- [doas(1)](https://man.openbsd.org/doas.1) and [doas.conf(5)](https://man.openbsd.org/doas.conf.5)
- [install(1)](https://man.openbsd.org/install.1)
- [spectrwm upstream manual](https://github.com/conformal/spectrwm/blob/master/spectrwm.1)
- [Dunst configuration manual](https://github.com/dunst-project/dunst/blob/master/docs/dunst.5.pod)

## License

See [LICENSE](LICENSE).
