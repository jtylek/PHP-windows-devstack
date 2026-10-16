# PHP Windows DevStack

PHP Windows DevStack is a native, portable Windows development environment for PHP
applications. The runtime combines Apache HTTP Server, PHP 8.5 and MariaDB
behind a small desktop control panel.

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

Download the [PHP Windows DevStack 1.0 RC5 installer](https://github.com/jtylek/PHP-windows-devstack/releases/download/v1.0.0-rc.5/PHP-Windows-DevStack-Setup-1.0.0-rc.5-win-x64.exe) and run it. The default installation directory is `C:\PHPDevStack`; installing there requires administrator
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

The control panel also provides **PHP extensions**, **OPcache settings**, and
**Port settings**. Apache defaults to port `8080` and MariaDB to `3307`; both
can be changed to common ports such as `80` and `3306`. DevStack checks that a
new port is available before saving it, and the services must be stopped before
changing ports.

### SMTP mail capture

The control panel includes **SMTP Mail Capture** for local application troubleshooting. Start it from the control panel and configure Epesi or another application to use `127.0.0.1`, port `25`, without encryption or authentication. Messages are captured locally in `data\smtp` and can be viewed, exported as `.eml`, or deleted from the capture window. The listener binds only to localhost and does not deliver mail.
Changes are stored under `data/config` and only require restarting Apache;
MariaDB is not restarted.

### Updating an existing installation (RC3 and later)

Run the new installer **as the same Windows user** who originally installed
PHPDevStack and select your existing folder, usually `C:\PHPDevStack`.
First stop all services and close the control panel and PHP terminals. Do not
uninstall the old version or delete `www` or `data`.

Setup labels the operation **Update existing installation**. Before replacing
files it checks runtime receipts, requires all processes from that folder to be
stopped, verifies access to your encrypted password, and makes a SHA-256-verified
full backup at `C:\PHPDevStack-backups\<timestamp-id>`. Allow disk space for a
second complete copy. An incomplete/unrecognized installation or a missing runtime
receipt stops the update before files are replaced. Symbolic links and junctions
are retained as links; their external targets are not followed into the backup
and are not changed by setup.

Existing `www`, databases, passwords, ports, PHP/MariaDB settings, phpMyAdmin
configuration, and Apache/PHP templates are preserved. Missing MariaDB tuning
defaults are added to its template; existing explicit values remain unchanged.
Runtime versions are compared with the installer's pinned supported manifest:
equal or newer installed versions display **Does not need updating - skipped**.
This is not a query of arbitrary latest upstream releases. Cross-series MariaDB
updates are blocked for a separate database migration. See
`logs\upgrade-report.txt` and `logs\setup-runtime.log` for the results.

The **Open phpMyAdmin** button signs in locally as `root` without placing the
password in a URL. It sends a random, one-time token through a local POST form;
the token expires after one minute and its credential record is removed on first
use. The internal sign-on endpoint only accepts `127.0.0.1` and `::1`.

If setup fails after replacing files, keep everything stopped. The verified
backup contains the matching old binaries, templates and data together: rename
the failed installation folder and copy the complete backup back to the original
path. Do not restore individual InnoDB files over a running database. Backups
include private data and are restricted to your Windows account and SYSTEM;
keep them until you have checked your sites and databases. Automatic rollback
and backup cleanup are not implemented.

### Memory usage

DevStack does not have a fixed memory footprint; usage depends on the active
application and database workload. The SSD development profile reserves a
RAM-sized InnoDB buffer pool (512 MiB on 8 GB, 1 GiB on 16 GB, capped at 2 GiB),
plus other MariaDB buffers and per-connection memory.
The old 180–350 MB idle-stack estimate does not apply to this profile.

The PHP `memory_limit` and OPcache values are limits or cache capacity, not
memory permanently allocated at startup. Database temporary-table limits are
not a total memory cap: concurrent queries can allocate multiple buffers.
Use **MariaDB → Memory settings** to override the automatic size on
memory-constrained systems. Check available RAM when running
another database stack alongside PHPDevStack.

### MariaDB development tuning

The persistent settings live in `runtime/templates/mariadb.ini.template`,
not the generated `runtime/config/generated/mariadb.ini`. See
[the MariaDB tuning specification](docs/mariadb-development-profile.md) for
the values, safe application steps, verification query, and durability caveats.
The slow query log is `logs/mariadb-slow.log` (queries taking over one second).
The MariaDB card has **Error log** and **Slow log** buttons to open these files.

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

## PHP PowerShell terminal

Click **Open PowerShell** in the control panel. It opens Windows PowerShell in
`C:\PHPDevStack\runtime\php` (or the equivalent under your chosen install folder).
The `php` command explicitly uses the bundled executable and
`runtime\config\generated\php.ini`, regenerated from your PHP settings before
the window opens. The terminal displays `php --ini` on startup for verification.
You can change to your project directory and continue using the same PHP:

```powershell
cd C:\PHPDevStack\www\my-project
php --ini
php -m
php artisan --version
```

The terminal's PATH and PHPRC apply only to this window and its child processes
(including Composer); other terminals and Windows environment settings are not
changed. PowerShell profiles are not loaded, preventing another profile from
selecting a different PHP. Close and reopen the terminal after changing PHP
settings. Additional CLI ini files, if needed, belong in `data\config\php-cli.d`.

## Network security

The development services are local-only by default. See
[`SECURITY.md`](SECURITY.md) and [`docs/architecture.md`](docs/architecture.md)
before changing listener addresses or distributing a build.

## License

The DevStack control-panel source is MIT licensed. Bundled third-party
components retain their own licenses and notices; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
