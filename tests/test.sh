#!/usr/bin/env bash
# Integration tests for log-archive. No framework required: bash tests/test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_ARCHIVE="${SCRIPT_DIR}/log-archive"

pass_count=0
fail_count=0

report() {
    local desc="$1" ok="$2"
    if [[ "$ok" -eq 0 ]]; then
        echo "ok   - $desc"
        pass_count=$((pass_count + 1))
    else
        echo "FAIL - $desc"
        fail_count=$((fail_count + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        report "$desc" 0
    else
        report "$desc (expected '$expected', got '$actual')" 1
    fi
}

new_workspace() {
    local ws
    ws="$(mktemp -d "${TMPDIR:-/tmp}/log-archive-test.XXXXXX")"
    # Canonicalize: log-archive resolves the source dir with `cd && pwd`
    # before logging it, so tests must compare against the same form
    # (macOS TMPDIR can contain a trailing slash / symlink components).
    (cd "$ws" && pwd)
}

run_tool() {
    local archives_dir="$1"; shift
    LOG_ARCHIVE_DIR="$archives_dir" "$LOG_ARCHIVE" "$@"
}

# --- no argument ---
test_no_argument() {
    local out status
    out="$("$LOG_ARCHIVE" 2>&1)"
    status=$?
    assert_eq "no-arg exit code" "1" "$status"
    [[ "$out" == "Usage: log-archive"* ]]
    report "no-arg usage message" $?
}

# --- help flag ---
test_help_flag() {
    local out status
    out="$("$LOG_ARCHIVE" -h 2>&1)"
    status=$?
    assert_eq "-h exit code" "0" "$status"
    [[ "$out" == "Usage: log-archive"* ]]
    report "-h prints usage" $?
}

# --- nonexistent directory ---
test_nonexistent_dir() {
    local ws status
    ws="$(new_workspace)"
    run_tool "$ws/archives" "$ws/does-not-exist" >/dev/null 2>&1
    status=$?
    assert_eq "nonexistent dir exit code" "2" "$status"
    rm -rf "$ws"
}

# --- empty directory ---
test_empty_dir() {
    local ws src status out
    ws="$(new_workspace)"
    src="$ws/empty"
    mkdir -p "$src"
    out="$(run_tool "$ws/archives" "$src")"
    status=$?
    assert_eq "empty dir exit code" "0" "$status"
    local archive
    archive="$(ls "$ws/archives"/logs_archive_*.tar.gz 2>/dev/null | head -1)"
    [[ -n "$archive" ]]
    report "empty dir archive created" $?
    tar -tzf "$archive" >/dev/null 2>&1
    report "empty dir archive is valid tar" $?
    grep -q " | ${src} | .* | 0 files | .* | format: tar.gz$" "$ws/archives/archive.log"
    report "empty dir logs 0 files" $?
    rm -rf "$ws"
}

# --- single file ---
test_single_file() {
    local ws src status
    ws="$(new_workspace)"
    src="$ws/single"
    mkdir -p "$src"
    echo "hello world" > "$src/app.log"
    run_tool "$ws/archives" "$src" >/dev/null
    status=$?
    assert_eq "single file exit code" "0" "$status"
    local archive
    archive="$(ls "$ws/archives"/logs_archive_*.tar.gz | head -1)"
    tar -tzf "$archive" | grep -q "^\./app\.log$"
    report "single file preserved with relative path" $?
    grep -q " | ${src} | .* | 1 files | .* | format: tar.gz$" "$ws/archives/archive.log"
    report "single file logs 1 file" $?
    rm -rf "$ws"
}

# --- nested structure ---
test_nested_structure() {
    local ws src
    ws="$(new_workspace)"
    src="$ws/nested"
    mkdir -p "$src/a/b/c"
    echo "1" > "$src/top.log"
    echo "2" > "$src/a/mid.log"
    echo "3" > "$src/a/b/c/deep.log"
    run_tool "$ws/archives" "$src" >/dev/null
    local archive
    archive="$(ls "$ws/archives"/logs_archive_*.tar.gz | head -1)"
    local listing
    listing="$(tar -tzf "$archive")"
    echo "$listing" | grep -q "^\./top\.log$"
    report "nested: top-level file present" $?
    echo "$listing" | grep -q "^\./a/mid\.log$"
    report "nested: mid-level file present" $?
    echo "$listing" | grep -q "^\./a/b/c/deep\.log$"
    report "nested: deep file present" $?
    ! echo "$listing" | grep -q "^/"
    report "nested: no absolute paths in archive" $?
    grep -q " | ${src} | .* | 3 files | .* | format: tar.gz$" "$ws/archives/archive.log"
    report "nested: logs 3 files" $?
    rm -rf "$ws"
}

# --- symlinks ---
test_symlink_warning() {
    local ws src status err
    ws="$(new_workspace)"
    src="$ws/symlinked"
    mkdir -p "$src"
    echo "real" > "$src/real.log"
    ln -s "real.log" "$src/link.log"
    err="$(run_tool "$ws/archives" "$src" 2>&1 >/dev/null)"
    status=$?
    assert_eq "symlink dir exit code" "0" "$status"
    [[ "$err" == *"symlink"* ]]
    report "symlink warning printed" $?
    rm -rf "$ws"
}

# --- archive log line format ---
test_log_line_format() {
    local ws src
    ws="$(new_workspace)"
    src="$ws/fmt"
    mkdir -p "$src"
    echo "x" > "$src/a.log"
    run_tool "$ws/archives" "$src" >/dev/null
    grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \| .+ \| logs_archive_[0-9]{8}_[0-9]{6}\.tar\.gz \| [0-9]+ files \| [0-9]+ bytes \| format: tar\.gz$' \
        "$ws/archives/archive.log"
    report "archive.log line matches expected format" $?
    rm -rf "$ws"
}

# --- cleanup / -k, --keep ---
test_cleanup_keep() {
    local ws src status
    ws="$(new_workspace)"
    src="$ws/cleanup"
    mkdir -p "$src"
    echo "x" > "$src/a.log"

    local i
    for i in 1 2 3 4; do
        run_tool "$ws/archives" "$src" >/dev/null
        sleep 1.1
    done
    local before after
    before="$(ls "$ws/archives"/logs_archive_*.tar.gz | wc -l | tr -d ' ')"
    assert_eq "cleanup: 4 archives exist before -k" "4" "$before"

    run_tool "$ws/archives" -k 2 "$src" >/dev/null
    status=$?
    assert_eq "cleanup: -k run exit code" "0" "$status"
    after="$(ls "$ws/archives"/logs_archive_*.tar.gz | wc -l | tr -d ' ')"
    assert_eq "cleanup: keeps only N archives" "2" "$after"
    grep -q "| CLEANUP | deleted logs_archive_" "$ws/archives/archive.log"
    report "cleanup: CLEANUP lines written to archive.log" $?
    rm -rf "$ws"
}

test_cleanup_invalid_values() {
    local ws src status
    ws="$(new_workspace)"
    src="$ws/cleanup-invalid"
    mkdir -p "$src"
    echo "x" > "$src/a.log"

    run_tool "$ws/archives" -k 0 "$src" >/dev/null 2>&1
    status=$?
    assert_eq "cleanup: -k 0 rejected" "1" "$status"

    run_tool "$ws/archives" -k abc "$src" >/dev/null 2>&1
    status=$?
    assert_eq "cleanup: -k non-numeric rejected" "1" "$status"
    rm -rf "$ws"
}

# --- formats / -f, --format ---
test_formats() {
    local ws src
    ws="$(new_workspace)"
    src="$ws/formats"
    mkdir -p "$src"
    echo "x" > "$src/a.log"

    local fmt ext archive status
    for fmt in tar tar.gz tar.bz2 tar.xz; do
        rm -f "$ws/archives"/logs_archive_*
        run_tool "$ws/archives" -f "$fmt" "$src" >/dev/null
        status=$?
        assert_eq "format $fmt: exit code" "0" "$status"
        archive="$(ls "$ws/archives"/logs_archive_*."$fmt" 2>/dev/null | head -1)"
        [[ -n "$archive" ]]
        report "format $fmt: filename has correct extension" $?
        tar -tf "$archive" >/dev/null 2>&1
        report "format $fmt: archive is extractable" $?
    done

    run_tool "$ws/archives" -f zip "$src" >/dev/null 2>&1
    status=$?
    assert_eq "invalid format rejected" "1" "$status"
    rm -rf "$ws"
}

# --- exclusions / -e, --exclude ---
test_exclusions() {
    local ws src
    ws="$(new_workspace)"
    src="$ws/exclude"
    mkdir -p "$src/sub"
    echo "1" > "$src/app.log"
    echo "2" > "$src/debug.tmp"
    echo "3" > "$src/sub/nested.log"

    run_tool "$ws/archives" -e "*.tmp" "$src" >/dev/null
    local archive listing
    archive="$(ls "$ws/archives"/logs_archive_*.tar.gz | head -1)"
    listing="$(tar -tzf "$archive")"
    ! echo "$listing" | grep -q "debug\.tmp"
    report "exclude: pattern removes matching file" $?
    echo "$listing" | grep -q "^\./app\.log$"
    report "exclude: non-matching files still archived" $?
    grep -q "2 files archived | 1 excluded" "$ws/archives/archive.log"
    report "exclude: archive.log records excluded count" $?
    rm -f "$ws/archives"/logs_archive_*

    run_tool "$ws/archives" -e "*.tmp|sub/*" "$src" >/dev/null
    archive="$(ls "$ws/archives"/logs_archive_*.tar.gz | head -1)"
    listing="$(tar -tzf "$archive")"
    ! echo "$listing" | grep -q "nested\.log"
    report "exclude: pipe-separated patterns both applied" $?
    rm -f "$ws/archives"/logs_archive_*

    run_tool "$ws/archives" -e "" "$src" >/dev/null 2>&1
    local status=$?
    assert_eq "exclude: empty pattern rejected" "1" "$status"
    rm -rf "$ws"
}

# --- cron scheduling / --schedule ---
test_schedule() {
    local ws src fakebin store
    ws="$(new_workspace)"
    src="$ws/schedule-src"
    mkdir -p "$src"
    echo "x" > "$src/a.log"

    fakebin="$ws/fakebin"
    store="$ws/fake_crontab_store"
    mkdir -p "$fakebin"
    cat > "$fakebin/crontab" <<EOF
#!/usr/bin/env bash
case "\$1" in
  -l) [[ -f "$store" ]] && cat "$store" || exit 1 ;;
  -)  cat > "$store" ;;
  *)  exit 1 ;;
esac
EOF
    chmod +x "$fakebin/crontab"
    ln -s "$LOG_ARCHIVE" "$fakebin/log-archive"

    local status
    PATH="$fakebin:$PATH" LOG_ARCHIVE_DIR="$ws/archives" "$fakebin/log-archive" \
        --schedule "0 2 * * *" "$src" >/dev/null 2>&1
    status=$?
    assert_eq "schedule: valid cron accepted" "0" "$status"
    grep -q "^0 2 \* \* \* .*log-archive .*${src}" "$store"
    report "schedule: crontab entry written with full path and target dir" $?

    PATH="$fakebin:$PATH" LOG_ARCHIVE_DIR="$ws/archives" "$fakebin/log-archive" \
        --schedule "0 2 * * *" "$src" >/dev/null 2>&1
    status=$?
    assert_eq "schedule: duplicate entry rejected" "1" "$status"

    PATH="$fakebin:$PATH" LOG_ARCHIVE_DIR="$ws/archives" "$fakebin/log-archive" \
        --schedule "not a cron expr" "$src" >/dev/null 2>&1
    status=$?
    assert_eq "schedule: invalid cron expression rejected" "1" "$status"

    "$LOG_ARCHIVE" --schedule "0 2 * * *" "$src" >/dev/null 2>&1
    status=$?
    assert_eq "schedule: rejected when log-archive not in PATH" "1" "$status"
    rm -rf "$ws"
}

test_no_argument
test_help_flag
test_nonexistent_dir
test_empty_dir
test_single_file
test_nested_structure
test_symlink_warning
test_log_line_format
test_cleanup_keep
test_cleanup_invalid_values
test_formats
test_exclusions
test_schedule

echo
echo "Passed: $pass_count, Failed: $fail_count"
[[ "$fail_count" -eq 0 ]]
