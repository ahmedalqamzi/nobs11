# Release checklist

## Repository

- [x] Native Explorer taskbar is the only active shell bar
- [x] Retired Zebar/Notch implementation and vendored binary assets removed
- [x] Startup enforcement uses explicit blocklists and preserves unlisted entries
- [x] Persistent Appx removal is opt-in
- [x] PowerShell 7 launcher works when `pwsh.exe` is absent from `PATH`
- [x] Curated dependency manifests contain no personal application inventory
- [x] Generated identity-bearing reports and backups remain ignored
- [x] Verification output is redacted by default
- [x] Public files contain no local username, hostname, email, profile path, private key, or common access-token format
- [x] Bootstrap repository ownership is caller-supplied rather than hard-coded to a personal account
- [x] Windows CI and local repository validation added
- [x] Choose and add the root project license (MIT)
- [x] Record exact upstream revisions reviewed for policy inspiration
- [ ] Configure a public Git author identity and replace the unpublished local-history metadata
- [ ] Create the public remote only after the sanitized history is ready

## Validation

- [x] Run `make preflight`
- [x] Run `make check`
- [x] Run `make audit`
- [x] Run `make verify` and require zero failures
- [x] Explicitly accept the prior elevated cleanup's four recorded failures: no restore point was exposed and three protected/obsolete Explorer writes were skipped; none are required by the standard profile
- [ ] Test a clean clone in a separate Windows user or disposable Windows test machine
- [ ] Complete the manual hardware and gaming sign-off in `TESTED-CONFIGURATION.md`
- [x] Review `git diff --check` and the complete working-tree diff
- [ ] Build the release archive with `git archive`, not by zipping the working directory

## Release metadata

- [x] Update `CHANGELOG.md`
- [ ] Commit the release candidate
- [ ] Tag the first public preview as `v0.1.0`
- [ ] Confirm that GitHub detects the chosen license and CI passes
- [ ] Enable GitHub private vulnerability reporting and add the final public security contact link
