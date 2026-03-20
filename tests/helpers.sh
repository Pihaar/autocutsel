#!/bin/sh
# Common test helpers for autocutsel test suite
# Exit codes: 0 = pass, 1 = fail, 77 = skip (autotools convention)

PASS=0
FAIL=1
SKIP=77

# Counters
_tests_run=0
_tests_passed=0
_tests_failed=0
_tests_skipped=0

AUTOCUTSEL="${AUTOCUTSEL:-../autocutsel}"
CUTSEL="${CUTSEL:-../cutsel}"

# Ensure X display is available (start Xvfb if needed)
ensure_display() {
  if [ -n "$DISPLAY" ]; then
    return 0
  fi
  if command -v Xvfb >/dev/null 2>&1; then
    Xvfb :99 -screen 0 640x480x8 -nolisten tcp &
    XVFB_PID=$!
    export DISPLAY=:99
    # Wait for Xvfb to be ready
    sleep 1
    if kill -0 "$XVFB_PID" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

XVFB_PID=""

cleanup_display() {
  if [ -n "$XVFB_PID" ]; then
    kill "$XVFB_PID" 2>/dev/null
    wait "$XVFB_PID" 2>/dev/null
    XVFB_PID=""
  fi
}

# Run a command with a timeout, capture combined output
# Usage: run_capture SECONDS command [args...]
# Sets: _output, _exit_code
run_capture() {
  _timeout=$1
  shift
  _output=$(timeout "$_timeout" "$@" 2>&1)
  _exit_code=$?
  # timeout returns 124 on timeout
  if [ "$_exit_code" -eq 124 ]; then
    _exit_code=0  # timeout is expected for daemons
  fi
}

# Like run_capture but with unbuffered stdout (for Xt programs)
run_capture_unbuffered() {
  _timeout=$1
  shift
  if command -v script >/dev/null 2>&1; then
    _output=$(script -qec "timeout $_timeout $*" /dev/null 2>&1)
  else
    _output=$(timeout "$_timeout" "$@" 2>&1)
  fi
  _exit_code=$?
  if [ "$_exit_code" -eq 124 ]; then
    _exit_code=0
  fi
}

# Assert output contains string
# Usage: assert_contains "description" "$output" "expected substring"
assert_contains() {
  _tests_run=$((_tests_run + 1))
  _desc=$1
  _haystack=$2
  _needle=$3
  if echo "$_haystack" | grep -qF "$_needle"; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_desc"
    return 0
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_desc"
    echo "    expected to contain: $_needle"
    echo "    got: $(echo "$_haystack" | head -3)"
    return 1
  fi
}

# Assert output does NOT contain string
assert_not_contains() {
  _tests_run=$((_tests_run + 1))
  _desc=$1
  _haystack=$2
  _needle=$3
  if echo "$_haystack" | grep -qF "$_needle"; then
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_desc"
    echo "    should not contain: $_needle"
    return 1
  else
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_desc"
    return 0
  fi
}

# Assert exit code equals expected
assert_exit() {
  _tests_run=$((_tests_run + 1))
  _desc=$1
  _actual=$2
  _expected=$3
  if [ "$_actual" -eq "$_expected" ]; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_desc"
    return 0
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_desc (exit=$_actual, expected=$_expected)"
    return 1
  fi
}

# Assert a process is running
assert_running() {
  _tests_run=$((_tests_run + 1))
  _desc=$1
  _pid=$2
  if kill -0 "$_pid" 2>/dev/null; then
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_desc"
    return 0
  else
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_desc (PID $_pid not running)"
    return 1
  fi
}

# Assert a process is NOT running
assert_not_running() {
  _tests_run=$((_tests_run + 1))
  _desc=$1
  _pid=$2
  if kill -0 "$_pid" 2>/dev/null; then
    _tests_failed=$((_tests_failed + 1))
    echo "  FAIL: $_desc (PID $_pid still running)"
    return 1
  else
    _tests_passed=$((_tests_passed + 1))
    echo "  PASS: $_desc"
    return 0
  fi
}

# Kill any running autocutsel/cutsel instances (but not the test scripts)
cleanup_instances() {
  # Only kill actual autocutsel/cutsel binaries, not shell scripts
  pkill -x "autocutsel" 2>/dev/null || true
  pkill -x "cutsel" 2>/dev/null || true
  sleep 1
}

# Print summary and return appropriate exit code
test_summary() {
  echo ""
  echo "Results: $_tests_passed/$_tests_run passed, $_tests_failed failed, $_tests_skipped skipped"
  cleanup_display
  if [ "$_tests_failed" -gt 0 ]; then
    return $FAIL
  fi
  return $PASS
}

# Skip the entire test file with a reason
skip_all() {
  echo "SKIP: $1"
  cleanup_display
  exit $SKIP
}
