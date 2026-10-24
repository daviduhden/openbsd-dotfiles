# Agent Instructions

This repository is an opinionated OpenBSD/Xenocara workstation configuration:
a root-only installer, an OpenBSD package manifest, a spectrwm/dunst desktop,
X session files, and a set of Dracula theme files. It is not a generic
unattended installer and it is not a Linux dotfiles collection.

Read `README.md` for the user-facing install and session behavior. Read
`USAGE.md` for the spectrwm operator guide. This file is the short contract
for agents; the detailed procedures live in `.agents/skills/`.

## Architecture

| Path | Role |
| --- | --- |
| `install.ksh` | Root-only orchestrator: target validation, optional doas rule, package install, file install, layout/locale rewrite, shell change. |
| `packages.txt` | One non-comment package per line; `#` comments and blank lines are ignored. |
| `sort-packages.pl` | Sorts and de-duplicates `packages.txt` atomically, preserving mode and ownership. |
| `.config/spectrwm/` | `spectrwm.conf` plus the Perl helpers `statusbar.pl`, `initscreen.pl`, and `screenshot.pl`. |
| `.config/dunst/` | Dunst notification configuration. |
| `.xsession.ksh` | Installed as `~/.xsession`; environment, keyboard, locale, Xresources, wallpaper, dunst, spectrwm. |
| `.Xresources` | Installed as `~/.Xresources`; Dracula palette and xterm/xlock/nsxiv settings. |
| `.profile.ksh` | Installed as the target user's `~/.profile`. |
| `root/.profile.ksh` | Installed as `/root/.profile`; only read by ksh logins. |
| `xenodm/Xsetup_0.sh` | Installed as `/etc/X11/xenodm/Xsetup_0`; root-weave login background. |
| `.config/*`, `.irssi/` | Theme and application files installed under the target user's home. |
| `tests/perl_helpers_test.ksh` | Non-root regression suite for `sort-packages.pl` and `screenshot.pl`. |
| `README.md`, `USAGE.md`, `LICENSE` | User documentation, operator guide, and ISC license. |

The repository source path is not the installed path. User files are copied
into the target user's `$HOME`; root files go to `/root` and
`/etc/X11/xenodm`. The installer uses `install(1) -b`, so existing targets
become `.old` backups.

## Conventions

- Target OpenBSD base plus Xenocara, with ports under `/usr/local`. Do not
  introduce Linux-only paths, GNU-only flags, or Linux desktop daemon
  assumptions.
- Shell is OpenBSD `/bin/ksh`; `xenodm/Xsetup_0.sh` is `/bin/sh`; helpers are
  base `/usr/bin/perl`. Keep `set -e`, quote expansions, and use `print` in
  ksh scripts.
- Perl helpers use `strict`, `warnings`, absolute command paths, and
  `OpenBSD::Unveil` on OpenBSD. Do not add CPAN dependencies.
- Documentation is US English. Update `README.md` and `USAGE.md` when behavior
  or a user-visible path changes.
- Preserve copyright and license headers. Do not add real hostnames,
  usernames beyond the existing project owner, keys, tokens, passwords, or
  private addresses.
- Prefer the smallest change that fits the existing structure. New runtime
  dependencies need a `packages.txt` entry and a documentation update.

## Installer and security policy

- `doas ./install.ksh` requires root and an existing non-root local target
  account. UID 0 aliases such as `toor` and numeric IDs are rejected. The
  home directory must exist and must not be `/`.
- The installer prompts for the target user, the X keyboard layout (`es`
  default or `us`), and optionally a broad
  `permit persist <user> as root` doas rule. `KEYBOARD_LAYOUT` only skips the
  layout prompt; the other prompts remain.
- It installs packages, writes user/root files, backs up replaced files as
  `.old`, leaves existing directories with their current mode and ownership,
  creates missing directories for the target user, and refuses symlinked
  managed directories. It changes the target login shell and replaces
  `Xsetup_0`.
- The installer is not transactional. A failure after packages, doas, or file
  installation leaves earlier changes in place.
- Agents must not run `install.ksh`, `pkg_add`, `chsh`, `doas`, or destructive
  X/desktop tests unless the user explicitly authorizes it on an OpenBSD
  target. The default mode for this repository is static analysis.
- Do not edit `/etc/doas.conf` by hand in a repository task. The installer
  builds and validates a candidate with `doas -C`; review that behavior
  instead.
- `/root/.profile` has no effect on a normal root login when root still uses
  `csh`. Document that limitation rather than silently changing root's shell.

## Validation

There is no Makefile and no CI configuration. Use these real checks; run each
file separately because `ksh -n` and `perl -c` only inspect their first file
operand:

```sh
for f in install.ksh .profile.ksh root/.profile.ksh .xsession.ksh; do
    ksh -n "$f" || exit 1
done
for f in .config/spectrwm/*.pl sort-packages.pl; do
    perl -c "$f" || exit 1
done
sh -n xenodm/Xsetup_0.sh
```

The regression suite is non-root and uses a temporary directory and a fake
`scrot`:

```sh
ksh tests/perl_helpers_test.ksh
```

It covers `sort-packages.pl` and `screenshot.pl`; `statusbar.pl` and
`initscreen.pl` have no automated coverage. `doas -C /etc/doas.conf` parses
the live doas configuration but does not change it; it is OpenBSD-only and
needs read access, normally as root.
Starting spectrwm or dunst from a terminal and inspecting
`~/.xsession-errors` are manual target checks, not repository tests.

When a request says static analysis only, do not run the test suite or any
script. Read the code, run `git diff --check`, and inspect the diff instead.

## Pre-existing changes

- Run `git status --short` and `git diff` before editing. Do not revert or
  rewrite unrelated user changes.
- Treat unknown files in `~/.config`, `.old` backups, and user-modified
  installed files as user data. Never delete them to make a check pass.
- If a change alters installer behavior, update the affected skill and both
  user documents. If a defect needs an OpenBSD runtime check that static
  analysis cannot provide, record it as pending instead of guessing.

## Skills

- [openbsd-dotfile-management](.agents/skills/openbsd-dotfile-management/SKILL.md):
  repository map, source-to-installed paths, backups, ownership, and adding
  files or themes.
- [safe-workstation-installation](.agents/skills/safe-workstation-installation/SKILL.md):
  preflight, installer review, doas, packages, recovery, and non-destructive
  validation.
- [xenocara-session-config](.agents/skills/xenocara-session-config/SKILL.md):
  `.xsession`, Xresources, Xsetup, keyboard/locale, spectrwm, dunst, and the
  Perl desktop helpers.
- [ksh-and-perl-configuration](.agents/skills/ksh-and-perl-configuration/SKILL.md):
  ksh style, Perl helpers, temp files, sandboxing, and the regression suite.
- [package-manifest-and-secrets](.agents/skills/package-manifest-and-secrets/SKILL.md):
  `packages.txt`, `sort-packages.pl`, package flavors, secret scanning, and
  license handling.

See [LICENSE](LICENSE) for copyright and license details.
