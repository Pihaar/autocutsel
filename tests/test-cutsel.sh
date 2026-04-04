#!/bin/sh
# Test the cutsel utility
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
# Wait for Xvfb readiness
sleep 3
cleanup_instances

echo "=== cutsel utility tests ==="

# --- Cutbuffer read/write ---

echo "Cutbuffer:"

# Probe: verify cutbuffer writes work on this X server
"$CUTSEL" cut "cutbuf_probe" >/dev/null 2>&1
sleep 1
_probe=$("$CUTSEL" cut 2>/dev/null)
if ! printf '%s' "$_probe" | grep -qF "cutbuf_probe"; then
  echo "  SKIP: cutbuffer writes not functional on this X server"
  _tests_run=$((_tests_run + 3))
  _tests_skipped=$((_tests_skipped + 3))
  _cutbuf_ok=0
else
  _cutbuf_ok=1
fi

if [ "$_cutbuf_ok" -eq 1 ]; then

# Write to cutbuffer and read back
"$CUTSEL" cut "hello_test_value" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" cut
assert_contains "cutbuffer round-trip" "$_output" "hello_test_value"

# Write a different value
"$CUTSEL" cut "second_value" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" cut
assert_contains "cutbuffer update" "$_output" "second_value"
assert_not_contains "cutbuffer replaced old value" "$_output" "hello_test_value"

fi  # _cutbuf_ok

# --- Selection own and read ---

echo ""
echo "Selection:"

# Set selection and read it back
"$CUTSEL" sel "owned_selection_value" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" sel
assert_contains "selection round-trip" "$_output" "owned_selection_value"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# --- UTF-8 selection round-trip ---

echo ""
echo "UTF-8:"

# UTF-8 text with various scripts
"$CUTSEL" sel "Ärger öffnet Über" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" sel
assert_contains "UTF-8 umlauts round-trip" "$_output" "Ärger öffnet Über"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# ASCII-only should also work
"$CUTSEL" sel "plain ASCII 123!@#" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" sel
assert_contains "ASCII round-trip" "$_output" "plain ASCII 123!@#"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# --- Targets command format ---

echo ""
echo "Targets:"

# Query targets from our own owner (which supports all types)
"$CUTSEL" sel "targets_test" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" targets
assert_contains "targets lists UTF8_STRING" "$_output" "UTF8_STRING"
assert_contains "targets lists STRING" "$_output" "STRING"
assert_matches "targets shows count" "$_output" "^[0-9]+ targets"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# --- Length command validation ---

echo ""
echo "Length:"

# Set known-length value and verify
"$CUTSEL" sel "12345" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" length
assert_contains "length reports value" "$_output" "Length is"
assert_matches "length output is decimal number" "$_output" "Length is [0-9]+"
# 5 bytes = 5
assert_contains "length value correct for '12345'" "$_output" "Length is 5"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# Longer string
"$CUTSEL" sel "abcdefghij" &
PID=$!
sleep 1
run_capture 3 "$CUTSEL" length
assert_contains "length correct for 10 chars" "$_output" "Length is 10"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

# --- Cutbuffer isolation from selection ---

if [ "$_cutbuf_ok" -eq 1 ]; then

echo ""
echo "Cutbuffer vs selection isolation:"

# Set cutbuffer to one value, selection to another
"$CUTSEL" cut "cutbuf_only" >/dev/null 2>&1
sleep 0.5
"$CUTSEL" sel "sel_only" &
PID=$!
sleep 1

# Read cutbuffer — should still be the cutbuffer value
run_capture 3 "$CUTSEL" cut
assert_contains "cutbuffer not overwritten by selection" "$_output" "cutbuf_only"
assert_not_contains "cutbuffer does not contain selection value" "$_output" "sel_only"

# Read selection — should be the selection value
run_capture 3 "$CUTSEL" sel
assert_contains "selection not overwritten by cutbuffer" "$_output" "sel_only"
assert_not_contains "selection does not contain cutbuffer value" "$_output" "cutbuf_only"

kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

else  # cutbuffer not functional
  _tests_run=$((_tests_run + 4))
  _tests_skipped=$((_tests_skipped + 4))
  echo "  SKIP: cutbuffer isolation tests (cutbuffer not functional)"
fi

test_summary
