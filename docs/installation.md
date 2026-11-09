# Installation and updating

## Nontechnical Windows installation

Download the latest installer from the
[Releases page](https://github.com/jtylek/PHP-windows-devstack/releases) and run it.
The current direct link is the
[PHP Windows DevStack 1.0 RC14 installer](https://github.com/jtylek/PHP-windows-devstack/releases/download/v1.0.0-rc.14/PHP-Windows-DevStack-Setup-1.0.0-rc.14-win-x64.exe).
The default installation directory is `C:\PHPDevStack`; installing there requires administrator
rights. It installs a self-contained control panel, downloads checksum-pinned
Apache, PHP, MariaDB and Mailpit archives, initializes a local MariaDB instance, and
creates shortcuts automatically.

The release-candidate installer is not code-signed, so Windows SmartScreen may display an
unknown-publisher warning. Published releases include a separate SHA-256 file.
The setup window displays the runtime download, verification, database
initialization and finalization phases while installation is running.

## Updating an existing installation (RC3 and later)

Run the new installer **as the same Windows user** who originally installed
PHPDevStack and select your existing folder, usually `C:\PHPDevStack`.
First stop all services and close the control panel and PHP terminals. Do not
uninstall the old version or delete `www` or `data`.

Setup labels the operation **Update existing installation**. Before replacing
files it checks runtime receipts, requires all processes from that folder to be
stopped, verifies access to your encrypted password, and offers a checked-by-default
safety-backup option. Setup estimates the data to copy and the final backup size,
then warns that copying and verification can take a long time. Progress reports
cover scanning, preparing the copy plan, creating the backup directory tree,
Robocopy batches, and verification. Cancel stops before setup replaces
installation files. If you skip the backup,
setup warns that it cannot restore the old installation if the update fails. The
installer maintains one backup at `C:\PHPDevStack-backups\current`: the first
backup without a previous completed snapshot makes a full copy, and later updates
copy only changed files into that folder.
After the new copy is verified, older timestamped backups made by previous releases
are removed. An incomplete/unrecognized installation or a missing runtime
receipt stops the update before files are replaced. Symbolic links and junctions
are retained as links; their external targets are not followed into the backup
and are not changed by setup.

Existing `www`, databases, passwords, ports, PHP/MariaDB settings, phpMyAdmin
configuration, and Apache/PHP templates are preserved. Missing MariaDB tuning
defaults are added to its template; existing explicit values remain unchanged.
An Apache template without the rule that blocks `.htaccess`/`.htpasswd`
downloads gets it appended.
Runtime versions are compared with the installer's pinned supported manifest:
equal or newer installed versions display **Does not need updating - skipped**.
This is not a query of arbitrary latest upstream releases. Cross-series MariaDB
updates are blocked for a separate database migration. See
`logs\upgrade-report.txt` and `logs\setup-runtime.log` for the results.

If setup fails after replacing files, keep everything stopped. The verified
backup contains the matching old binaries, templates and data together: rename
the failed installation folder and copy the complete backup back to the original
path. Do not restore individual InnoDB files over a running database. Backups
include private data and are restricted to your Windows account and SYSTEM;
keep them until you have checked your sites and databases. Automatic rollback
and backup cleanup are not implemented.
