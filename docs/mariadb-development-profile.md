# MariaDB SSD development profile

Addendum to the PHPDevStack HTTPS/ports/SMTP specification, requested 2026-10-16.
Target: bundled MariaDB 11.8 on a 16 GB Windows development machine with SATA
SSDs. These are development defaults, not universal or production tuning.

| Setting | Value |
| --- | --- |
| innodb_buffer_pool_size | Automatic: 512M on 8 GB, 1G on 16 GB, up to 2G |
| innodb_flush_log_at_trx_commit | 2 |
| innodb_log_file_size | 256M |
| innodb_io_capacity / innodb_io_capacity_max | 1000 / 4000 |
| table_definition_cache | 1000 |
| tmp_table_size / max_heap_table_size | 64M / 64M |
| key_buffer_size | 16M |
| slow_query_log / log_output / long_query_time | 1 / FILE / 1 |
| slow_query_log_file | {{LOG_ROOT}}/mariadb-slow.log |

`{{INNODB_BUFFER_POOL_SIZE}}` is resolved at configuration generation from
Windows installed physical RAM. The explicit target sizes in the specification
correspond to **1/16**, not its stated 1/8. Automatic sizing rounds down to 64 MiB,
with a 128 MiB minimum and 2048 MiB maximum: 2 GB → 128M, 4 GB → 256M,
8 GB → 512M, 16 GB → 1G, 32 GB or more → 2G. If RAM detection fails, use 256M.

Use **MariaDB → Memory settings** for an override (128–65536 MB, multiples of
64), or clear the field to restore automatic sizing. This is saved as
`BufferPoolSizeMb` in `data/config/mariadb-settings.json`; null means automatic.
An explicit override may exceed the automatic cap. Restart MariaDB to apply it;
the UI never force-restarts the database or applies live SET GLOBAL changes.
The **Error log** and **Slow log** buttons open the respective files in Notepad.

The larger buffer pool should reduce repeated InnoDB reads once the working
set is warm; this is not a guarantee that every query avoids disk access.
Startup read counters alone do not establish a steady-state cache miss rate.
Benchmark imports and ordinary application requests before and after tuning.

## Tradeoffs

- Flush-at-commit 2 writes redo on commit but normally flushes it once a second.
  An OS crash or power failure can lose recent committed transactions; the
  interval is not a hard loss bound. Set it to 1 for stronger durability.
- Pool growth from 128 MiB to 1 GiB adds 896 MiB of capacity. Reducing the
  MyISAM key buffer saves capacity, but total process RAM is workload-dependent.
  The 256 MiB redo log is primarily disk capacity, not another 256 MiB RAM pool.
- Temporary-table limits apply to individual allocations, not all connections
  together. More RAM does not prevent every kind of temporary-table disk spill.
- I/O capacities are starting points for SSDs, not measurements of this disk.
- Slow logs can include personal data and SQL literals and grow without a bound.
  Do not put them under `www` or commit them. Archive/rotate them while MariaDB
  is cleanly stopped; automatic log rotation is not implemented by this change.

## Apply to an existing installation

1. Back up the databases with a database-aware backup tool, and save a copy of
   `runtime/templates/mariadb.ini.template` before editing it.
2. Stop application writes and stop MariaDB cleanly. Do not force-kill it.
3. With the updated control panel, add or update the settings above inside the template's `[mariadbd]` section,
   before `[client]`. Preserve existing ports, paths, and other custom settings.
   Do not append duplicate settings or edit only the generated ini.
   An older panel cannot resolve the new buffer-pool placeholder: for a manual
   template-only update on a 16 GB machine use the literal `1G` instead.
4. Start MariaDB from the control panel; it regenerates the configuration.
   MariaDB manages its redo-log resizing. Never delete `ib_logfile0`, `ibdata1`,
   database directories, or any other file in `data/mariadb` to apply this profile.
5. Verify on PHPDevStack's database connection (not another running XAMPP instance):

```sql
SELECT @@port, @@datadir, @@version;
SHOW GLOBAL VARIABLES WHERE Variable_name IN (
  'innodb_buffer_pool_size', 'innodb_flush_log_at_trx_commit',
  'innodb_log_file_size', 'innodb_io_capacity', 'innodb_io_capacity_max',
  'table_definition_cache', 'tmp_table_size', 'max_heap_table_size',
  'key_buffer_size', 'slow_query_log', 'slow_query_log_file',
  'log_output', 'long_query_time');
SELECT SLEEP(1.2);
```

On a 16 GB machine without an override, expect buffer pool 1073741824,
redo log 268435456, temporary limits 67108864,
and key buffer 16777216 bytes. Check `logs/mariadb-slow.log` for the test query.
MariaDB may expose the slow-log settings using their newer `log_slow_*` aliases.
If memory pressure grows, reduce the buffer pool and restart cleanly. To undo
the profile, restore the saved template and restart; no database restore or
runtime download is required for these configuration-only changes.

Installer integration must preserve explicit user overrides and explain the
durability change; these source defaults alone do not implement upgrade migration.

## References

- [InnoDB variables](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-system-variables)
- [Server variables](https://mariadb.com/docs/server/server-management/variables-and-modes/server-system-variables)
- [Redo log](https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-redo-log)
