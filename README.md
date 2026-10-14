# DevStack for Windows

DevStack is a native, portable Windows development environment for PHP
applications. The planned runtime combines Apache HTTP Server, PHP 8.5 and
MariaDB behind a small desktop control panel.

> Project status: early scaffold. No third-party server binaries are committed
> yet, and this repository is not ready for production use.

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

## Runtime acquisition

`runtime/manifest/components.json` records pinned versions, source pages and
archive checksums. The archive URLs and checksums must be reviewed and filled
before the future bootstrap command is enabled. DevStack must never execute or
extract an unverified download.

## Security

The development services are local-only by default. See
[`SECURITY.md`](SECURITY.md) and [`docs/architecture.md`](docs/architecture.md)
before changing listener addresses or distributing a build.

## License

The DevStack control-panel source is MIT licensed. Bundled third-party
components retain their own licenses and notices; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
