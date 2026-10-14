# Architecture

## Design principles

DevStack separates immutable application/runtime files from mutable user data.
This enables upgrades and rollback without replacing projects or databases.

```text
DevStack/
  DevStack.ControlPanel.exe
  runtime/
    apache/
    php/
    mariadb/
    templates/
    config/generated/
  data/mariadb/
  logs/
  www/
```

The control panel discovers its root from `AppContext.BaseDirectory`, renders
configuration files using absolute Windows paths, validates required binaries
and ports, and then supervises the server processes.

## Process lifecycle

1. Validate the runtime layout.
2. Confirm ports 8080 and 3307 are available.
3. Render configuration into `runtime/config/generated`.
4. Start MariaDB and wait for its TCP listener.
5. Start Apache and wait for its TCP listener.
6. Stream process output to the control panel and `logs/`.
7. Stop Apache first, then request a graceful MariaDB shutdown.

The initial scaffold implements configuration generation and process
supervision. Health checks, graceful MariaDB administration and recovery from
unexpected termination remain roadmap work.

## Runtime trust

Runtime binaries must come from upstream release sources. Each exact archive
is pinned in `runtime/manifest/components.json` with a SHA-256 checksum. The
installer rejects non-HTTPS URLs, malformed checksums, path traversal in
required-file declarations and unexpected archive layouts. It verifies the
download before extraction and installs through a staging directory.

Apache for Windows requires special care because the Apache Software
Foundation does not publish official Windows binaries. The dedicated Windows
workflow verifies the pinned Apache 2.4.69 source archive, builds against an
exact vcpkg revision, copies dynamic runtime dependencies and emits a ZIP with
its SHA-256 checksum and a machine-readable build receipt. The runner image and
compiler family are fixed, while the receipt records the remaining build
inputs. The result is not trusted until its checksum is verified during local
installation.

## Runtime installation

`scripts/install-runtime.ps1` installs enabled Windows ZIP components. A
successful installation produces `.devstack-receipt.json` inside the component
directory containing the exact version, URL, digest and installation time.
Replacement is opt-in, and the previous runtime is moved to a recoverable
backup rather than deleted.

The verified Apache build is promoted from its successful Actions artifact to a
permanent prerelease asset. The runtime manifest pins that asset and its digest.
`scripts/install-apache-artifact.ps1` remains available for independent or
offline verification.

## Windows distribution

The online distribution is compiled by `.github/workflows/distribution.yml` on
Windows Server 2022. It publishes the WPF application self-contained for
`win-x64`, packages it with Inno Setup, installs per-user under Local AppData,
and downloads all server components during setup. The same workflow performs a
silent installation into a clean directory and verifies the executable, server
and initialized database layout before publishing the setup program.

MariaDB receives a cryptographically random root password during initialization.
The password is stored using Windows DPAPI for the current user, rather than as
plain text. The control panel can change it while MariaDB is running by using a
temporary client option file restricted to the current Windows user. No Windows
services are registered; Apache and MariaDB remain child processes of the
control panel.

## Secrets

Database credentials will be generated on first run. The intended design is to
protect stored secrets with Windows DPAPI and create temporary client option
files with user-only ACLs when invoking administrative utilities. Passwords
must never be passed on a process command line or written to logs.

## Updates

Runtime updates will be installed side-by-side. A small local manifest will
select the active runtime version, and switching versions will be atomic.
Mutable directories (`www`, `data`, `logs`, and user configuration overrides)
are never part of a runtime replacement.
