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
- [x] Bootstrap accepts an explicit repository override and defaults to the official NoBS11 repository
- [x] Windows CI and local repository validation added
- [x] Choose and add the root project license (MIT)
- [x] Record exact upstream revisions reviewed for policy inspiration
- [x] Configure a public Git author identity and replace the unpublished local-history metadata
- [x] Create the public remote only after the sanitized history is ready

## Validation

- [x] Run `make preflight`
- [x] Run `make check`
- [x] Run `make audit`
- [x] Run `make verify` and require zero failures
- [x] Explicitly accept the prior elevated cleanup's four recorded failures: no restore point was exposed and three protected/obsolete Explorer writes were skipped; none are required by the standard profile
- [ ] Test a clean clone in a separate Windows user or disposable Windows test machine
- [ ] Complete the manual hardware and gaming sign-off in `TESTED-CONFIGURATION.md`
- [x] Review `git diff --check` and the complete working-tree diff
- [x] Build the release archive with `git archive`, not by zipping the working directory

## Release metadata

- [x] Update `CHANGELOG.md`
- [x] Commit the release candidate
- [x] Tag the first public preview as `v0.1.0`
- [x] Confirm that GitHub detects the chosen license and CI passes
- [x] Enable GitHub private vulnerability reporting and add the final public security contact link
- [x] Publish the project website with GitHub Pages

## NoBS11 v0.2.0

- [x] Rename the public product and rewrite the site around performance and honest measurements
- [x] Add pinned, SHA-256-verified website installer files
- [x] Add Standard, Lean, and Maximum profile boundaries
- [x] Keep Maximum behind explicit warning, UAC, rollback data, and post-restart validation guidance
- [ ] Test the release launcher from the published GitHub asset on a clean Windows user
- [ ] Publish v0.2.0 assets and verify every public download hash
- [ ] Verify the renamed GitHub Pages URL and direct site download
