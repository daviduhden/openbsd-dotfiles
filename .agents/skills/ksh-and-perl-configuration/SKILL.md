---
name: ksh-and-perl-configuration
description: Use when editing the ksh installer or profiles, the Perl desktop helpers, the package sorter, or their regression tests, including temp files, sandboxing, exit status, and static validation.
---

# ksh and Perl Configuration

## When to use

Use this skill for `install.ksh`, `.profile.ksh`, `root/.profile.ksh`,
`.xsession.ksh`, `sort-packages.pl`, or
`.config/spectrwm/*.pl`, and for changes to
`tests/perl_helpers_test.ksh`. Use `xenocara-session-config` for what the
session scripts should do, and `package-manifest-and-secrets` for package
contents and secret handling.

## ksh rules

- Shebang is `/bin/ksh` on OpenBSD. Do not use bash-only syntax, arrays from
  bash, `[[ ... ]]`, or process substitution.
- Keep `set -e` in `install.ksh` and the test suite. Check command failures
  explicitly when a pipeline would otherwise mask them.
- Quote expansions. Use `print` (ksh) rather than `echo` for portable output,
  and `print -u2` for errors.
- Use `typeset` for function-local variables where needed. `ensure_dir` is
  recursive and must not inherit a caller's `dir`/`parent`.
- Create temporary files with `mktemp` and remove them with an `EXIT`/signal
  trap. Do not leave `/tmp/doas.conf.*` or a `.dotfiles.*` file in the
  destination directory behind on a failure.
- Do not use `getent` on OpenBSD; read `/etc/passwd` with `awk -F:`. Validate
  UID 0 aliases and numeric IDs instead of trusting `id` alone.
- Use `pkg_add -- "$pkg"` so a manifest entry beginning with `-` cannot be
  parsed as an option.
- Preserve owner and mode when rewriting an installed file. Write to a
  temporary file, `chown`, `chmod`, then `mv`.

## Perl rules

- Every helper starts with `use strict; use warnings;` and uses base Perl
  only. Do not add CPAN modules.
- Use absolute paths for external commands (`/usr/bin/netstat`,
  `/usr/sbin/apm`, `/usr/local/bin/scrot`). Keep `/usr/local` for ports.
- OpenBSD helpers use `OpenBSD::Unveil` with a trailing `unveil()` lock.
  A failing unveil is fatal. The launchers stay unpledged because they
  execute programs; the locked unveil view is inherited across `execve(2)`,
  so children still need the unveiled library paths.
- Prefer named-column parsing over fixed field counts. `statusbar.pl` locates
  `Ibytes`/`Obytes` from the `netstat` header; do not reintroduce a
  six-field assumption.
- Perl's `sleep` truncates fractional seconds. Use
  `select undef, undef, undef, $seconds` when a fractional delay is
  required, as in `statusbar.pl` and `screenshot.pl`. Keep a local
  `ProhibitSleepViaSelect` Perl::Critic suppression on these calls: they
  intentionally preserve fractional delays without adding a dependency.
- Propagate child failures. `screenshot.pl` distinguishes exit status,
  signal death, and a missing command; preserve that behavior.
- `sort-packages.pl` writes atomically in the source directory, preserves
  mode and ownership, and cleans up through `File::Temp` on failure.

## Procedure

1. Read the current script and the documentation that describes it.
2. Make the smallest change that preserves the existing interfaces and
   output format.
3. Add or update a regression test when the behavior is testable without
   root, X, or OpenBSD-specific hardware. The current suite's pattern is a
   temporary directory, a fake `scrot`, and a copied helper with the sandbox
   disabled.
4. Update `README.md`, `USAGE.md`, `AGENTS.md`, or this skill when a command,
   path, default, or safety rule changes.
5. Do not run the script under test as root. Do not run the installer,
   `pkg_add`, `chsh`, or `doas`.

## Validation

Static, per file:

```sh
for f in install.ksh .profile.ksh root/.profile.ksh .xsession.ksh; do
    ksh -n "$f" || exit 1
done
for f in .config/spectrwm/*.pl sort-packages.pl; do
    perl -c "$f" || exit 1
done
```

`ksh -n file1 file2` and `perl -c file1 file2` only inspect the first file;
never document the multi-file form as a full check.

When execution is allowed, the non-root regression suite is:

```sh
ksh tests/perl_helpers_test.ksh
```

It covers `sort-packages.pl` (sorting, duplicate removal, comments, mode and
ownership preservation, temp cleanup, missing input) and `screenshot.pl`
(success, scrot exit code, signal status, invalid mode, unset `HOME`).
`statusbar.pl` and `initscreen.pl` are not covered automatically.

## Common issues

- **A syntax error passes review.** The documented multi-file `ksh -n` or
  `perl -c` recipe checks only the first path. Use a loop.
- **A failed pipeline looks successful.** `set -e` does not fail on a
  non-zero command in the middle of a pipeline. Check the pipeline or avoid
  it.
- **Temp files leak.** Every `mktemp` path needs a trap or explicit cleanup
  on every exit path.
- **Fractional sleeps are ignored.** Replace `sleep 0.2` with `select`.
- **Child processes lose library access.** Do not assume `execve` clears the
  unveil view; it is inherited.
- **Ownership changes on sorting.** `sort-packages.pl` must `chown` the
  temporary file before `rename`, not only `chmod`.
- **Root-owned parent directories.** Use `ensure_dir`, not a bare
  `install -d` with a nested destination.

## References

- [`install.ksh`](../../../install.ksh) and the ksh profiles.
- [`sort-packages.pl`](../../../sort-packages.pl) and
  [`tests/perl_helpers_test.ksh`](../../../tests/perl_helpers_test.ksh).
- [`statusbar.pl`](../../../.config/spectrwm/statusbar.pl),
  [`screenshot.pl`](../../../.config/spectrwm/screenshot.pl), and
  [`initscreen.pl`](../../../.config/spectrwm/initscreen.pl).
- [OpenBSD::Unveil](https://man.openbsd.org/OpenBSD::Unveil.3p),
  [unveil(2)](https://man.openbsd.org/unveil.2), and
  [pledge(2)](https://man.openbsd.org/pledge.2).

## Maintenance & Continuous Learning

Whenever this skill is used to change the repository, review this skill after
the implementation. Correct procedures that proved wrong, update commands,
paths, configuration and examples, incorporate reusable findings, and remove
outdated assumptions. Review the applicable root and nested `AGENTS.md` files,
specialized agents and related skills; update only the knowledge affected by
the work. Validate local references and run
`python3 scripts/validate-agent-knowledge.py --scope worktree` plus the
applicable project checks. For pull request comparisons, use the documented
`--scope range --base BASE_REF --head HEAD_REF` command. The canonical validator
is read-only and is required even when a task restricts execution of project
scripts; this does not authorize running installers or changing the host.
Report checks actually performed. A structural pass does not prove semantic
relevance, and a task is incomplete until synchronization is validated.
