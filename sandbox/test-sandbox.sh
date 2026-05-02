#!/usr/bin/env bash
set -uo pipefail

# Integration test script for oc-sandbox
# Covers the test scenarios from the design spec

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OC_SANDBOX="${SCRIPT_DIR}/oc-sandbox"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  ((TESTS_PASSED++))
}

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  ((TESTS_FAILED++))
}

skip() {
  echo -e "${YELLOW}SKIP${NC}: $1"
  ((TESTS_SKIPPED++))
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [ "$actual" -eq "$expected" ]; then
    pass "$description"
  else
    fail "$description (expected exit code $expected, got $actual)"
  fi
}

assert_stderr_contains() {
  local output="$1"
  local pattern="$2"
  local description="$3"
  if printf '%s' "$output" | grep -q -- "$pattern"; then
    pass "$description"
  else
    fail "$description (expected pattern: '$pattern'): $output"
  fi
}

# --- Pre-flight checks ---

echo "=== oc-sandbox integration tests ==="
echo ""

# Check if podman is available
PODMAN_AVAILABLE="false"
if command -v podman &>/dev/null; then
  PODMAN_AVAILABLE="true"
fi

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Test directory: $TEST_DIR"
echo ""

# --- Test 1: Help display (no args) ---

echo "--- Test 1: Help display (no args) ---"

OUTPUT=$("$OC_SANDBOX" 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "oc-sandbox with no args exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Help output contains usage"
assert_stderr_contains "$OUTPUT" "build" "Help output mentions build command"
assert_stderr_contains "$OUTPUT" "run" "Help output mentions run command"

echo ""

# --- Test 2: Main help flag ---

echo "--- Test 2: Main help flag ---"

OUTPUT=$("$OC_SANDBOX" --help 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "oc-sandbox --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Main --help contains usage"

echo ""

# --- Test 3: Build help flag ---

echo "--- Test 3: Build help flag ---"

OUTPUT=$("$OC_SANDBOX" build --help 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "oc-sandbox build --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Build --help contains usage"
assert_stderr_contains "$OUTPUT" "--tag" "Build --help mentions --tag"
assert_stderr_contains "$OUTPUT" "--force" "Build --help mentions --force"

echo ""

# --- Test 4: Run help flag ---

echo "--- Test 4: Run help flag ---"

OUTPUT=$("$OC_SANDBOX" run --help 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "oc-sandbox run --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Run --help contains usage"
assert_stderr_contains "$OUTPUT" "--tag" "Run --help mentions --tag"
assert_stderr_contains "$OUTPUT" "--profile" "Run --help mentions --profile"

echo ""

# --- Test 5: Unknown command ---

echo "--- Test 5: Unknown command ---"

OUTPUT=$("$OC_SANDBOX" unknown 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "oc-sandbox with unknown command exits with error"
else
  fail "oc-sandbox with unknown command should exit with error"
fi
assert_stderr_contains "$OUTPUT" "Unknown command" "Error mentions unknown command"

echo ""

# --- Test 6: Run without image (requires podman) ---

echo "--- Test 6: Run without image ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  # Use a tag that is unlikely to exist
  OUTPUT=$("$OC_SANDBOX" run --tag nonexistent-tag-12345 2>&1)
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -ne 0 ]; then
    pass "oc-sandbox run without image exits with error"
  else
    fail "oc-sandbox run without image should exit with error"
  fi
  assert_stderr_contains "$OUTPUT" "not found" "Error mentions image not found"
  assert_stderr_contains "$OUTPUT" "oc-sandbox build" "Error suggests running build"
else
  skip "Run without image (podman not available)"
fi

echo ""

# --- Test 7: Build command (requires podman) ---

echo "--- Test 7: Build command ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  # Force rebuild to ensure it works
  OUTPUT=$("$OC_SANDBOX" build --force 2>&1)
  EXIT_CODE=$?
  assert_exit_code 0 "$EXIT_CODE" "oc-sandbox build --force exits with 0"
  assert_stderr_contains "$OUTPUT" "built successfully" "Build output mentions success"
else
  skip "Build command (podman not available)"
fi

echo ""

# --- Test 8: Build skip if exists (requires podman) ---

echo "--- Test 8: Build skip if exists ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  # After the force build above, a plain build should skip
  OUTPUT=$("$OC_SANDBOX" build 2>&1)
  EXIT_CODE=$?
  assert_exit_code 0 "$EXIT_CODE" "oc-sandbox build without --force exits with 0 when image exists"
  assert_stderr_contains "$OUTPUT" "already exists" "Build skip mentions image already exists"
else
  skip "Build skip if exists (podman not available)"
fi

echo ""

# --- Test 9: Build with custom tag (requires podman) ---

echo "--- Test 9: Build with custom tag ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  OUTPUT=$("$OC_SANDBOX" build --tag test-integration --force 2>&1)
  EXIT_CODE=$?
  assert_exit_code 0 "$EXIT_CODE" "oc-sandbox build --tag test-integration exits with 0"
  assert_stderr_contains "$OUTPUT" "localhost/opencode-sandbox:test-integration" "Build output mentions custom tag"
else
  skip "Build with custom tag (podman not available)"
fi

echo ""
# --- Test 10: Run with invalid profile (path traversal) ---

echo "--- Test 10: Run with invalid profile (path traversal) ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    OUTPUT=$("$OC_SANDBOX" run --profile "invalid/profile" 2>&1)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "oc-sandbox run with invalid profile exits with error"
    else
      fail "oc-sandbox run with invalid profile should exit with error"
    fi
    assert_stderr_contains "$OUTPUT" "Profile name must not contain" "Error mentions invalid profile characters"
  else
    skip "Invalid profile test (image not built)"
  fi
else
  skip "Invalid profile test (podman not available)"
fi

echo ""

# --- Test 11: Run with nonexistent path ---

echo "--- Test 11: Run with nonexistent path ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    OUTPUT=$("$OC_SANDBOX" run /nonexistent/path/xyz 2>&1)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "oc-sandbox run with nonexistent path exits with error"
    else
      fail "oc-sandbox run with nonexistent path should exit with error"
    fi
    assert_stderr_contains "$OUTPUT" "does not exist" "Error message mentions nonexistent path"
  else
    skip "Nonexistent path test (image not built)"
  fi
else
  skip "Nonexistent path test (podman not available)"
fi

echo ""

# --- Test 12: Run with non-directory path ---

echo "--- Test 12: Run with non-directory path ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    NOT_DIR="${TEST_DIR}/not_a_dir"
    touch "$NOT_DIR"
    OUTPUT=$("$OC_SANDBOX" run "$NOT_DIR" 2>&1)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "oc-sandbox run with non-directory path exits with error"
    else
      fail "oc-sandbox run with non-directory path should exit with error"
    fi
    assert_stderr_contains "$OUTPUT" "not a directory" "Error message mentions not a directory"
  else
    skip "Non-directory path test (image not built)"
  fi
else
  skip "Non-directory path test (podman not available)"
fi

echo ""

# --- Test 13: Outside home directory warning (non-interactive) ---

echo "--- Test 13: Outside home directory warning (non-interactive) ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Pipe 'n' to simulate non-interactive stdin rejecting the prompt
    OUTPUT=$(echo "n" | "$OC_SANDBOX" run /tmp 2>&1)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "oc-sandbox run errors when outside-home and non-interactive"
    else
      fail "oc-sandbox run should exit with error for outside-home non-interactive"
    fi
    assert_stderr_contains "$OUTPUT" "outside your home directory" "Warning mentions home directory"
  else
    skip "Outside home directory test (image not built)"
  fi
else
  skip "Outside home directory test (podman not available)"
fi

echo ""

# --- Test 14: Filesystem isolation (requires podman) ---

echo "--- Test 14: Filesystem isolation ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Test writing to / (should fail)
    OUTPUT=$(podman run --rm --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "touch /test_write 2>&1; echo exit_code=\$?") || true

    if printf '%s' "$OUTPUT" | grep -q "exit_code=1\|Permission denied\|Read-only file system"; then
      pass "Container cannot write to / (read-only filesystem)"
    else
      fail "Container should not be able to write to /"
    fi

    # Test writing to /workspace (should succeed)
    OUTPUT=$(podman run --rm --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "touch /workspace/test_write && echo success || echo failure") || true

    if printf '%s' "$OUTPUT" | grep -q "success"; then
      pass "Container can write to /workspace"
    else
      fail "Container should be able to write to /workspace"
    fi

    # Test writing to /tmp (should succeed)
    OUTPUT=$(podman run --rm --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "touch /tmp/test_write && echo success || echo failure") || true

    if printf '%s' "$OUTPUT" | grep -q "success"; then
      pass "Container can write to /tmp"
    else
      fail "Container should be able to write to /tmp"
    fi

    # Test writing to /home/sandbox (should succeed)
    OUTPUT=$(podman run --rm --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "touch /home/sandbox/test_write && echo success || echo failure") || true

    if printf '%s' "$OUTPUT" | grep -q "success"; then
      pass "Container can write to /home/sandbox"
    else
      fail "Container should be able to write to /home/sandbox"
    fi
  else
    skip "Filesystem isolation test (image not built)"
  fi
else
  skip "Filesystem isolation test (podman not available)"
fi

echo ""

# --- Test 15: Permission escalation prevention (requires podman) ---

echo "--- Test 15: Permission escalation prevention ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Test that container runs as sandbox user
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "whoami") || true

    if printf '%s' "$OUTPUT" | grep -q "sandbox"; then
      pass "Container runs as sandbox user (not root)"
    else
      fail "Container should run as sandbox user, got: $OUTPUT"
    fi

    # Test that sudo is not available
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "which sudo 2>/dev/null && echo 'sudo found' || echo 'sudo not found'") || true

    if printf '%s' "$OUTPUT" | grep -q "sudo not found"; then
      pass "sudo is not available in the container"
    else
      fail "sudo should not be available in the container"
    fi
  else
    skip "Permission escalation test (image not built)"
  fi
else
  skip "Permission escalation test (podman not available)"
fi

echo ""

# --- Test 16: Persistent home directory (requires podman) ---

echo "--- Test 16: Persistent home directory ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    VOLUME_NAME="opencode-sandbox-home-main"

    # Write a marker file into the home volume
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "${VOLUME_NAME}:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "echo marker123 > /home/sandbox/.test_marker && echo written") || true

    if printf '%s' "$OUTPUT" | grep -q "written"; then
      pass "Marker file written to persistent home"
    else
      fail "Failed to write marker file to persistent home: $OUTPUT"
    fi

    # Run a second container and verify the marker persists
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "${VOLUME_NAME}:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      "$IMAGE_NAME" \
      bash -c "cat /home/sandbox/.test_marker 2>/dev/null || echo 'not found'") || true

    if printf '%s' "$OUTPUT" | grep -q "marker123"; then
      pass "Marker file persists across container runs"
    else
      fail "Marker file should persist across container runs, got: $OUTPUT"
    fi
  else
    skip "Persistent home test (image not built)"
  fi
else
  skip "Persistent home test (podman not available)"
fi

echo ""

# --- Summary ---

echo "=== Test Summary ==="
echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed (or skipped).${NC}"
  exit 0
fi
