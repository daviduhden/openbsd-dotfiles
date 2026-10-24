---
name: package-manifest-and-secrets
description: Use when editing packages.txt or sort-packages.pl, checking OpenBSD package names and flavors, scanning the repository for secrets or private host data, or reviewing license and publication hygiene.
---

# Package Manifest and Secrets

## When to use

Use this skill for `packages.txt`, `sort-packages.pl`, package additions or
removals, dependency documentation, pre-publication checks, and any review
that could expose hostnames, accounts, keys, tokens, or private paths.

## Manifest rules

- `packages.txt` has one package per line. Blank lines and lines whose first
  non-space character is `#` are ignored. Do not add inline comments after a
  package name; the loader takes the first field only.
- Keep the file bytewise sorted with comments at the top. Use
  `sort-packages.pl`:

  ```sh
  perl sort-packages.pl
  perl sort-packages.pl path/to/packages.txt
  ```

- The sorter reads the file once, closes it, writes a temporary file in the
  same directory, preserves the original mode and ownership, and renames it
  atomically. It removes duplicates. A failed write must not replace the
  original.
- OpenBSD empty-flavor names end in `--`, for example `nsh--` and `unzip--`.
  Flavored names use the package's documented suffix, for example
  `neomutt--gpgme-sasl-notmuch`. Do not "normalize" these to a guessed name.
- `pkg_add` is invoked with `--` so a leading dash cannot be interpreted as
  an option. The installer is not transactional: a bad entry aborts the
  package loop after earlier packages were installed.
- Add a package only when the corresponding config, script, or documented
  feature actually needs it. Update `README.md` or `USAGE.md` when a package
  is a user-visible dependency.

## Verification

Static review:

```sh
perl -c sort-packages.pl
perl sort-packages.pl /tmp/packages-copy.txt
```

If you use the sorter, operate on a copy unless the task is to update the
real manifest. Check that comments remain at the top, entries are sorted,
duplicates are gone, and no `.packages-*` temporary file remains.

Package existence and exact flavor sets cannot be proven offline. On the
OpenBSD target, verify with the package tools, for example:

```sh
pkg_info -Q <name>
```

Treat `rate-mirrors`, `truncate`, and other unfamiliar entries as unverified
until the target package index confirms them. `nsh--` and `unzip--` are
consistent with OpenBSD empty-flavor syntax but still need target
verification.

The regression suite exercises the sorter:

```sh
ksh tests/perl_helpers_test.ksh
```

Run it only when execution is allowed; it is non-root and uses a temporary
directory.

## Secrets and privacy review

Before publishing or committing, scan the working tree and the diff. Do not
print a matched secret in full; redact it in notes and reports.

- Credentials: `api_key`, `apikey`, `token`, `secret`, `password`, `passwd`,
  `Authorization:`, and private-key headers.
- Keys and certificates: `BEGIN OPENSSH PRIVATE KEY`, `BEGIN RSA PRIVATE
  KEY`, `BEGIN EC PRIVATE KEY`, `BEGIN PRIVATE KEY`.
- Personal data: real hostnames, internal DNS names, MAC addresses, private
  IP addresses, account names, and email addresses not already present in
  the project license.
- Shell history, browser profiles, SSH configs, and files under `.ssh`,
  `.gnupg`, or similar must not be added.

The only known personal identifier in the repository is the project owner's
copyright line in `LICENSE`; do not expand it with hostnames, keys, or
additional addresses. Configuration examples should use generic values.

## License and publication

- `LICENSE` is ISC, copyright 2025-2026. Preserve it and all per-file
  notices.
- Installed copies retain references to the repository's `LICENSE`; keep the
  repository checkout or a copy of the license when redistributing.
- New files should carry the same short notice style as their neighbors.
  Do not remove a copyright header while rewriting a file.
- Do not add a package or script whose license is incompatible with the ISC
  project terms.

## Common issues

- **Unsorted manifest after a manual edit.** Run the sorter; do not hand-sort
  case-sensitively or use locale-dependent ordering.
- **Duplicate package.** The sorter removes exact duplicates, but review the
  diff to ensure the removal was intentional.
- **Wrong flavor.** `pkg_add` fails or installs an unexpected package. Verify
  the flavor on the target instead of guessing from the name.
- **Sorter ownership drift.** Running as root on a user-owned manifest must
  not leave the file root-owned; the script now preserves UID/GID.
- **Comment loss.** The sorter hoists comments to the top; do not rely on
  inline comments or comment position for semantics.
- **Secret in a diff.** Stop, remove it, rotate the credential if it was
  real, and do not repeat it in the report.

## References

- [`packages.txt`](../../../packages.txt) and
  [`sort-packages.pl`](../../../sort-packages.pl).
- [`LICENSE`](../../../LICENSE).
- [pkg_add(1)](https://man.openbsd.org/pkg_add.1) and
  [pkg_info(1)](https://man.openbsd.org/pkg_info.1).
- [OpenBSD ports flavors](https://www.openbsd.org/faq/ports/specialtopics.html).
