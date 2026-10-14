# Third-party notices

No third-party binaries are committed to this repository. The runtime manifest
downloads the repository-built Apache 2.4.69 release asset, PHP 8.5.11 and
MariaDB 11.8.9 after verifying pinned SHA-256 checksums.

Future release packages are expected to include Apache HTTP Server, PHP,
MariaDB and their transitive runtime libraries. Each release must ship the
applicable license texts, notices, source links and an SBOM. The release
pipeline must not treat this file as a substitute for those component-specific
obligations.
