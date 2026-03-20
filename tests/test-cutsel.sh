#!/bin/sh
# Test the cutsel utility
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
cleanup_instances

echo "=== cutsel utility tests ==="

# Write to cutbuffer and read back
run_capture 3 "$CUTSEL" cut "hello_test_value"
run_capture 3 "$CUTSEL" cut
assert_contains "cutbuffer round-trip" "$_output" "hello_test_value"

# Write a different value
run_capture 3 "$CUTSEL" cut "second_value"
run_capture 3 "$CUTSEL" cut
assert_contains "cutbuffer update" "$_output" "second_value"
assert_not_contains "cutbuffer replaced old value" "$_output" "hello_test_value"

# Set selection and read it back
# Start owning the selection in background
"$CUTSEL" sel "owned_selection_value" &
PID=$!
sleep 1
# Read the selection
run_capture 3 "$CUTSEL" sel
assert_contains "selection round-trip" "$_output" "owned_selection_value"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# Query targets
run_capture 3 "$CUTSEL" targets
assert_contains "targets command works" "$_output" "targets"

# Query length
run_capture 3 "$CUTSEL" length
# Should return some response (either a length or "No length received")
_tests_run=$((_tests_run + 1))
if [ -n "$_output" ]; then
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: length command produces output"
else
  _tests_failed=$((_tests_failed + 1))
  echo "  FAIL: length command produces no output"
fi

test_summary
