# Using DevStack

## phpMyAdmin and databases

After starting DevStack, open `http://127.0.0.1:8080/phpmyadmin` (or use the
**Open phpMyAdmin** button). Log in with username `root`. To display the generated
root password for the current Windows user, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\show-database-password.ps1
```

When MariaDB is running, the control panel also provides **Set root
password**. The new password must contain at least 8 characters.

In phpMyAdmin, open the **Databases** tab, enter a database name, and choose
**Create**. phpMyAdmin is installed as the English-only stable 5.2.3 package;
the installer verifies its SHA-256 checksum before extraction.

## Settings and ports

The control panel provides **PHP extensions**, **OPcache settings**, and
**Port settings**. OPcache is enabled for both web requests and CLI PHP by default.
Apache defaults to port `8080` and MariaDB to `3307`; both
can be changed to common ports such as `80` and `3306`. DevStack checks that a
new port is available before saving it, and the services must be stopped before
changing ports. PHP setting changes are stored under `data/config` and only
require restarting Apache; MariaDB is not restarted.

## LAN access

Apache listens on all network interfaces and serves files from `www/` to LAN
clients on the configured HTTP port. Find the PC's private IPv4 address with
`ipconfig`, then open `http://<PC-LAN-IP>:8080` from another device (replace
`8080` if you changed Apache's port). Windows Defender Firewall must allow the
selected Apache port on the Private network profile. Do not expose it through a
Public profile or router port forwarding. MariaDB remains bound to
`127.0.0.1:3307` by default, and phpMyAdmin is restricted to local access.
An update migrates the stock Apache loopback-only directives to these LAN
defaults while preserving customized listen addresses and access rules.

## Notification area

Clicking the Control Panel's **X** button hides it in the Windows notification
area and leaves its services running. Choose **Open PHP Windows DevStack** to
show it again, or **Quit and stop services** from the tray menu to stop Apache,
MariaDB and Mailpit before exiting. If the panel is closed unexpectedly,
the next launch detects Apache and MariaDB processes by their executable paths
and reconnects its status and stop controls to this installation. A different
program using the same port is not treated as a DevStack service.

## Mail capture (Mailpit)

DevStack bundles [Mailpit](https://github.com/axllent/mailpit), a native Windows
executable with an embedded web inbox; Docker is not required. Use its **Start** and
**Stop** buttons, then **Open Mailpit** to open `http://127.0.0.1:8025/` in your
default browser. The inbox button is enabled once Mailpit is running. **Start all**,
**Stop all**, and **Quit and stop services** include Mailpit; hiding the panel to the
tray leaves it running.

Configure Epesi or another application to use SMTP host `127.0.0.1`, port `25`,
without encryption or authentication. Both SMTP and the web inbox bind only to
loopback. Mailpit captures mail without external delivery; DevStack clears inherited
`MP_*` environment settings for its child process to prevent accidental
relay/forwarding. Messages persist in `data\smtp\mailpit.db` across restarts, with
automatic message-count deletion disabled. Delete unwanted mail through the web
inbox. Existing capture `.eml` files remain in `data\smtp`; they are not
automatically imported into Mailpit.

Setup downloads and verifies the pinned Mailpit ZIP (about **11.19 MB**); its
installed files add about **29.35 MB**, plus captured mail. The online setup EXE only
gains the integration code and metadata. Port conflicts on SMTP `25` or inbox `8025`
are reported when starting Mailpit.

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

The installer downloads and SHA-256 verifies the current Mozilla CA bundle from the
curl project into `runtime\certificates\cacert.pem` on fresh installs and updates.
Generated PHP configuration points both cURL and OpenSSL at that bundle, so CLI
scripts and the Apache PHP module can validate outgoing HTTPS. If you have set
`curl.cainfo` or `openssl.cafile` yourself in `runtime\templates\php.ini.template`,
DevStack preserves those values.

## Memory usage

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

## MariaDB development tuning

The persistent settings live in `runtime/templates/mariadb.ini.template`,
not the generated `runtime/config/generated/mariadb.ini`. See
[the MariaDB tuning specification](mariadb-development-profile.md) for
the values, safe application steps, verification query, and durability caveats.
The slow query log is `logs/mariadb-slow.log` (queries taking over one second).
The MariaDB card has **Error log** and **Slow log** buttons to open these files.
