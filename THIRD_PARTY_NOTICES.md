# Third-party notices

No third-party binaries are committed to this repository. The runtime manifest
downloads the repository-built Apache 2.4.69 release asset, PHP 8.5.12,
MariaDB 11.8.9 and Mailpit 1.33.1 after verifying pinned SHA-256 checksums.

Future release packages are expected to include Apache HTTP Server, PHP,
MariaDB and their transitive runtime libraries. Each release must ship the
applicable license texts, notices, source links and an SBOM. The release
pipeline must not treat this file as a substitute for those component-specific
obligations.

## Mailpit

The online installer downloads Mailpit 1.33.1 for Windows x64 from
https://github.com/axllent/mailpit/releases/tag/v1.33.1 and verifies its pinned
SHA-256 checksum. Mailpit is copyright (c) 2022-present Ralph Slooten
and distributed under the MIT license. Its LICENSE and README.md are retained
under `runtime/mailpit`. Source: https://github.com/axllent/mailpit.

## Mozilla CA certificate bundle

The setup downloads the current Mozilla CA root bundle in PEM format from the curl project at https://curl.se/ca/cacert.pem and verifies its SHA-256 against the companion checksum. The bundle is derived from Mozilla's CA certificate store and is distributed under the Mozilla Public License 2.0 (MPL-2.0). Source and license information: https://curl.se/docs/caextract.html.
