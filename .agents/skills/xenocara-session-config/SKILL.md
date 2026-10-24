---
name: xenocara-session-config
description: Use when changing or troubleshooting the OpenBSD Xenocara session, including .xsession, Xresources, Xsetup, keyboard and locale selection, spectrwm, dunst, and the desktop Perl helpers.
---

# Xenocara Session Configuration

## When to use

Use this skill for changes to `.xsession.ksh`, `.Xresources`,
`xenodm/Xsetup_0.sh`, `.config/spectrwm/`, or `.config/dunst/`, and for
diagnosing login, keyboard, locale, bar, screenshot, or notification
behavior. Use `ksh-and-perl-configuration` for code style and helper tests.

## Session flow

1. `xenodm` runs `/etc/X11/xenodm/Xsetup_0` (from `xenodm/Xsetup_0.sh`) to
   paint the login root window with the gray root-weave bitmap.
2. After login, `~/.xsession` (from `.xsession.ksh`) sets a predictable
   `PATH`, clears inherited `LC_ALL`, exports the selected locale, applies
   the keyboard layout, merges `~/.Xresources`, sets the root cursor, starts
   `openbsd-wallpaper` and `dunst` when present, and `exec`s
   `spectrwm -c "$HOME/.config/spectrwm/spectrwm.conf"`.
3. spectrwm runs `~/.config/spectrwm/initscreen.pl` once through `autorun`.
4. `bar_action` starts `~/.config/spectrwm/statusbar.pl`, which loops and
   prints one line per cycle for the native bar.

The repository documents that `Mod+q` restarts spectrwm without re-running
`autorun`, so `initscreen.pl` is not re-executed on restart. Verify that
behavior on the target before relying on it. There is no automatic idle
lock; `Mod+Shift+l` runs `xlock`.

## Keyboard and locale

- `install.ksh` writes a single `KEYBOARD_LAYOUT=es` or `=us` line into
  `~/.xsession` and rewrites `LANG`/`LC_CTYPE` in `~/.xsession`,
  `~/.profile`, and `/root/.profile`. `LC_COLLATE` stays `C`.
- `es` uses `setxkbmap es nodeadkeys`; the grave key then reports `grave`
  instead of `dead_grave`, which the move bindings rely on. `us` uses
  `setxkbmap us` with no variant.
- An unknown `KEYBOARD_LAYOUT` is a fatal session error, not a US fallback.
  Do not restore the old `else setxkbmap us` behavior.
- On `us`, `Mod+apostrophe` still fires on the `'` key. `Mod+Shift+apostrophe`
  requires `quotedbl` and does not fire. `exclamdown`, `masculine`, and
  `ccedilla` have no US physical key.
- The session clears inherited `LC_ALL` before exporting `LANG`,
  `LC_CTYPE`, and `LC_COLLATE`; do not reintroduce an inherited override.

## Spectrwm and dunst

- `spectrwm.conf` targets the OpenBSD package and assumes `/usr/local`.
  `bar_format` uses spectrwm's native bar; there is no Lemonbar.
- `bar_action` is a long-lived Perl process. Keep it single-instance and
  verify with `pgrep -fl 'statusbar\.pl'` after a session. If the installed
  spectrwm re-executes `bar_action` per update instead of reading a stream,
  the loop must be redesigned; verify this on the target rather than
  assuming.
- `statusbar.pl` gathers CPU, volume, memory, battery/AC, network,
  throughput, and Tor state. Throughput reads `netstat -nib -I` and locates
  `Ibytes`/`Obytes` by header name, preferring the `<Link>` row. The
  refresh interval accepts fractional seconds through `select(2)`, not
  `sleep`.
- The bar uses Noto Sans Mono with Noto Color Emoji fallback. Emoji are
  single code points without ZWJ or variation selectors. Missing glyphs
  usually mean the fallback font is unavailable.
- `screenshot.pl` requires `scrot`, saves to `~/Pictures/Screenshots/`, and
  optionally notifies through `notify-send`. The window mode waits with
  `select(2)`; Perl's `sleep` would truncate the fractional delay.
- `statusbar.pl` creates `~/.sndio` with mode 0700 on OpenBSD so the sndio
  cookie directory stays private.
- Dunst uses the Dracula palette, recursive Freedesktop icon lookup, and the
  `hicolor` theme. The `transparency = 0` key is version-sensitive; keep it
  only if the installed dunst accepts it, and remove it after the target
  reports it as unknown.
- `program[clip]` uses an explicit `sh -c` wrapper so the `xclip` pipeline
  is interpreted consistently. `program[menu]` also passes quoted dmenu
  arguments.

## Xsetup and Xresources

- `Xsetup_0.sh` is a neutral login-screen script: it calls
  `/usr/X11R6/bin/xsetroot` with fixed colors and the
  `/usr/X11R6/include/X11/bitmaps/root_weave` bitmap. Verify that bitmap
  exists on the target Xenocara installation; do not add user input or
  shell interpolation.
- `.Xresources` defines the Dracula ANSI palette, xterm font/settings,
  xlock colors, and nsxiv colors. Themes that use ANSI names inherit this
  palette; zathura, kakoune, and mpv use true-color values.

## Validation

Static checks, no X server required:

```sh
ksh -n .xsession.ksh
sh -n xenodm/Xsetup_0.sh
perl -c .config/spectrwm/statusbar.pl
perl -c .config/spectrwm/initscreen.pl
perl -c .config/spectrwm/screenshot.pl
```

Manual checks on the OpenBSD graphical target only:

```sh
setxkbmap -query
xrdb -query | grep -E 'foreground|background|cursorColor'
pgrep -fl 'statusbar\.pl'
```

Open spectrwm and dunst from a terminal once after package upgrades, inspect
`~/.xsession-errors`, and test `Mod+Shift+l` (xlock), `Mod+Print`, and
`Mod+Shift+Print`. Run `statusbar.pl 3` in a terminal to inspect three
cycles; the optional iteration count is documented in `USAGE.md`.

## Common issues

- **Session exits immediately after a manual edit.** Check the
  `KEYBOARD_LAYOUT` value and the ksh syntax of `~/.xsession`.
- **Wrong keyboard characters.** Confirm `setxkbmap -query` matches the
  installed line and that the `es` variant is `nodeadkeys`.
- **Bar field missing.** Run `statusbar.pl 3` and inspect stderr. A missing
  interface, battery, sound server, or Tor service is omitted silently.
- **Throughput never appears.** Check the `netstat -nib -I <iface>` output on
  the target: the parser needs a header row containing `Ibytes` and
  `Obytes` and a data row with those columns.
- **Screenshots fail.** Check `scrot` is installed, the helper is mode 755,
  and the selection pause is a `select(2)` call rather than `sleep 0.2`.
- **Dunst logs unknown options.** Compare against the installed dunst
  version before deleting keys; `transparency` is version-sensitive.
- **Only one status process should exist.** Multiple `statusbar.pl` processes
  indicate that the spectrwm `bar_action` contract differs from the assumed
  persistent-stream behavior.

## References

- [`.xsession.ksh`](../../../.xsession.ksh),
  [`.Xresources`](../../../.Xresources),
  [`xenodm/Xsetup_0.sh`](../../../xenodm/Xsetup_0.sh).
- [`.config/spectrwm/spectrwm.conf`](../../../.config/spectrwm/spectrwm.conf)
  and the three helper scripts in the same directory.
- [`.config/dunst/dunstrc`](../../../.config/dunst/dunstrc).
- [`USAGE.md`](../../../USAGE.md): shortcuts, bar fields, and
  troubleshooting.
- [spectrwm manual](https://github.com/conformal/spectrwm/blob/master/spectrwm.1)
  and [dunst manual](https://github.com/dunst-project/dunst/blob/master/docs/dunst.5.pod).
