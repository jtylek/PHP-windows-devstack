# Security policy

DevStack is currently an early development scaffold and should not be exposed
to the public internet.

## Secure defaults

- Apache listens on all interfaces and serves the `www/` web root to LAN clients; phpMyAdmin remains local-only.
- MariaDB binds to `127.0.0.1` only.
- MariaDB uses nonstandard development port `3307` by default; Apache defaults to `8080`.
- Allow Apache inbound traffic only on Windows' Private network profile, and never expose the development stack to the public internet.
- Runtime downloads must have a pinned SHA-256 checksum.
- Database data and credentials are never stored in the source tree.
- The control panel does not modify the machine-wide `PATH`.
- Administrator rights are not required for ordinary portable operation.

## Reporting vulnerabilities

Please report a vulnerability privately through GitHub's security advisory
feature once it is enabled for the repository. Do not disclose credentials,
private application data or database dumps in a public issue.
