# Development

## Goals

- Run without administrator rights in portable mode.
- Start and stop Apache and MariaDB from one control panel.
- Generate relocatable configuration from templates.
- Serve the `www/` web root to clients on the LAN; keep MariaDB bound to `127.0.0.1`.
- Keep applications, database files and local settings outside replaceable
  runtime directories.
- Verify every downloaded runtime archive by SHA-256 before extraction.
- Support safe, side-by-side runtime upgrades and rollback.

## Default stack

| Component | Choice |
| --- | --- |
| Control panel | .NET 8 WPF, self-contained x64 |
| HTTP server | Apache HTTP Server 2.4 |
| PHP | PHP 8.5 x64 Thread Safe |
| Database | MariaDB LTS x64 |
| Mail capture | Mailpit 1.33.1 native Windows x64 |
| Web root | `www/` |
| HTTP access | Local: `http://127.0.0.1:8080`; LAN: `http://<PC-LAN-IP>:8080` |
| Database endpoint | `127.0.0.1:3307` (local only) |

PHP Windows DevStack bundles PHP 8.5.12 Thread Safe x64, which fixes the critical
security vulnerabilities CVE-2026-109618 and CVE-2026-109619. The official Windows
archive URL and its SHA-256 checksum are pinned in `runtime/manifest/components.json`;
the installer verifies the checksum before extracting PHP.

## Repository layout

```text
src/                  Control-panel and core source code
runtime/manifest/     Pinned runtime component metadata
runtime/templates/    Apache, PHP and MariaDB configuration templates
scripts/              Build and package-validation scripts
docs/                 Documentation, architecture and security decisions
www/                  Default web root
```

Downloaded runtime files, database data and logs are intentionally ignored by
Git.

## Build

Requirements:

- Windows 10 or 11 x64
- .NET 8 SDK
- PowerShell 7 recommended

```powershell
./scripts/build.ps1
```

To validate the expected repository and package layout:

```powershell
./scripts/validate-layout.ps1
```

## Developer installation

The manifest pins Apache 2.4.69, PHP 8.5.12 Thread Safe x64, MariaDB 11.8.9
LTS and Mailpit for Windows. To download, verify and extract all packages:

```powershell
./scripts/install-runtime.ps1
```

The installer downloads only over HTTPS, verifies the exact SHA-256 before
extraction, validates expected executable files and writes an installation
receipt. Existing runtimes are not replaced unless `-Force` is supplied; when
forced, the previous directory is moved under `runtime/.backup/`.

Apache 2.4.69 source is pinned for provenance. Because Apache does not publish
an official Windows binary, `.github/workflows/build-apache.yml` compiles it on
a Windows Server 2022 runner using a pinned vcpkg revision. The verified build
is published as a permanent project release asset for the online installer.

To build the same artifact locally, use Visual Studio 2022 with C++ tools,
CMake, Ninja, Git and PowerShell 7:

```powershell
./scripts/build-apache.ps1
```

For independent verification, an extracted Apache build artifact can still be
installed into `runtime/apache` with:

```powershell
./scripts/install-apache-artifact.ps1 `
  -ArchivePath ./apache-httpd-2.4.69-win64-vs17.zip `
  -ChecksumPath ./apache-httpd-2.4.69-win64-vs17.zip.sha256
```

The Apache installer verifies the artifact checksum and expected runtime files.
As with the other installer, replacement requires `-Force` and preserves the
previous directory under `runtime/.backup/`.

## Network security

Apache serves the web root to LAN clients by default; MariaDB and phpMyAdmin
remain local-only. Use DevStack only on a trusted private network, allow inbound
Apache traffic only on the Windows Private profile, and do not expose the stack
to the public internet. See [`SECURITY.md`](../SECURITY.md) and
[`architecture.md`](architecture.md) before changing listener
addresses or distributing a build.
