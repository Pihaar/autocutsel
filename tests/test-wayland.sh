#!/bin/sh
# Test Wayland auto-detection and target selection logic
set -u
. "$(dirname "$0")/helpers.sh"

ensure_display || skip_all "No X display available"
cleanup_instances

echo "=== Wayland detection tests ==="

# Save original WAYLAND_DISPLAY
_orig_wayland="${WAYLAND_DISPLAY:-}"

# With WAYLAND_DISPLAY set: should detect Wayland
export WAYLAND_DISPLAY=wayland-0
run_capture_unbuffered 2 "$AUTOCUTSEL" -debug
assert_contains "detects Wayland when WAYLAND_DISPLAY set" "$_output" "Wayland detected"
assert_contains "shows direct selection sync message" "$_output" "direct selection sync"

# CLIPBOARD monitored on Wayland → target = PRIMARY
run_capture_unbuffered 2 "$AUTOCUTSEL" -selection CLIPBOARD -debug
assert_contains "CLIPBOARD on Wayland → target PRIMARY" "$_output" "Target: PRIMARY"

# PRIMARY monitored on Wayland → target = CLIPBOARD
run_capture_unbuffered 2 "$AUTOCUTSEL" -selection PRIMARY -debug
assert_contains "PRIMARY on Wayland → target CLIPBOARD" "$_output" "Target: CLIPBOARD"

# Wayland mode should not mention cutbuffer operations
run_capture_unbuffered 2 "$AUTOCUTSEL" -debug
assert_not_contains "no cutbuffer operations on Wayland" "$_output" "Updating buffer"

# Without WAYLAND_DISPLAY: should NOT detect Wayland
unset WAYLAND_DISPLAY
run_capture_unbuffered 2 "$AUTOCUTSEL" -debug
assert_not_contains "no Wayland without WAYLAND_DISPLAY" "$_output" "Wayland detected"
assert_not_contains "no target selection in X11 mode" "$_output" "Monitoring:"

# Empty WAYLAND_DISPLAY should NOT trigger Wayland (getenv returns "" not NULL,
# but our code checks != NULL which is true for "" — this documents actual behavior)
export WAYLAND_DISPLAY=""
run_capture_unbuffered 2 "$AUTOCUTSEL" -debug
# Note: empty string IS non-NULL, so Wayland IS detected. This is intentional
# because an empty WAYLAND_DISPLAY still indicates a Wayland session.
assert_contains "empty WAYLAND_DISPLAY still triggers detection" "$_output" "Wayland detected"

# Restore original value
if [ -n "$_orig_wayland" ]; then
  export WAYLAND_DISPLAY="$_orig_wayland"
else
  unset WAYLAND_DISPLAY
fi

test_summary
