# log-archive

Command-line tool that compresses a log directory into a timestamped
`tar.gz` archive and records the operation in an audit log.

Built for the [Log Archive Tool](https://roadmap.sh/projects/log-archive-tool) roadmap.sh project.

## Usage

```bash
log-archive /var/log
log-archive /home/user/applogs
log-archive .
```

Each run creates `archives/logs_archive_YYYYMMDD_HHMMSS.<ext>` (relative to
the current working directory, or `$LOG_ARCHIVE_DIR` if set) and appends a
line to `archives/archive.log`:

```
2024-08-16 10:06:48 | /var/log | logs_archive_20240816_100648.tar.gz | 42 files | 5242880 bytes | format: tar.gz
```

## Options

```
log-archive [OPTIONS] <log-directory>

  -k, --keep N            Keep only the N most recent archives, deleting older ones
  -f, --format FORMAT     Archive format: tar, tar.gz, tar.bz2, tar.xz (default: tar.gz)
  -e, --exclude PATTERN   Exclude paths matching a glob PATTERN. Repeatable, or
                           pipe-separate multiple patterns in one flag: "*.tmp|*.swp"
      --schedule CRON     Register a crontab entry (5-field expression) that runs
                           this exact command on a schedule, then exit
  -h, --help              Show this help and exit
```

### Cleanup old archives (`-k`, `--keep`)

```bash
log-archive -k 5 /var/log          # archive, then keep only the 5 most recent archives
log-archive --keep=10 /var/log
```

Deletes the oldest `logs_archive_*` files beyond the given count (sorted by
the timestamp embedded in the filename) and logs one `CLEANUP` line per
deleted archive:

```
2024-08-16 10:06:48 | CLEANUP | deleted logs_archive_20240801_120000.tar.gz | freed 1048576 bytes
```

### Compression format (`-f`, `--format`)

```bash
log-archive -f tar.gz /var/log     # default: gzip
log-archive -f tar.bz2 /var/log    # bzip2 — smaller, slower
log-archive -f tar.xz /var/log     # xz — smallest, slowest
log-archive -f tar /var/log        # uncompressed — fastest
```

The chosen format becomes the archive's file extension and is recorded in
`archive.log`.

### Exclude patterns (`-e`, `--exclude`)

```bash
log-archive -e "*.tmp" /var/log
log-archive -e "*.tmp|*.swp|*.lock" /var/log       # multiple patterns, pipe-separated
log-archive -e "debug/*" -e "test/*" /var/log      # or multiple -e flags
```

Patterns are shell globs matched against each file's path relative to the
archived directory (e.g. `sub/debug.log`, `debug/*`). Matching files are
skipped and counted in `archive.log`:

```
2024-08-16 10:06:48 | /var/log | logs_archive_20240816_100648.tar.gz | 42 files archived | 5 excluded | 5242880 bytes | format: tar.gz
```

### Cron scheduling (`--schedule`)

```bash
log-archive --schedule "0 2 * * *" /var/log        # daily at 2 AM
log-archive --schedule "0 */6 * * *" -k 10 /var/log # every 6 hours, auto-cleanup
```

Registers a crontab entry that invokes the installed `log-archive` binary
(via `command -v log-archive`, so it must be installed first — see
`make install`) with the same flags, then exits without archiving anything
in that invocation. Refuses to add an identical entry twice. To remove a
scheduled job later, run `crontab -e` and delete the corresponding lines.

## Install

```bash
make install      # copies log-archive to /usr/local/bin
make uninstall     # removes it
```

Override the install location with `make install PREFIX=/some/prefix`.

## Behavior

- No argument: prints `Usage: log-archive <log-directory>` and exits 1.
- Missing/unreadable directory: prints an error and exits 2.
- Empty directory: still creates a (near-empty) valid `tar.gz`.
- Directory structure is preserved with relative paths (`./sub/file.log`),
  never absolute paths, so extraction can't escape the target directory.
- Symlinks are archived as links (not followed) and reported as warnings.
- Available disk space is checked before archiving (requires roughly half
  the source directory's size to be free, based on typical log compression
  ratios).
- Exit code 0 on success, non-zero on any failure.

## Tests

```bash
make test
# or
bash tests/test.sh
```
