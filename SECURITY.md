# Security policy

This project changes Windows registry values, scheduled tasks, services, optional components, application packages, and user configuration. Review the exact script and JSON policy before execution; never run a high-impact target copied from an untrusted fork.

Use `-WhatIf` where supported and retain local rollback data until restart and hardware validation are complete. A rollback manifest is not a substitute for a tested backup, System Restore, or an accessible Device Encryption/BitLocker recovery key.

Verification reports, logs, baselines, and backups can contain local paths, package inventories, task definitions, registry data, account names, or a computer name. They are ignored by Git. Verification is redacted by default; do not attach private diagnostic files to a public issue without reviewing them.

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/ahmedalqamzi/nobs11/security/advisories/new) rather than posting secrets or sensitive logs in a public issue.
