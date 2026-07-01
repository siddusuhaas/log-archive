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

Each run creates `archives/logs_archive_YYYYMMDD_HHMMSS.tar.gz` (relative to
the current working directory, or `$LOG_ARCHIVE_DIR` if set) and appends a
line to `archives/archive.log`:

```
2024-08-16 10:06:48 | /var/log | logs_archive_20240816_100648.tar.gz | 42 files | 5242880 bytes
```

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
