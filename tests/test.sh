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
    [[ "$out" == "Usage: log-archive <log-directory>" ]]
    report "no-arg usage message" $?
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
    grep -q " | ${src} | .* | 0 files | " "$ws/archives/archive.log"
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
    grep -q " | ${src} | .* | 1 files | " "$ws/archives/archive.log"
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
    grep -q " | ${src} | .* | 3 files | " "$ws/archives/archive.log"
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
    grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \| .+ \| logs_archive_[0-9]{8}_[0-9]{6}\.tar\.gz \| [0-9]+ files \| [0-9]+ bytes$' \
        "$ws/archives/archive.log"
    report "archive.log line matches expected format" $?
    rm -rf "$ws"
}

test_no_argument
test_nonexistent_dir
test_empty_dir
test_single_file
test_nested_structure
test_symlink_warning
test_log_line_format

echo
echo "Passed: $pass_count, Failed: $fail_count"
[[ "$fail_count" -eq 0 ]]
