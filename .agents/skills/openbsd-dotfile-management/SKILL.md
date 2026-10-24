---
name: openbsd-dotfile-management
description: Use when adding, editing, moving, or reviewing dotfiles and theme files in this OpenBSD repository, including source-to-installed path mapping, backups, ownership, and documentation updates.
---

# OpenBSD Dotfile Management

## When to use

Use this skill for repository-wide changes: adding a new application config,
moving a theme file, changing an installed path, reviewing ownership or backup
behavior, or updating `README.md`/`USAGE.md` after a file change. Use
`xenocara-session-config` for session semantics and
`safe-workstation-installation` for running or auditing the installer.

## Source and installed layout

The installer copies repository files into a target user's home or into root
locations. The source path is never the live path.

| Source | Installed path | Owner/mode |
| --- | --- | --- |
| `.config/spectrwm/spectrwm.conf` | `~/.config/spectrwm/spectrwm.conf` | target user, 644 |
| `.config/spectrwm/statusbar.pl` | `~/.config/spectrwm/statusbar.pl` | target user, 755 |
| `.config/spectrwm/initscreen.pl` | `~/.config/spectrwm/initscreen.pl` | target user, 755 |
| `.config/spectrwm/screenshot.pl` | `~/.config/spectrwm/screenshot.pl` | target user, 755 |
| `.config/dunst/dunstrc` | `~/.config/dunst/dunstrc` | target user, 644 |
| `.xsession.ksh` | `~/.xsession` | target user, 755 |
| `.Xresources` | `~/.Xresources` | target user, 644 |
| `.profile.ksh` | `~/.profile` | target user, 644 |
| `root/.profile.ksh` | `/root/.profile` | root:wheel, 644 |
| `xenodm/Xsetup_0.sh` | `/etc/X11/xenodm/Xsetup_0` | root:wheel, 755 |
| `.config/*` themes | matching path under `~/.config` | target user, 644 |
| `.irssi/dracula.theme` | `~/.irssi/dracula.theme` | target user, 644 |

New directories are created by `ensure_dir`: `~/.config` with mode 755 and
the spectrwm/dunst directories with mode 700; theme parent directories use
755. Existing directories keep their current mode and ownership. Existing
target files are backed up as `<name>.old` by `install(1) -b`.

## Procedure

1. Inspect the working tree before touching anything:

   ```sh
   git status --short
   git diff
   ```

2. Find every place the file is referenced: `install.ksh`, `README.md`,
   `USAGE.md`, `packages.txt`, the relevant skill, and any runtime path in a
   config or script. A theme that is not listed in `install_themes` will not
   be installed.
3. Decide whether the file is a user file or a root file. Use
   `install_user_file` for user files and an explicit `install -b -o root -g
   wheel` for root files. Do not install user content as root.
4. If a new directory is needed, call `ensure_dir "$path" <mode>` instead of
   a bare `install -d`. The latter creates missing parents as root and only
   changes the deepest component.
5. Preserve the source file's license or copyright header. Do not add real
   hostnames, account names, keys, tokens, or private addresses.
6. Update the table or prose in `README.md` and the operator details in
   `USAGE.md`. If the installed path or safety rule changed, update
   `AGENTS.md` and the affected skill too.
7. Validate statically; do not run the installer to test a file move.

## Validation

Run each file separately because `ksh -n` and `perl -c` inspect only their
first operand:

```sh
for f in install.ksh .profile.ksh root/.profile.ksh .xsession.ksh; do
    ksh -n "$f" || exit 1
done
for f in .config/spectrwm/*.pl sort-packages.pl; do
    perl -c "$f" || exit 1
done
sh -n xenodm/Xsetup_0.sh
git diff --check
```

Check that every installed source path still exists and that the README/USAGE
references match. The non-root regression suite is
`ksh tests/perl_helpers_test.ksh`; run it only when execution is allowed.

## Common issues

- **Editing the live file instead of the repo.** `~/.profile`, `~/.xsession`,
  and `~/.config` files are replaced on the next install. Change the
  repository source.
- **Recreating parent directories with `install -d`.** It can leave
  `~/.config/mpv` owned by root. Use `ensure_dir`.
- **Assuming a `.old` backup survives.** A later install can overwrite an
  earlier `.old`. Review backups before re-running.
- **Symlinked managed directories.** The installer refuses them on purpose;
  do not "fix" that by following the link as root.
- **Wrong ownership.** Theme files are target-user files; only
  `root/.profile.ksh` and `xenodm/Xsetup_0.sh` are root-owned.
- **Forgetting documentation.** Application additions need a README table
  entry and, when behavior is non-obvious, a USAGE section.

## References

- [`install.ksh`](../../../install.ksh): installation functions and modes.
- [`README.md`](../../../README.md): install effects and theme table.
- [`USAGE.md`](../../../USAGE.md): operator guide.
- [`LICENSE`](../../../LICENSE): ISC terms and copyright.
- [install(1)](https://man.openbsd.org/install.1): `-b`, `-o`, `-g`, `-m`.
