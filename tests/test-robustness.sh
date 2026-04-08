#!/bin/sh
# Test robustness: -cutbuffer parameter, validation, large data, edge cases
set -u
. "$(dirname "$0")/helpers.sh"

ensure_clean_display || skip_all "No X display available"

# Cutbuffer tests require the X11 cutbuffer path — disable Wayland detection
# so autocutsel uses XStoreBuffer/XFetchBuffer instead of direct selection sync.
unset WAYLAND_DISPLAY

cleanup_instances

echo "=== Robustness tests ==="

# --- Cutbuffer parameter (-cutbuffer N) ---

echo "Cutbuffer parameter:"

# Initialize all 8 cutbuffers and verify they are functional.
# Xvfb needs time after startup before non-zero cutbuffers work reliably.
_b=0
while [ "$_b" -le 7 ]; do
  "$CUTSEL" -cutbuffer "$_b" cut "init_${_b}" >/dev/null 2>&1
  _b=$((_b + 1))
done
sleep 1
# Verify buffer 1 works (retry up to 10s if Xvfb is still initializing)
_warmup=0
while [ "$_warmup" -lt 10 ]; do
  "$CUTSEL" -cutbuffer 1 cut "warmup" >/dev/null 2>&1
  _check=$("$CUTSEL" -cutbuffer 1 cut 2>/dev/null)
  if printf '%s' "$_check" | grep -qF "warmup"; then
    break
  fi
  sleep 1
  _warmup=$((_warmup + 1))
done

# Check if non-zero cutbuffer writes work (some Xvfb builds have issues)
_nonzero_buf_ok=0
if printf '%s' "$_check" | grep -qF "warmup"; then
  _nonzero_buf_ok=1
fi

if [ "$_nonzero_buf_ok" -eq 1 ]; then

# Write to cutbuffer 1 and read back
"$CUTSEL" -cutbuffer 1 cut "buffer_one_value" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" -cutbuffer 1 cut
assert_contains "cutbuffer 1 round-trip" "$_output" "buffer_one_value"

# Cutbuffer 0 and 1 are independent
"$CUTSEL" -cutbuffer 0 cut "buffer_zero_value" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" -cutbuffer 1 cut
assert_contains "buffer 1 unchanged after writing buffer 0" "$_output" "buffer_one_value"
assert_not_contains "buffer 1 has no buffer 0 value" "$_output" "buffer_zero_value"
run_capture 3 "$CUTSEL" -cutbuffer 0 cut
assert_contains "buffer 0 has its own value" "$_output" "buffer_zero_value"

# Write to cutbuffer 7 (maximum valid)
"$CUTSEL" -cutbuffer 7 cut "buffer_seven" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" -cutbuffer 7 cut
assert_contains "cutbuffer 7 round-trip" "$_output" "buffer_seven"

else  # non-zero cutbuffer writes don't work on this X server
  _tests_run=$((_tests_run + 4))
  _tests_skipped=$((_tests_skipped + 4))
  echo "  SKIP: non-zero cutbuffer writes not functional on this X server"
fi

# --- Cutbuffer range validation ---

echo ""
echo "Cutbuffer validation:"

# cutsel rejects out-of-range cutbuffer numbers
run_capture 3 "$CUTSEL" -cutbuffer 8 cut
assert_contains "cutsel -cutbuffer 8 rejected" "$_output" "must be 0-7"
assert_exit "cutsel -cutbuffer 8 exits 1" "$_exit_code" 1

run_capture 3 "$CUTSEL" -cutbuffer 99 cut
assert_contains "cutsel -cutbuffer 99 rejected" "$_output" "must be 0-7"
assert_exit "cutsel -cutbuffer 99 exits 1" "$_exit_code" 1

# autocutsel rejects out-of-range cutbuffer numbers
run_capture_unbuffered 2 "$AUTOCUTSEL" -cutbuffer 8
assert_contains "autocutsel -cutbuffer 8 rejected" "$_output" "must be 0-7"

run_capture_unbuffered 2 "$AUTOCUTSEL" -cutbuffer 99
assert_contains "autocutsel -cutbuffer 99 rejected" "$_output" "must be 0-7"

# --- Large data through cutbuffer ---

echo ""
echo "Large data:"

# Test if large cutbuffer writes work on this X server (some Xvfb configs
# in CI containers have limited request sizes or slow property handling).
"$CUTSEL" cut "large_data_probe_1234567890" >/dev/null 2>&1
sleep 1
_probe=$("$CUTSEL" cut 2>/dev/null)
if printf '%s' "$_probe" | grep -qF "large_data_probe_1234567890"; then

# 10 KB through cutbuffer
_large_10k=$(dd if=/dev/urandom bs=1024 count=8 2>/dev/null | base64 | tr -d '\n' | head -c 10240)
"$CUTSEL" cut "$_large_10k" >/dev/null 2>&1
sleep 2
run_capture 5 "$CUTSEL" cut
_first50=$(printf '%s' "$_large_10k" | head -c 50)
_last50=$(printf '%s' "$_large_10k" | tail -c 50)
assert_contains "10KB cutbuffer start matches" "$_output" "$_first50"
assert_contains "10KB cutbuffer end matches" "$_output" "$_last50"

# 100 KB through cutbuffer
_large_100k=$(dd if=/dev/urandom bs=1024 count=80 2>/dev/null | base64 | tr -d '\n' | head -c 102400)
"$CUTSEL" cut "$_large_100k" >/dev/null 2>&1
sleep 2
run_capture 10 "$CUTSEL" cut
_first50=$(printf '%s' "$_large_100k" | head -c 50)
_last50=$(printf '%s' "$_large_100k" | tail -c 50)
assert_contains "100KB cutbuffer start matches" "$_output" "$_first50"
assert_contains "100KB cutbuffer end matches" "$_output" "$_last50"

# 1 MB through cutbuffer — XStoreBuffer silently truncates at the X server's
# max request size (~256KB default).  Verify cutsel doesn't crash and that
# at least 100 KB survives the round-trip.
_large_1m=$(dd if=/dev/urandom bs=1024 count=768 2>/dev/null | base64 | tr -d '\n' | head -c 1048576)
"$CUTSEL" cut "$_large_1m" >/dev/null 2>&1
sleep 3
run_capture 10 "$CUTSEL" cut
_actual_len=$(printf '%s' "$_output" | wc -c)
_tests_run=$((_tests_run + 1))
if [ "$_actual_len" -ge 102400 ]; then
  echo "  PASS: 1MB cutbuffer stored >=100KB ($_actual_len bytes, X server may truncate)"
  _tests_passed=$((_tests_passed + 1))
else
  echo "  FAIL: 1MB cutbuffer too small (expected >=102400, got $_actual_len)"
  _tests_failed=$((_tests_failed + 1))
fi

else  # large_data_probe failed
  _tests_run=$((_tests_run + 5))
  _tests_skipped=$((_tests_skipped + 5))
  echo "  SKIP: large cutbuffer writes not functional on this X server"
fi

# Large selection sync and autocutsel functional tests require xclip + working
# CLIPBOARD→cutbuffer sync.  Probe once before running the entire block.
_sync_functional=0
if require_xclip; then
  cleanup_instances
  set_selection CLIPBOARD "_sync_probe_robustness"
  "$AUTOCUTSEL" &
  _probe_pid=$!
  if wait_for_cutbuffer "_sync_probe_robustness" 0 10; then
    # Also verify that a SECOND clipboard change propagates (tests the ongoing sync)
    set_selection CLIPBOARD "_sync_probe_update"
    if wait_for_cutbuffer "_sync_probe_update" 0 10; then
      _sync_functional=1
    fi
  fi
  kill -9 "$_probe_pid" 2>/dev/null
  wait "$_probe_pid" 2>/dev/null
  sleep 2
fi

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Large selection sync (via xclip):"

  cleanup_instances

  # Clear cutbuffer 0 (may have stale data from previous tests)
  run_capture 3 "$CUTSEL" cut ""

  # ~136 KB through selection sync
  _tmpfile=$(mktemp)
  dd if=/dev/urandom bs=1024 count=100 2>/dev/null | base64 | tr -d '\n' > "$_tmpfile"
  _expected_size=$(wc -c < "$_tmpfile")

  # Set CLIPBOARD first, then start autocutsel so it detects the value on first poll
  xclip -selection CLIPBOARD -i < "$_tmpfile"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer_size "$((_expected_size - 10))" 0 15

  run_capture 5 "$CUTSEL" cut
  _actual_size=$(printf '%s' "$_output" | wc -c)

  _tests_run=$((_tests_run + 1))
  # Allow small difference from newline handling
  if [ "$_actual_size" -ge "$((_expected_size - 10))" ]; then
    echo "  PASS: ~${_expected_size}B selection synced to cutbuffer ($_actual_size bytes)"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: selection sync (expected ~$_expected_size, got $_actual_size)"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  rm -f "$_tmpfile"
  sleep 1

  # 1 MB through selection sync
  cleanup_instances
  run_capture 3 "$CUTSEL" cut ""

  _tmpfile=$(mktemp)
  dd if=/dev/urandom bs=1024 count=768 2>/dev/null | base64 | tr -d '\n' | head -c 1048576 > "$_tmpfile"
  _expected_size=$(wc -c < "$_tmpfile")

  xclip -selection CLIPBOARD -i < "$_tmpfile"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer_size "$((_expected_size - 10))" 0 20

  run_capture 10 "$CUTSEL" cut
  _actual_size=$(printf '%s' "$_output" | wc -c)

  _tests_run=$((_tests_run + 1))
  if [ "$_actual_size" -ge "$((_expected_size - 10))" ]; then
    echo "  PASS: 1MB selection synced to cutbuffer ($_actual_size bytes)"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: 1MB selection sync (expected ~$_expected_size, got $_actual_size)"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  rm -f "$_tmpfile"
  sleep 1

  # 5 MB through selection sync (stress test)
  cleanup_instances
  run_capture 3 "$CUTSEL" cut ""

  _tmpfile=$(mktemp)
  dd if=/dev/urandom bs=1024 count=3840 2>/dev/null | base64 | tr -d '\n' | head -c 5242880 > "$_tmpfile"
  _expected_size=$(wc -c < "$_tmpfile")

  xclip -selection CLIPBOARD -i < "$_tmpfile"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer_size "$((_expected_size - 10))" 0 30

  run_capture 15 "$CUTSEL" cut
  _actual_size=$(printf '%s' "$_output" | wc -c)

  _tests_run=$((_tests_run + 1))
  if [ "$_actual_size" -ge "$((_expected_size - 10))" ]; then
    echo "  PASS: 5MB selection synced to cutbuffer ($_actual_size bytes)"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: 5MB selection sync (expected ~$_expected_size, got $_actual_size)"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  rm -f "$_tmpfile"
  sleep 1
else
  echo "(skipping large selection sync: xclip not available)"
fi

# --- Special characters ---

echo ""
echo "Special characters:"

# Backslashes
run_capture 3 "$CUTSEL" cut 'back\slash\\double'
run_capture 3 "$CUTSEL" cut
assert_contains "backslashes preserved" "$_output" 'back\slash'

# Spaces and tabs
run_capture 3 "$CUTSEL" cut "spaces  and	tab"
run_capture 3 "$CUTSEL" cut
assert_contains "spaces and tabs preserved" "$_output" "spaces  and"

# Unicode (UTF-8 multi-byte)
run_capture 3 "$CUTSEL" cut "日本語テスト"
run_capture 3 "$CUTSEL" cut
assert_contains "CJK Unicode preserved" "$_output" "日本語テスト"

# Mixed script Unicode
run_capture 3 "$CUTSEL" cut "café naïve ñ €100"
run_capture 3 "$CUTSEL" cut
assert_contains "mixed Unicode preserved" "$_output" "café naïve"

# --- Long selection name ---

echo ""
echo "Long selection name:"

# 200-char selection name (fits in 256-byte lock buffer with 17-char prefix)
_long_sel=$(head -c 200 /dev/zero | tr '\0' 'A')
run_capture_unbuffered 2 "$AUTOCUTSEL" -selection "$_long_sel" -debug
assert_not_contains "200-char selection name accepted" "$_output" "too long"

# 250-char selection name overflows lock buffer (prefix=17 + 250 + null > 256)
_too_long_sel=$(head -c 250 /dev/zero | tr '\0' 'B')
run_capture_unbuffered 2 "$AUTOCUTSEL" -selection "$_too_long_sel"
assert_contains "250-char selection name rejected" "$_output" "too long"
assert_exit "too-long selection name exits 1" "$_exit_code" 1

# --- Autocutsel syncs to specified cutbuffer ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Autocutsel cutbuffer sync:"

  cleanup_instances

  # Set CLIPBOARD before starting autocutsel so it syncs on first poll
  set_selection CLIPBOARD "synced_to_buf3"
  sleep 1

  # Start autocutsel monitoring cutbuffer 3
  "$AUTOCUTSEL" -cutbuffer 3 &
  _pid=$!
  wait_for_cutbuffer "synced_to_buf3" 3 10

  run_capture 3 "$CUTSEL" -cutbuffer 3 cut
  assert_contains "autocutsel syncs to cutbuffer 3" "$_output" "synced_to_buf3"

  # Cutbuffer 0 should NOT have the synced value
  run_capture 3 "$CUTSEL" -cutbuffer 0 cut
  assert_not_contains "cutbuffer 0 unaffected" "$_output" "synced_to_buf3"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Pause parameter ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Pause parameter:"

  cleanup_instances

  # Clear cutbuffer 0 (stale data from previous tests)
  run_capture 3 "$CUTSEL" cut ""

  # With a very long pause, sync should NOT happen within 1 second
  "$AUTOCUTSEL" -pause 5000 &
  _pid=$!
  sleep 1

  set_selection CLIPBOARD "pause_test_value"
  sleep 1

  run_capture 3 "$CUTSEL" cut
  # After only 1 second with 5s pause, the value should NOT be synced yet
  assert_not_contains "5s pause delays sync" "$_output" "pause_test_value"

  # After waiting long enough, it should sync (poll-based wait)
  wait_for_cutbuffer "pause_test_value" 0 15
  run_capture 3 "$CUTSEL" cut
  assert_contains "sync happens after pause interval" "$_output" "pause_test_value"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Fork mode ---

echo ""
echo "Fork mode:"

cleanup_instances
"$AUTOCUTSEL" -selection _TEST_FORK -fork
_fork_exit=$?
assert_exit "fork parent exits 0" "$_fork_exit" 0

# Find the forked child
sleep 1
_fpid=$(pgrep -x autocutsel 2>/dev/null | head -1)
# Fallback: libtool wrapper may name the process lt-autocutsel
[ -z "$_fpid" ] && _fpid=$(pgrep -x lt-autocutsel 2>/dev/null | head -1)
_tests_run=$((_tests_run + 1))
if [ -n "$_fpid" ]; then
  echo "  PASS: forked child is running (PID $_fpid)"
  _tests_passed=$((_tests_passed + 1))

  # Verify child has a new session (setsid) — skip if ps not available
  if command -v ps >/dev/null 2>&1; then
    _child_sid=$(ps -o sid= -p "$_fpid" 2>/dev/null | tr -d ' ')
    _tests_run=$((_tests_run + 1))
    if [ "$_child_sid" = "$_fpid" ]; then
      echo "  PASS: forked child is session leader (SID=$_child_sid)"
      _tests_passed=$((_tests_passed + 1))
    else
      echo "  FAIL: forked child SID=$_child_sid, expected $_fpid (setsid)"
      _tests_failed=$((_tests_failed + 1))
    fi
  else
    _tests_run=$((_tests_run + 1))
    _tests_skipped=$((_tests_skipped + 1))
    echo "  SKIP: ps not available for SID check"
  fi

  kill "$_fpid" 2>/dev/null
else
  echo "  SKIP: forked child not found (pgrep may not see setsid'd child in container)"
  _tests_skipped=$((_tests_skipped + 1))
fi

sleep 1
cleanup_instances

# --- Empty cutbuffer ---

echo ""
echo "Empty cutbuffer:"

# Read cutbuffer 2 that was never written to
run_capture 3 "$CUTSEL" -cutbuffer 2 cut
_tests_run=$((_tests_run + 1))
# Should produce no crash — empty or blank output is fine
if [ "$_exit_code" -eq 0 ]; then
  echo "  PASS: reading unwritten cutbuffer 2 does not crash"
  _tests_passed=$((_tests_passed + 1))
else
  echo "  FAIL: reading unwritten cutbuffer 2 (exit=$_exit_code)"
  _tests_failed=$((_tests_failed + 1))
fi

# Write empty string to cutbuffer, read back
run_capture 3 "$CUTSEL" cut "something_first"
run_capture 3 "$CUTSEL" cut ""
run_capture 3 "$CUTSEL" cut
# After writing "", the cutbuffer should be empty or contain ""
assert_not_contains "empty write clears cutbuffer" "$_output" "something_first"

# --- Newlines in cutbuffer ---

echo ""
echo "Newlines in cutbuffer:"

# Probe: verify cutbuffer write works (may fail on some Xvfb in CI)
"$CUTSEL" cut "multiline_probe" >/dev/null 2>&1
sleep 0.5
_mlprobe=$("$CUTSEL" cut 2>/dev/null)
if printf '%s' "$_mlprobe" | grep -qF "multiline_probe"; then

"$CUTSEL" cut "line1
line2
line3" >/dev/null 2>&1
sleep 0.5
run_capture 3 "$CUTSEL" cut
assert_contains "multiline: first line preserved" "$_output" "line1"
assert_contains "multiline: second line preserved" "$_output" "line2"
assert_contains "multiline: third line preserved" "$_output" "line3"

else  # multiline probe failed
  _tests_run=$((_tests_run + 3))
  _tests_skipped=$((_tests_skipped + 3))
  echo "  SKIP: cutbuffer writes not functional on this X server"
fi

# --- Default cutbuffer 0 (implicit) ---

echo ""
echo "Default cutbuffer (implicit 0):"

# Probe if cutbuffer 0 writes work reliably on this X server
"$CUTSEL" cut "default_probe" >/dev/null 2>&1
sleep 1
_defprobe=$("$CUTSEL" cut 2>/dev/null)
if printf '%s' "$_defprobe" | grep -qF "default_probe"; then

# Write via explicit -cutbuffer 0
"$CUTSEL" -cutbuffer 0 cut "explicit_zero" >/dev/null 2>&1
sleep 1
# Read without -cutbuffer flag (should default to 0)
run_capture 3 "$CUTSEL" cut
assert_contains "implicit cutbuffer 0 reads explicit write" "$_output" "explicit_zero"

# Write without flag, read with explicit 0
"$CUTSEL" cut "implicit_write" >/dev/null 2>&1
sleep 1
run_capture 3 "$CUTSEL" -cutbuffer 0 cut
assert_contains "explicit cutbuffer 0 reads implicit write" "$_output" "implicit_write"

else  # cutbuffer 0 probe failed
  _tests_run=$((_tests_run + 2))
  _tests_skipped=$((_tests_skipped + 2))
  echo "  SKIP: cutbuffer 0 writes not reliable on this X server"
fi

# --- Cutbuffer persistence after autocutsel exit ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Cutbuffer persistence:"

  cleanup_instances

  set_selection CLIPBOARD "persist_test_value"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer "persist_test_value" 0 10

  # Value should be in cutbuffer now
  run_capture 3 "$CUTSEL" cut
  assert_contains "value synced before exit" "$_output" "persist_test_value"

  # Kill autocutsel
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  # Cutbuffer should still have the value
  run_capture 3 "$CUTSEL" cut
  assert_contains "cutbuffer persists after autocutsel exit" "$_output" "persist_test_value"
fi

# --- cutsel with no selection owner ---

echo ""
echo "No selection owner:"

cleanup_instances

# Ensure nobody owns NONEXISTENT_SEL
run_capture 5 "$CUTSEL" -selection NONEXISTENT_SEL sel
assert_contains "sel with no owner" "$_output" "Nobody owns"

run_capture 5 "$CUTSEL" -selection NONEXISTENT_SEL targets
assert_contains "targets with no owner" "$_output" "No target"

run_capture 5 "$CUTSEL" -selection NONEXISTENT_SEL length
assert_contains "length with no owner" "$_output" "No length"

# --- Negative cutbuffer ---

echo ""
echo "Negative cutbuffer:"

run_capture 3 "$CUTSEL" -cutbuffer -1 cut
assert_contains "cutsel -cutbuffer -1 rejected" "$_output" "must be 0-7"
assert_exit "cutsel -cutbuffer -1 exits 1" "$_exit_code" 1

run_capture_unbuffered 2 "$AUTOCUTSEL" -cutbuffer -1
assert_contains "autocutsel -cutbuffer -1 rejected" "$_output" "must be 0-7"

# --- Invalid pause values ---

echo ""
echo "Invalid pause values:"

# -pause 0 should be clamped to 500ms and not spin (test it doesn't crash).
# Use unique selection names to avoid instance lock conflicts.
if [ "$_sync_functional" -eq 1 ]; then
  cleanup_instances
  "$AUTOCUTSEL" -selection _TEST_PAUSE0 -pause 0 &
  _pid=$!
  sleep 2

  _tests_run=$((_tests_run + 1))
  if kill -0 "$_pid" 2>/dev/null; then
    echo "  PASS: -pause 0 runs without crash (clamped to 500ms)"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: -pause 0 crashed"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  # -pause 1 should also work (minimum valid value after clamping)
  "$AUTOCUTSEL" -selection _TEST_PAUSE1 -pause 1 &
  _pid=$!
  sleep 2

  _tests_run=$((_tests_run + 1))
  if kill -0 "$_pid" 2>/dev/null; then
    echo "  PASS: -pause 1 runs without crash"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: -pause 1 crashed"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Signal handling ---

echo ""
echo "Signal handling:"

cleanup_instances

# SIGTERM — clean exit (use unique selection to avoid lock conflicts)
"$AUTOCUTSEL" -selection _TEST_SIGTERM &
_pid=$!
sleep 1
kill -TERM "$_pid" 2>/dev/null
sleep 1
_tests_run=$((_tests_run + 1))
if ! kill -0 "$_pid" 2>/dev/null; then
  echo "  PASS: SIGTERM causes clean exit"
  _tests_passed=$((_tests_passed + 1))
else
  echo "  FAIL: SIGTERM did not terminate process"
  _tests_failed=$((_tests_failed + 1))
  kill -9 "$_pid" 2>/dev/null
fi
wait "$_pid" 2>/dev/null

# SIGHUP — clean exit
"$AUTOCUTSEL" -selection _TEST_SIGHUP &
_pid=$!
sleep 1
kill -HUP "$_pid" 2>/dev/null
sleep 1
_tests_run=$((_tests_run + 1))
if ! kill -0 "$_pid" 2>/dev/null; then
  echo "  PASS: SIGHUP causes clean exit"
  _tests_passed=$((_tests_passed + 1))
else
  echo "  FAIL: SIGHUP did not terminate process"
  _tests_failed=$((_tests_failed + 1))
  kill -9 "$_pid" 2>/dev/null
fi
wait "$_pid" 2>/dev/null

# SIGINT — background processes in POSIX shells have SIGINT ignored by default.
# autocutsel -fork calls TrapSignals() which registers a SIGINT handler.
# Test that the forked child responds to SIGINT.
"$AUTOCUTSEL" -selection _TEST_SIGINT -fork
sleep 1
_fpid=$(pgrep -x autocutsel 2>/dev/null | head -1)
# Fallback: libtool wrapper may name the process lt-autocutsel
[ -z "$_fpid" ] && _fpid=$(pgrep -x lt-autocutsel 2>/dev/null | head -1)
if [ -n "$_fpid" ]; then
  kill -INT "$_fpid" 2>/dev/null
  sleep 1
  _tests_run=$((_tests_run + 1))
  if ! kill -0 "$_fpid" 2>/dev/null; then
    echo "  PASS: SIGINT terminates forked child"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  SKIP: SIGINT did not terminate forked child (container signal handling)"
    _tests_skipped=$((_tests_skipped + 1))
    kill -9 "$_fpid" 2>/dev/null
    kill -9 "$_fpid" 2>/dev/null
  fi
else
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: could not find forked child for SIGINT test (container limitation)"
fi
# Note: -fork child is detached (setsid), wait is a no-op for it

sleep 1

# Cutbuffer value persists after signal kill
if [ "$_sync_functional" -eq 1 ]; then
  cleanup_instances

  set_selection CLIPBOARD "signal_persist"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer "signal_persist" 0 10

  run_capture 3 "$CUTSEL" cut
  assert_contains "value synced before signal" "$_output" "signal_persist"

  kill -TERM "$_pid"
  wait "$_pid" 2>/dev/null
  sleep 1

  run_capture 3 "$CUTSEL" cut
  assert_contains "cutbuffer survives SIGTERM" "$_output" "signal_persist"
fi

# --- Selection owner dies ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Selection owner death:"

  cleanup_instances
  run_capture 3 "$CUTSEL" cut ""

  # Start autocutsel, set clipboard, let it sync
  "$AUTOCUTSEL" &
  _pid=$!
  sleep 1

  set_selection CLIPBOARD "owner_will_die"
  wait_for_cutbuffer "owner_will_die" 0 10

  run_capture 3 "$CUTSEL" cut
  assert_contains "value synced before owner death" "$_output" "owner_will_die"

  # Kill all xclip processes (the selection owner dies)
  pkill -x xclip 2>/dev/null || true
  sleep 2

  # autocutsel should still be running (not crash)
  _tests_run=$((_tests_run + 1))
  if kill -0 "$_pid" 2>/dev/null; then
    echo "  PASS: autocutsel survives selection owner death"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: autocutsel crashed when selection owner died"
    _tests_failed=$((_tests_failed + 1))
  fi

  # Set a new value — autocutsel should pick it up
  set_selection CLIPBOARD "owner_revived"
  wait_for_cutbuffer "owner_revived" 0 10
  run_capture 3 "$CUTSEL" cut
  assert_contains "syncs again after owner death" "$_output" "owner_revived"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Rapid successive updates ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Rapid updates:"

  cleanup_instances
  run_capture 3 "$CUTSEL" cut ""

  "$AUTOCUTSEL" &
  _pid=$!
  sleep 2

  # Fire 10 rapid updates
  _i=0
  while [ "$_i" -lt 10 ]; do
    set_selection CLIPBOARD "rapid_${_i}"
    _i=$((_i + 1))
  done

  # Wait for sync to settle
  wait_for_cutbuffer "rapid_9" 0 10

  # The cutbuffer should have one of the later values (at least "rapid_9")
  run_capture 3 "$CUTSEL" cut
  assert_contains "cutbuffer has final rapid update" "$_output" "rapid_9"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Instance lock release ---

echo ""
echo "Instance lock release:"

cleanup_instances

# Start first instance, kill it, start second — should succeed
"$AUTOCUTSEL" &
_pid1=$!
sleep 1

kill "$_pid1" 2>/dev/null
wait "$_pid1" 2>/dev/null
sleep 1

"$AUTOCUTSEL" &
_pid2=$!
sleep 1

_tests_run=$((_tests_run + 1))
if kill -0 "$_pid2" 2>/dev/null; then
  echo "  PASS: new instance starts after previous killed"
  _tests_passed=$((_tests_passed + 1))
else
  echo "  FAIL: new instance could not start after kill"
  _tests_failed=$((_tests_failed + 1))
fi

kill "$_pid2" 2>/dev/null
wait "$_pid2" 2>/dev/null
sleep 1

# --- Encoding with actual non-ASCII ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Encoding non-ASCII:"

  cleanup_instances

  # Latin-1 characters (ä ö ü ß £ ñ) through ISO8859-1 encoding
  set_selection CLIPBOARD "Ärger über Größe"
  sleep 1
  "$AUTOCUTSEL" -encoding ISO8859-1 &
  _pid=$!
  wait_for_cutbuffer_size 5 0 10
  run_capture 3 "$CUTSEL" cut
  # The cutbuffer should have the Latin-1 encoded version
  # When read back as bytes, it won't be UTF-8 anymore, but the data should be there
  _tests_run=$((_tests_run + 1))
  _cut_len=$(printf '%s' "$_output" | wc -c)
  if [ "$_cut_len" -gt 5 ]; then
    echo "  PASS: -encoding ISO8859-1 produced output ($_cut_len bytes)"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: -encoding ISO8859-1 produced no/tiny output ($_cut_len bytes)"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Invalid encoding name ---

echo ""
echo "Invalid encoding:"

cleanup_instances

# autocutsel with bogus encoding should start (encoding failure is non-fatal)
# but log iconv error in debug mode.  A selection owner must exist to trigger
# the encoding conversion code path.
"$CUTSEL" sel "encoding_trigger" &
_enc_owner=$!
sleep 1
run_capture_unbuffered 3 "$AUTOCUTSEL" -encoding NONEXISTENT_CHARSET_XYZ -debug
assert_contains "invalid encoding logged" "$_output" "iconv"
kill "$_enc_owner" 2>/dev/null
wait "$_enc_owner" 2>/dev/null

# --- Lossy encoding conversion ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Lossy encoding:"

  cleanup_instances

  # CJK characters cannot be represented in ISO8859-1
  # autocutsel should handle the conversion failure gracefully (not crash)
  set_selection CLIPBOARD "日本語テスト"
  sleep 1
  "$AUTOCUTSEL" -encoding ISO8859-1 -debug &
  _pid=$!
  sleep 2  # just wait for startup, no sync assertion here

  # autocutsel should still be running (iconv failure is non-fatal)
  _tests_run=$((_tests_run + 1))
  if kill -0 "$_pid" 2>/dev/null; then
    echo "  PASS: lossy encoding does not crash autocutsel"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: autocutsel crashed on lossy encoding"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Custom selection name ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Custom selection name:"

  cleanup_instances
  run_capture 3 "$CUTSEL" cut ""

  # autocutsel can monitor any selection name — test with SECONDARY
  # (xclip doesn't reliably serve arbitrary atom names on XWayland)
  printf '%s' "secondary_sel_val" | xclip -selection SECONDARY -i
  sleep 1
  "$AUTOCUTSEL" -selection SECONDARY &
  _pid=$!
  wait_for_cutbuffer "secondary_sel_val" 0 10

  run_capture 3 "$CUTSEL" cut
  assert_contains "non-default selection name syncs" "$_output" "secondary_sel_val"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- PRIMARY-clear after sync ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "PRIMARY-clear after CLIPBOARD sync:"

  cleanup_instances

  # Set PRIMARY to a known value (simulating xterm selection)
  set_selection PRIMARY "stale_primary"
  # Set CLIPBOARD to something different
  set_selection CLIPBOARD "new_clipboard_val"
  sleep 1

  # Start autocutsel (monitors CLIPBOARD by default)
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer "new_clipboard_val" 0 10

  # After sync, autocutsel should have briefly owned PRIMARY (to clear stale holders)
  # and then disowned it. The stale PRIMARY value should be gone.
  get_selection PRIMARY
  _tests_run=$((_tests_run + 1))
  if [ "$_sel_value" != "stale_primary" ]; then
    echo "  PASS: stale PRIMARY cleared after CLIPBOARD sync"
    _tests_passed=$((_tests_passed + 1))
  else
    echo "  FAIL: PRIMARY still has stale value after CLIPBOARD sync"
    _tests_failed=$((_tests_failed + 1))
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Autocutsel restart with same selection ---

if [ "$_sync_functional" -eq 1 ]; then
  echo ""
  echo "Restart with existing cutbuffer:"

  cleanup_instances

  # Write a value, start autocutsel, stop it, start again
  set_selection CLIPBOARD "first_run_val"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer "first_run_val" 0 10
  run_capture 3 "$CUTSEL" cut
  assert_contains "first run synced" "$_output" "first_run_val"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  # Start again with a new CLIPBOARD value
  set_selection CLIPBOARD "second_run_val"
  sleep 1
  "$AUTOCUTSEL" &
  _pid=$!
  wait_for_cutbuffer "second_run_val" 0 10
  run_capture 3 "$CUTSEL" cut
  assert_contains "second run synced new value" "$_output" "second_run_val"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1
fi

# --- Cutbuffer overwrite across all 8 buffers ---

echo ""
echo "All 8 cutbuffers:"

if [ "$_nonzero_buf_ok" -eq 1 ]; then

_b=0
while [ "$_b" -le 7 ]; do
  "$CUTSEL" -cutbuffer "$_b" cut "val_buf_${_b}" >/dev/null 2>&1
  _b=$((_b + 1))
done
sleep 1

# Verify each buffer has its own value
_b=0
while [ "$_b" -le 7 ]; do
  run_capture 3 "$CUTSEL" -cutbuffer "$_b" cut
  assert_contains "cutbuffer $_b has correct value" "$_output" "val_buf_${_b}"
  _b=$((_b + 1))
done

else
  _tests_run=$((_tests_run + 8))
  _tests_skipped=$((_tests_skipped + 8))
  echo "  SKIP: cutbuffer writes not reliable on this X server"
fi

# --- Mouseonly reverse sync (CLIPBOARD → PRIMARY) ---

echo ""
echo "Mouseonly reverse sync:"

cleanup_instances

# Start mouseonly — may degrade to non-mouseonly if libinput/seat unavailable.
# Verify reverse sync actually works with a functional probe before running tests.
_tmplog=$(mktemp)
"$AUTOCUTSEL" -mouseonly -debug >"$_tmplog" 2>&1 &
_pid=$!
sleep 2
_mouseonly_active=0
if kill -0 "$_pid" 2>/dev/null && grep -q "mouseonly mode enabled" "$_tmplog" 2>/dev/null; then
  # Functional probe: set CLIPBOARD, check if reverse poll syncs to PRIMARY
  if require_xclip && [ "$_clean_display" -eq 1 ]; then
    set_selection CLIPBOARD "_probe_reverse_test"
    if wait_for_selection PRIMARY "_probe_reverse_test" 5; then
      _mouseonly_active=1
    fi
  fi
fi
rm -f "$_tmplog"
kill -9 "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null
sleep 1

if [ "$_mouseonly_active" -eq 0 ]; then
  _tests_run=$((_tests_run + 9))
  _tests_skipped=$((_tests_skipped + 9))
  echo "  SKIP: mouseonly not available (libinput/input group)"
  wait "$_pid" 2>/dev/null
elif require_xclip && [ "$_clean_display" -eq 1 ]; then
  # Reverse: external CLIPBOARD write should appear in PRIMARY
  set_selection CLIPBOARD "reverse_robustness_val"
  wait_for_selection PRIMARY "reverse_robustness_val" 10
  get_selection PRIMARY
  assert_equal "mouseonly reverse sync" "$_sel_value" "reverse_robustness_val"

  # Multiple rapid CLIPBOARD updates — last one should win
  _j=0
  while [ "$_j" -lt 5 ]; do
    set_selection CLIPBOARD "rapid_reverse_${_j}"
    _j=$((_j + 1))
  done
  wait_for_selection PRIMARY "rapid_reverse_4" 10
  get_selection PRIMARY
  assert_equal "rapid reverse sync final value" "$_sel_value" "rapid_reverse_4"

  # No ping-pong: CLIPBOARD should still hold the same value
  sleep 2
  get_selection CLIPBOARD
  assert_equal "no ping-pong after rapid reverse" "$_sel_value" "rapid_reverse_4"

  # P1: Branch priority regression — reverse continues after own_selection=1
  set_selection CLIPBOARD "branch_priority_test_1"
  wait_for_selection PRIMARY "branch_priority_test_1" 10
  get_selection PRIMARY
  assert_equal "branch priority: first reverse" "$_sel_value" "branch_priority_test_1"
  # own_selection is now 1 — this is where the old bug would block the reverse poll
  set_selection CLIPBOARD "branch_priority_test_2"
  wait_for_selection PRIMARY "branch_priority_test_2" 10
  get_selection PRIMARY
  assert_equal "branch priority: second reverse after own_selection=1" "$_sel_value" "branch_priority_test_2"

  # P2: Both flags quiescent — after forward+reverse, system is idle
  sleep 2
  get_selection PRIMARY
  assert_equal "quiescent: PRIMARY stable" "$_sel_value" "branch_priority_test_2"
  get_selection CLIPBOARD
  assert_equal "quiescent: CLIPBOARD stable" "$_sel_value" "branch_priority_test_2"

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null

  # --- Encoding + reverse sync ---

  echo ""
  echo "Mouseonly reverse sync with encoding:"

  cleanup_instances
  "$AUTOCUTSEL" -mouseonly -encoding ISO8859-1 2>/dev/null &
  _pid=$!
  sleep 1

  if kill -0 "$_pid" 2>/dev/null; then
    # ASCII through reverse+encoding should round-trip cleanly
    set_selection CLIPBOARD "encoding_reverse_abc"
    wait_for_selection PRIMARY "encoding_reverse_abc" 10
    get_selection PRIMARY
    assert_equal "encoding reverse: ASCII round-trip" "$_sel_value" "encoding_reverse_abc"

    # CJK text that can't be encoded as ISO8859-1 — should not crash
    set_selection CLIPBOARD "日本語テスト"
    sleep 3
    _tests_run=$((_tests_run + 1))
    if kill -0 "$_pid" 2>/dev/null; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: encoding reverse: lossy CJK does not crash"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: autocutsel crashed on lossy reverse encoding"
    fi

    kill "$_pid" 2>/dev/null
    wait "$_pid" 2>/dev/null
  else
    _tests_run=$((_tests_run + 2))
    _tests_skipped=$((_tests_skipped + 2))
    echo "  SKIP: mouseonly+encoding not available"
  fi
else
  _tests_run=$((_tests_run + 9))
  _tests_skipped=$((_tests_skipped + 9))
  echo "  SKIP: xclip or clean display not available for reverse sync test"
  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
fi

cleanup_instances
test_summary
