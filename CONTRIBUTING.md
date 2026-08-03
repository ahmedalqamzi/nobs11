# Contributing

Keep changes inspectable, narrowly scoped, and reversible where Windows provides a reversible operation.

Before opening a change:

1. Run `./scripts/Test-Repository.ps1` in PowerShell 7.
2. Run `make audit` and `make verify` on a supported Windows test system when runtime behavior changes.
3. Add a rollback path for new registry, task, service, or file mutations.
4. Keep machine-specific inventories, exported reports, credentials, and local paths out of tracked files.
5. Document the source URL, revision, and license for adapted policy or vendored material.

Do not weaken Defender, Windows Update, UAC secure desktop, VBS/exploit mitigations, or driver/security components without an explicit change to the project's stated safety boundary.
