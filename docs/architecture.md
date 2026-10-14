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
Foundation does not publish official Windows binaries. Apache 2.4.69 source is
pinned but disabled; release builds should either compile it reproducibly from
upstream source or clearly document and verify the selected binary distributor.

## Runtime installation

`scripts/install-runtime.ps1` installs enabled Windows ZIP components. A
successful installation produces `.devstack-receipt.json` inside the component
directory containing the exact version, URL, digest and installation time.
Replacement is opt-in, and the previous runtime is moved to a recoverable
backup rather than deleted.

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
