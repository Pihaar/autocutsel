#!/bin/sh
# Test single-instance enforcement
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
cleanup_instances

echo "=== Single-instance tests ==="

# Start first instance for PRIMARY
"$AUTOCUTSEL" -selection PRIMARY &
PID1=$!
sleep 1
assert_running "first PRIMARY instance runs" "$PID1"

# Second instance for same selection should exit
run_capture 3 "$AUTOCUTSEL" -selection PRIMARY
assert_contains "second PRIMARY instance detects first" "$_output" "another instance is already running"
assert_exit "second PRIMARY instance exits 0" "$_exit_code" 0

# Instance for different selection should work
"$AUTOCUTSEL" -selection CLIPBOARD &
PID2=$!
sleep 1
assert_running "CLIPBOARD instance runs alongside PRIMARY" "$PID2"

# Third instance for CLIPBOARD should also be blocked
run_capture 3 "$AUTOCUTSEL" -selection CLIPBOARD
assert_contains "second CLIPBOARD instance detected" "$_output" "another instance is already running"

# Cleanup
kill "$PID1" "$PID2" 2>/dev/null
wait "$PID1" "$PID2" 2>/dev/null

# After kill, a new instance should start fine
"$AUTOCUTSEL" -selection PRIMARY &
PID3=$!
sleep 1
assert_running "new instance starts after previous killed" "$PID3"
kill "$PID3" 2>/dev/null
wait "$PID3" 2>/dev/null

test_summary
