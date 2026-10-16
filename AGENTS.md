# PHP Windows DevStack: Agent Notes

This file is project memory for future contributors and coding agents. Keep it
up to date when installer behavior, runtime versions, release procedures, or
known workarounds change.

## Project identity and scope

- Product name: **PHP Windows DevStack**.
- Repository: `https://github.com/jtylek/PHP-windows-devstack`.
- Default installation directory: `C:\PHPDevStack`.
- This is a native, portable Windows development stack for PHP applications:
  Apache HTTP Server, PHP 8.5, MariaDB, phpMyAdmin, and a .NET 8 WPF control
  panel.
- Do not reintroduce XAMPP branding or references. DevStack is an independent
  package.
- The runtime is intended for local development and binds services to
  `127.0.0.1` by default. It is not a production distribution.

## Repository structure

- `src/DevStack.Core`: service control, generated configuration, passwords,
  ports, PHP settings, and SMTP capture.
- `src/DevStack.ControlPanel`: WPF UI.
- `runtime/manifest/components.json`: pinned runtime download URLs and hashes.
- `runtime/templates`: generated Apache, PHP, and MariaDB configuration.
- `scripts/setup-runtime.ps1`: online installer orchestration and MariaDB
  initialization.
- `scripts/install-runtime.ps1`: download, verify, extract, and safely replace
  individual runtime components.
- `installer/DevStack.iss`: Inno Setup wrapper and installer wizard behavior.
- `www/`: default web root, including the project-directory index page and CSS.
- `data/`: generated database, secrets, logs, and user settings; it is not
  source-controlled.

## Important defaults

- MariaDB uses the SSD development profile documented in
  `docs/mariadb-development-profile.md`: RAM-sized buffer pool, 256 MiB redo log,
  flush-at-commit 2, and a one-second slow-query log under `logs/`. This trades
  crash durability for development throughput; never describe the loss window
  as a guaranteed maximum of one second. Do not delete redo/data files to apply
  it. Preserve custom settings during installer upgrades. Old low-memory
  estimates no longer apply to this profile.
- `MariaDbSettingsManager` renders `INNODB_BUFFER_POOL_SIZE` using installed
  physical RAM / 16 (the explicit requested examples override the spec's /8
  wording), rounded down to 64 MiB, clamped to 128–2048 MiB; detection fallback
  256 MiB. `data/config/mariadb-settings.json` holds optional `BufferPoolSizeMb`.
  The UI saves overrides for next restart and opens both database logs. Do not
  pass the new template to an old panel that cannot resolve its placeholder.

- Apache: `127.0.0.1:8080`.
- MariaDB: `127.0.0.1:3307`.
- SMTP capture: `127.0.0.1:25`.
- phpMyAdmin: `http://127.0.0.1:8080/phpmyadmin` unless the Apache port is
  changed in the control panel.
- MariaDB root password is generated during setup and stored encrypted with
  Windows DPAPI at `data/secrets/mariadb-root-password.dpapi`.
- User-selected ports are stored in `data/config/ports.json`. Port changes
  require both services to be stopped; the control panel checks availability and
  updates phpMyAdmin's MariaDB port.

## PHP and Epesi compatibility

- The control panel's **Open PowerShell** button opens the bundled PHP directory.
  `PhpTerminal` sets child-process-only PATH/PHPRC/PHP_INI_SCAN_DIR and defines a
  session-local `php` function with explicit `-c` for the generated ini. Never
  set machine/user-wide PHPRC: other PHP installations must remain unaffected.
  Generating terminal settings must not regenerate Apache config or restart services.

- PHP 8.5 built-in extensions include `ctype`, `pdo`, `tokenizer`, and `xml`.
  They do not appear as DLLs and cannot be meaningfully disabled. The extension
  dialog must keep them checked and explain this to users.
- PHP settings and extension changes affect Apache's PHP module. Restarting
  Apache is sufficient; MariaDB does not need to restart.
- The default PHP settings are tuned for Epesi development, including OPcache
  memory `256 MB`, interned strings `32 MB`, maximum accelerated files `20000`,
  realpath cache TTL `600`, `memory_limit=256M`, `zend.assertions=-1`, and
  `display_errors=Off`.
- Do not assume the PHP `memory_limit` or OPcache capacity is permanently
  allocated RAM. See the README memory section for practical estimates.
- Epesi's current dependency tree can emit PHP 8.5 deprecation notices about
  implicitly nullable parameters under `vendor/ekmungai/eloquent-ifrs`. Record
  compatibility findings in `www/AI-shared/PHP-8.5-compatibility.md`; do not
  silently patch `vendor/` unless explicitly requested.
- For an Epesi checkout, run Composer from `C:\PHPDevStack\www` so that
  `vendor/` is created in the project root. Check `.env`, writable
  `storage/`, `bootstrap/cache/`, `modules/`, and `public/`, and use MariaDB
  port `3307` unless the user changed it.

## Known installer and runtime gotchas

### PowerShell and path handling

- The Inno Setup installer invokes **Windows PowerShell 5.1**, not necessarily
  PowerShell 7. Keep installer scripts compatible with Windows PowerShell 5.1.
- Scripts use `$PSScriptRoot` to find the installation root. Run scripts by
  their actual path; invoking or pasting only a fragment can leave
  `$PSScriptRoot` empty and cause errors such as `Split-Path ... Path ... empty`.
  `show-database-password.ps1` can also be given `-InstallRoot C:\PHPDevStack`.
- Always use explicit literal paths when diagnosing or modifying an install.
  Avoid broad recursive deletes and never remove the user's whole install to
  solve a configuration issue unless the user explicitly requests it.

### Setup failures

- The installer downloads runtime components online. A successful Inno Setup
  wizard does not mean runtime setup succeeded until `.devstack-ready` exists.
- On failure inspect:
  - the Inno Setup log shown or written by setup;
  - `C:\PHPDevStack\logs\setup-runtime.log`;
  - `C:\PHPDevStack\setup-progress.txt`.
- MariaDB is started temporarily during setup to initialize its data directory
  and phpMyAdmin configuration storage. The bootstrap code currently uses
  port `3307` deliberately. If changing the install-time default port, update
  every bootstrap client/initializer reference in `scripts/setup-runtime.ps1`,
  the generated phpMyAdmin config, and the verification flow—not just the
  runtime template.
- A previous setup can leave a partially initialized `data/` directory. Check
  logs and process state before retrying, and preserve logs for diagnosis.
- The installer progress display is driven by lines emitted to the progress
  file/callback. If setup stages are renamed, update the progress parsing in
  `installer/DevStack.iss` as well as the PowerShell messages.

### Apache/PHP startup

- Apache loads PHP as an Apache module. `StackController` must put the PHP and
  Apache DLL directories on the process `PATH` before launching `httpd.exe`.
  This avoids errors such as a missing sodium/OpenSSL DLL entry point.
- When diagnosing a native DLL error, verify that all PHP extension DLLs match
  the bundled PHP build and that no older PHP directory precedes DevStack on
  `PATH`.
- Apache and MariaDB can be started/stopped independently. Changing PHP
  extensions or OPcache settings should not restart MariaDB.

### SMTP capture

- SMTP capture is local-only, listens on port 25, stores messages under
  `data/smtp`, and does not deliver mail.
- Port 25 may already be occupied by another mail tool. Surface the bind error
  clearly instead of silently retrying.
- The capture window is modeless. Closing the main control panel must close the
  capture window and stop the listener.

### Runtime trimming

- `scripts/trim-runtime.ps1` removes development/debug payloads, and the online
  setup already performs the supported trimming step. Do not propose or apply
  additional package trimming without user approval; the project decision is to
  keep the functional runtime intact.

## Validation before committing

Run these checks from the repository root:

```powershell
./scripts/validate-layout.ps1
./scripts/verify-runtime-manifest.ps1
./scripts/build.ps1
git diff --check
```

The local development machine may not have the .NET 8 SDK or Inno Setup. In
that case, do not claim a local build passed; the GitHub Actions results are the
authoritative build verification. The CI build uses Windows and .NET 8.

## Publishing a new installer release

1. Make the code and documentation changes. Keep the install path and product
   name consistent across `README.md`, `installer/DevStack.iss`, UI text, and
   shortcuts.
2. If changing the release version, update all of these consistently:
   - `MyAppVersion`, `VersionInfo*`, and output filename in
     `installer/DevStack.iss`;
   - `RELEASE_TAG`, setup filename, artifact name, and title/notes in
     `.github/workflows/distribution.yml`;
   - README download links and any displayed version text.
3. If runtime versions change, update `runtime/manifest/components.json` and
   verify every URL and SHA-256 hash. If Apache is rebuilt, update the Apache
   artifact ID and hash in the distribution workflow.
4. Validate, inspect the diff, commit, and push to `main`:

```powershell
git diff --check
git status --short
git add <intended files>
git commit -m "Describe the release change"
git push origin main
```

5. A push to `main` triggers both `build` and `distribution` when distribution
   paths change. Monitor them with GitHub CLI:

```powershell
gh run list --repo jtylek/PHP-windows-devstack --limit 5
gh run watch <distribution-run-id> --repo jtylek/PHP-windows-devstack --exit-status
```

6. The distribution workflow compiles the self-contained control panel, runs
   Inno Setup, silently installs to a temporary Windows directory, verifies
   required runtime files and MariaDB data, writes a SHA-256 file, and uploads
   the installer to the GitHub release. It uses `--clobber`, so reusing the
   same tag replaces assets; use a new tag for a distinct public release.
7. Verify the final release asset and checksum before reporting it:

```powershell
gh release view <tag> --repo jtylek/PHP-windows-devstack
gh release download <tag> --repo jtylek/PHP-windows-devstack `
  --pattern '*Setup*.exe.sha256' --dir $env:TEMP
```

The current release workflow is an unsigned release candidate. Never claim an
installer is ready until the distribution workflow is successful and the
installer plus checksum are visible on the GitHub release page.

## Git and change-management rules

- Preserve unrelated user changes in a dirty worktree.
- Do not use `git reset --hard` or `git checkout --` unless explicitly asked.
- Use `apply_patch` for source edits.
- Do not commit secrets, generated `data/`, runtime downloads, or local
  installer logs.
- Before release work, confirm `git remote -v` still points to
  `jtylek/PHP-windows-devstack`.
