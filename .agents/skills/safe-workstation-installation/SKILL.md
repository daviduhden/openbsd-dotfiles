---
name: safe-workstation-installation
description: Use when planning, reviewing, or recovering an installation of this OpenBSD workstation configuration, including preflight checks, the doas rule, package installation, backups, and non-destructive verification.
---

# Safe Workstation Installation

## When to use

Use this skill before changing `install.ksh`, before advising a user to run
it, when reviewing its behavior, or when recovering from a partial install.
The installer is an opinionated, interactive, root-only operation. It is not
an unattended provisioning tool.

## Preflight (static, no root)

Read the code and the target state before running anything:

1. `git status --short` and `git diff` to separate your changes from
   pre-existing work.
2. Confirm the target account is local, exists in `/etc/passwd`, has a
   non-zero UID, and has a real home directory other than `/`. The installer
   rejects UID 0 aliases such as `toor` and numeric IDs that do not name an
   account.
3. Confirm `packages.txt` is sorted and has no duplicates or invalid
   comments; see `package-manifest-and-secrets`.
4. Confirm every source path referenced by `install.ksh` exists, and that
   `README.md` describes the current effects.
5. Inspect `/etc/doas.conf` read-only. The installer offers a broad
   `permit persist <user> as root` rule and validates the complete candidate
   with `doas -C`. Decline it when command-specific rules are required.
6. Check for existing `.old` backups and for user-modified files under
   `~/.config`, `~/.irssi`, `~/.xsession`, `~/.Xresources`, and `~/.profile`.
   The installer backs up replaced files but does not merge them.

## Installation procedure

Run from the repository root on the OpenBSD target, with explicit user
authorization:

```sh
doas ./install.ksh
```

The expected order is: target user prompt, keyboard layout prompt, optional
doas prompt, package installation, directory/file installation, root profile,
session files, themes, layout/locale rewrite, and `chsh` to `/bin/ksh`.
`KEYBOARD_LAYOUT=es` or `KEYBOARD_LAYOUT=us` skips only the layout prompt.
Because `doas` resets the environment, use:

```sh
doas env KEYBOARD_LAYOUT=us ./install.ksh
```

Do not run this in an agent session unless the user explicitly requests it
and the host is the intended OpenBSD target. There is no safe way to exercise
`pkg_add`, `chsh`, or the `/etc/X11/xenodm/Xsetup_0` replacement on a
non-OpenBSD machine.

## After installation

1. Log out and back in so the new shell and `~/.xsession` take effect.
2. Confirm `getent` is not needed; the installer reads `/etc/passwd`
   directly.
3. Check `~/.xsession`, `~/.profile`, `/root/.profile`, and the selected
   locale. `LC_COLLATE` stays `C`; an unknown layout aborts the session.
4. Review any `.old` files before a second run overwrites them.
5. Check `doas -C /etc/doas.conf` and confirm the rule is the one intended.
6. Start spectrwm and dunst from a terminal once to catch unknown
   configuration keys; inspect `~/.xsession-errors`.

## Recovery

- Restore a replaced file from its `.old` sibling with the original owner and
  mode. Do not copy root-owned backups into a user's home without changing
  ownership.
- Package installation is not rolled back by the script. Remove packages only
  with explicit authorization and a package audit.
- The doas rule is not removed automatically. Edit `/etc/doas.conf` only with
  authorization and validate the result with `doas -C`.
- Restore the previous login shell with `chsh` if the ksh change was not
  intended.
- A failure after packages or doas leaves a partial install. Re-run only
  after understanding which steps already completed.

## Validation

Static checks are safe and do not require root:

```sh
for f in install.ksh .profile.ksh root/.profile.ksh .xsession.ksh; do
    ksh -n "$f" || exit 1
done
for f in .config/spectrwm/*.pl sort-packages.pl; do
    perl -c "$f" || exit 1
done
sh -n xenodm/Xsetup_0.sh
```

The regression suite `ksh tests/perl_helpers_test.ksh` is non-root and
temporary-directory based. `doas -C /etc/doas.conf` is a parse check, not an
install test. There is no Makefile or CI.

## Common issues

- **`/root/.profile` appears inert.** OpenBSD root normally uses `csh`, which
  does not read `.profile`. The file only affects ksh root logins.
- **Re-running the installer.** Package installation is not skipped
  explicitly; a package already present may still produce output. The layout
  rewrite is idempotent, but `.old` files can be overwritten.
- **Existing directory modes.** The installer now leaves existing
  directories alone and creates missing ones for the target user. Do not
  reintroduce a bare `install -d` on a path below a user's home.
- **Symlinked directories.** Managed symlinks are refused to avoid root
  writing through them. Resolve the user's layout instead of bypassing the
  check.
- **Broad doas access.** The generated rule grants full root via doas. Treat
  it as a security decision, not a convenience default.
- **No transaction.** A failed run is not rolled back. Inspect `.old` files
  and package state before retrying.

## References

- [`install.ksh`](../../../install.ksh): target validation, doas, package and
  file installation.
- [`README.md`](../../../README.md): documented effects and non-interactive
  behavior.
- [doas(1)](https://man.openbsd.org/doas.1) and
  [doas.conf(5)](https://man.openbsd.org/doas.conf.5).
- [install(1)](https://man.openbsd.org/install.1): backup suffix and
  ownership/mode semantics.
- [pkg_add(1)](https://man.openbsd.org/pkg_add.1): package installation.
