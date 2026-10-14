# DevStack for Windows

DevStack is a native, portable Windows development environment for PHP
applications. The planned runtime combines Apache HTTP Server, PHP 8.5 and
MariaDB behind a small desktop control panel.

> Project status: unsigned release candidate. The automated distribution is intended for
> Windows 10/11 x64 testing and is not ready for production use.

## Initial goals

- Run without administrator rights in portable mode.
- Start and stop Apache and MariaDB from one control panel.
- Generate relocatable configuration from templates.
- Bind HTTP and database listeners to `127.0.0.1` by default.
- Keep applications, database files and local settings outside replaceable
  runtime directories.
- Verify every downloaded runtime archive by SHA-256 before extraction.
- Support safe, side-by-side runtime upgrades and rollback.

## Planned default stack

| Component | Initial choice |
| --- | --- |
| Control panel | .NET 8 WPF, self-contained x64 |
| HTTP server | Apache HTTP Server 2.4 |
| PHP | PHP 8.5 x64 Thread Safe |
| Database | MariaDB LTS x64 |
| Web root | `www/` |
| HTTP endpoint | `http://127.0.0.1:8080` |
| Database endpoint | `127.0.0.1:3307` |

## Repository layout

```text
src/                  Control-panel and core source code
runtime/manifest/     Pinned runtime component metadata
runtime/templates/    Apache, PHP and MariaDB configuration templates
scripts/              Build and package-validation scripts
docs/                 Architecture and security decisions
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

## Install the verified runtime

### Nontechnical Windows installation

Download the [DevStack 1.0 RC1 installer](https://github.com/jtylek/devstack-windows/releases/download/v1.0.0-rc.1/DevStack-Setup-1.0.0-rc.1-win-x64.exe) and run it. The per-user installer does not require administrator
rights. It installs a self-contained control panel, downloads checksum-pinned
Apache, PHP and MariaDB archives, initializes a local MariaDB instance, and
creates shortcuts automatically.

The release-candidate installer is not code-signed, so Windows SmartScreen may display an
unknown-publisher warning. Published releases include a separate SHA-256 file.
The setup window displays the runtime download, verification, database
initialization and finalization phases while installation is running.

### phpMyAdmin and databases

After starting DevStack, open `http://127.0.0.1:8080/phpmyadmin`. Log in with
username `root`. To display the generated root password for the current Windows
user, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\show-database-password.ps1
```

When MariaDB is running, the DevStack control panel also provides **Set root
password**. The new password must contain at least 8 characters.

The control panel also provides **PHP extensions** and **OPcache settings**.
Changes are stored under `data/config` and only require restarting Apache;
MariaDB is not restarted.

In phpMyAdmin, open the **Databases** tab, enter a database name, and choose
**Create**. phpMyAdmin is installed as the English-only stable 5.2.3 package;
the installer verifies its SHA-256 checksum before extraction.

### Developer installation

The manifest pins Apache 2.4.69, PHP 8.5.11 Thread Safe x64 and MariaDB 11.8.9
LTS for Windows. To download, verify and extract all packages:

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

## Security

The development services are local-only by default. See
[`SECURITY.md`](SECURITY.md) and [`docs/architecture.md`](docs/architecture.md)
before changing listener addresses or distributing a build.

## License

The DevStack control-panel source is MIT licensed. Bundled third-party
components retain their own licenses and notices; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
