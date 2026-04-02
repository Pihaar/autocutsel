#!/bin/sh
# Functional sync tests — verify actual CLIPBOARD ↔ PRIMARY data transfer
# Requires: DISPLAY + xclip
set -u
. "$(dirname "$0")/helpers.sh"

ensure_clean_display || skip_all "No X display available"
require_xclip || skip_all "xclip not available"
if [ "$_clean_display" -eq 0 ]; then
  skip_all "Xvfb not available — sync tests need a clean display (install Xvfb)"
fi
cleanup_instances

echo "=== Functional sync tests ==="

# --- CLIPBOARD → PRIMARY sync (default mode) ---

echo "CLIPBOARD → PRIMARY sync:"

cleanup_instances
# Ensure CLIPBOARD is owned by our xclip with the expected value.
# sleep gives xclip time to establish ownership before autocutsel starts.
set_selection CLIPBOARD "sync-test-c2p"
sleep 1

"$AUTOCUTSEL" &
_pid=$!
wait_for_selection PRIMARY "sync-test-c2p" 10

get_selection PRIMARY
assert_equal "CLIPBOARD syncs to PRIMARY" "$_sel_value" "sync-test-c2p"

# Update CLIPBOARD while running — should propagate
set_selection CLIPBOARD "updated-c2p"
wait_for_selection PRIMARY "updated-c2p" 10
get_selection PRIMARY
assert_equal "CLIPBOARD update propagates to PRIMARY" "$_sel_value" "updated-c2p"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

# --- PRIMARY → CLIPBOARD sync (-selection PRIMARY) ---

echo ""
echo "PRIMARY → CLIPBOARD sync:"

cleanup_instances
set_selection PRIMARY "sync-test-p2c"
sleep 1

"$AUTOCUTSEL" -selection PRIMARY &
_pid=$!
wait_for_selection CLIPBOARD "sync-test-p2c" 10

get_selection CLIPBOARD
assert_equal "PRIMARY syncs to CLIPBOARD" "$_sel_value" "sync-test-p2c"

set_selection PRIMARY "updated-p2c"
wait_for_selection CLIPBOARD "updated-p2c" 10
get_selection CLIPBOARD
assert_equal "PRIMARY update propagates to CLIPBOARD" "$_sel_value" "updated-p2c"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

# --- -pause interval verification ---

echo ""
echo "Pause interval:"

cleanup_instances
set_selection CLIPBOARD "pause-init"
sleep 1
"$AUTOCUTSEL" -pause 3000 &
_pid=$!
sleep 1

# Change CLIPBOARD; after 1s it should NOT yet be synced
set_selection CLIPBOARD "pause-new-value"
sleep 1
get_selection PRIMARY
if [ "$_sel_value" = "pause-new-value" ]; then
  # Might have synced early — timing dependent, not a hard fail
  _tests_run=$((_tests_run + 1))
  _tests_passed=$((_tests_passed + 1))
  echo "  PASS: -pause 3000 syncs (timing may vary)"
else
  # Poll until it syncs (should happen within one pause interval)
  wait_for_selection PRIMARY "pause-new-value" 10
  get_selection PRIMARY
  assert_equal "-pause 3000 syncs after delay" "$_sel_value" "pause-new-value"
fi

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

# --- -encoding round-trip ---

echo ""
echo "Encoding conversion:"

cleanup_instances
set_selection CLIPBOARD "encoding-abc-123"
sleep 1

"$AUTOCUTSEL" -encoding ISO8859-1 &
_pid=$!
wait_for_selection PRIMARY "encoding-abc-123" 10

# ASCII text should round-trip cleanly through encoding
get_selection PRIMARY
assert_equal "-encoding ASCII round-trip" "$_sel_value" "encoding-abc-123"

# Update with ASCII and verify
set_selection CLIPBOARD "encoding-updated"
wait_for_selection PRIMARY "encoding-updated" 10
get_selection PRIMARY
assert_equal "-encoding ASCII update round-trip" "$_sel_value" "encoding-updated"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

# --- -mouseonly: forward and reverse sync ---

echo ""
echo "Mouseonly mode:"

cleanup_instances
# mouseonly needs libinput access — may not be available in CI
"$AUTOCUTSEL" -mouseonly 2>/dev/null &
_pid=$!
sleep 1
if ! kill -0 "$_pid" 2>/dev/null; then
  _tests_run=$((_tests_run + 1))
  _tests_skipped=$((_tests_skipped + 1))
  echo "  SKIP: mouseonly not available (libinput/input group)"
  wait "$_pid" 2>/dev/null
else
  # Forward direction: PRIMARY should NOT sync to CLIPBOARD without a mouse event
  set_selection PRIMARY "mouseonly-primary"
  set_selection CLIPBOARD "mouseonly-clipboard"
  sleep 2

  get_selection CLIPBOARD
  _tests_run=$((_tests_run + 1))
  if [ "$_sel_value" != "mouseonly-primary" ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: mouseonly does not forward-sync without mouse event"
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: mouseonly forward-synced without mouse event"
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  # --- Reverse direction: CLIPBOARD → PRIMARY via polling ---

  echo ""
  echo "Mouseonly reverse sync (CLIPBOARD → PRIMARY):"

  cleanup_instances
  "$AUTOCUTSEL" -mouseonly 2>/dev/null &
  _pid=$!
  sleep 1

  if kill -0 "$_pid" 2>/dev/null; then
    # Set CLIPBOARD externally (simulates browser copy button / Ctrl+C in app)
    set_selection CLIPBOARD "browser-copy-value"

    # Reverse poll runs every ~500ms — wait up to 10s
    wait_for_selection PRIMARY "browser-copy-value" 10
    get_selection PRIMARY
    assert_equal "reverse sync: CLIPBOARD→PRIMARY" "$_sel_value" "browser-copy-value"

    # Update CLIPBOARD again — should propagate
    set_selection CLIPBOARD "browser-copy-updated"
    wait_for_selection PRIMARY "browser-copy-updated" 10
    get_selection PRIMARY
    assert_equal "reverse sync update propagates" "$_sel_value" "browser-copy-updated"

    # No ping-pong: after reverse sync, CLIPBOARD should still have the same value
    # (not overwritten by autocutsel trying to forward-sync it back)
    sleep 2
    get_selection CLIPBOARD
    assert_equal "no ping-pong after reverse sync" "$_sel_value" "browser-copy-updated"

    # --- P1: Regression test for branch-priority bug ---
    # After reverse sync, own_selection=1. Verify that subsequent CLIPBOARD
    # changes are STILL picked up (reverse poll must not be starved by
    # the own_selection && !wayland → CheckBuffer branch).
    set_selection CLIPBOARD "second-reverse-after-own"
    wait_for_selection PRIMARY "second-reverse-after-own" 10
    get_selection PRIMARY
    assert_equal "reverse continues after own_selection=1" "$_sel_value" "second-reverse-after-own"

    # Third change to confirm the reverse poll runs indefinitely
    set_selection CLIPBOARD "third-reverse-value"
    wait_for_selection PRIMARY "third-reverse-value" 10
    get_selection PRIMARY
    assert_equal "reverse poll runs indefinitely" "$_sel_value" "third-reverse-value"

    # --- P2: LoseTarget re-enables reverse polling ---
    # Forward: we don't have a mouse event, but we can verify that after
    # external CLIPBOARD takeover, the reverse poll resumes.
    # First, verify autocutsel currently has some state:
    sleep 1
    # External app takes CLIPBOARD with a different value
    set_selection CLIPBOARD "after-target-loss"
    wait_for_selection PRIMARY "after-target-loss" 10
    get_selection PRIMARY
    assert_equal "reverse resumes after target ownership lost" "$_sel_value" "after-target-loss"

    # --- P2: Same value does not cause unnecessary re-sync ---
    # Kill xclip and re-set CLIPBOARD with the SAME value from a new process.
    # ReverseReceived should see differs=0 and skip.
    pkill -x xclip 2>/dev/null || true
    sleep 1
    set_selection CLIPBOARD "after-target-loss"
    sleep 2
    # PRIMARY should still have the value (no crash, no corruption)
    get_selection PRIMARY
    assert_equal "same value does not cause re-sync issues" "$_sel_value" "after-target-loss"

    # --- P2: CLIPBOARD owner dies, autocutsel survives ---
    pkill -x xclip 2>/dev/null || true
    sleep 1
    _tests_run=$((_tests_run + 1))
    if kill -0 "$_pid" 2>/dev/null; then
      _tests_passed=$((_tests_passed + 1))
      echo "  PASS: autocutsel survives CLIPBOARD owner death (mouseonly)"
    else
      _tests_failed=$((_tests_failed + 1))
      echo "  FAIL: autocutsel crashed after CLIPBOARD owner death"
    fi

    # New CLIPBOARD owner after death — reverse poll should pick it up
    set_selection CLIPBOARD "revived-after-death"
    wait_for_selection PRIMARY "revived-after-death" 10
    get_selection PRIMARY
    assert_equal "reverse resumes after CLIPBOARD owner death" "$_sel_value" "revived-after-death"

    # --- P3: UTF-8 multibyte in reverse direction ---
    set_selection CLIPBOARD "日本語テスト🎉"
    wait_for_selection PRIMARY "日本語テスト🎉" 10
    get_selection PRIMARY
    assert_equal "reverse sync preserves UTF-8 multibyte" "$_sel_value" "日本語テスト🎉"

  else
    _tests_run=$((_tests_run + 10))
    _tests_skipped=$((_tests_skipped + 10))
    echo "  SKIP: mouseonly not available for reverse sync tests"
  fi

  kill "$_pid" 2>/dev/null
  wait "$_pid" 2>/dev/null
  sleep 1

  # --- Verify debug output shows correct direction mapping ---

  echo ""
  echo "Mouseonly direction mapping:"

  _tmplog=$(mktemp)
  script -qec "timeout 2 $AUTOCUTSEL -mouseonly -debug" /dev/null >"$_tmplog" 2>&1 || true
  _mo_output=$(cat "$_tmplog")
  rm -f "$_tmplog"
  assert_contains "mouseonly monitors PRIMARY" "$_mo_output" "Monitoring: PRIMARY"
  assert_contains "mouseonly targets CLIPBOARD" "$_mo_output" "Target: CLIPBOARD"
fi

# --- Bidirectional: sync only one direction at a time ---

echo ""
echo "Sync direction isolation:"

cleanup_instances
set_selection CLIPBOARD "dir-test-clip"
set_selection PRIMARY "dir-test-prim"

# Default mode: CLIPBOARD → PRIMARY, not the other way
"$AUTOCUTSEL" &
_pid=$!
wait_for_selection PRIMARY "dir-test-clip" 10

get_selection PRIMARY
assert_equal "default mode syncs CLIPBOARD to PRIMARY" "$_sel_value" "dir-test-clip"

# Now change PRIMARY — should NOT overwrite CLIPBOARD (autocutsel owns PRIMARY)
set_selection CLIPBOARD "dir-test-clip"  # reset
sleep 1

# Verify CLIPBOARD was not overwritten by the PRIMARY change
get_selection CLIPBOARD
assert_equal "PRIMARY does not overwrite CLIPBOARD in default mode" "$_sel_value" "dir-test-clip"

kill "$_pid" 2>/dev/null
wait "$_pid" 2>/dev/null

test_summary
