# Security policy

DevStack is currently an early development scaffold and should not be exposed
to the public internet.

## Secure defaults

- Apache and MariaDB bind to `127.0.0.1` only.
- MariaDB uses a nonstandard development port by default.
- Runtime downloads must have a pinned SHA-256 checksum.
- Database data and credentials are never stored in the source tree.
- The control panel does not modify the machine-wide `PATH`.
- Administrator rights are not required for ordinary portable operation.

## Reporting vulnerabilities

Please report a vulnerability privately through GitHub's security advisory
feature once it is enabled for the repository. Do not disclose credentials,
private application data or database dumps in a public issue.
