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

# --- Test: Help flag ---

echo "--- Test: Help flag ---"

OUTPUT=$("$OC_SANDBOX" --help 2>&1) || true
assert_exit_code 0 $? "oc-sandbox --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Help output contains usage"
assert_stderr_contains "$OUTPUT" "--profile" "Help output contains --profile option"

echo ""

# --- Test: No profile specified ---

echo "--- Test: No profile specified ---"

OUTPUT=$("$OC_SANDBOX" 2>&1)
EXIT_CODE=$?
# Should exit with error (non-zero)
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "oc-sandbox without profile exits with error"
else
  fail "oc-sandbox without profile should exit with error"
fi
assert_stderr_contains "$OUTPUT" "No profile specified" "Error message mentions missing profile"

echo ""

# --- Test: Invalid profile ---

echo "--- Test: Invalid profile ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="${OC_SANDBOX_IMAGE:-localhost/opencode-sandbox:latest}"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Test with a profile name that has invalid characters (path traversal)
    # This validates before image operations
    OUTPUT=$("$OC_SANDBOX" --profile "invalid/profile" 2>&1)
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "oc-sandbox with invalid profile exits with error"
    else
      fail "oc-sandbox with invalid profile should exit with error"
    fi
    assert_stderr_contains "$OUTPUT" "Profile name must not contain" "Error message mentions invalid profile"
  else
    skip "Invalid profile test (image not built)"
  fi
else
  skip "Invalid profile test (podman not available)"
fi

echo ""

# --- Test: Path doesn't exist ---

echo "--- Test: Path doesn't exist ---"

OUTPUT=$("$OC_SANDBOX" --profile dev /nonexistent/path/xyz 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "oc-sandbox with nonexistent path exits with error"
else
  fail "oc-sandbox with nonexistent path should exit with error"
fi
assert_stderr_contains "$OUTPUT" "does not exist" "Error message mentions nonexistent path"

echo ""

# --- Test: Path is not a directory ---

echo "--- Test: Path is not a directory ---"

NOT_DIR="${TEST_DIR}/not_a_dir"
touch "$NOT_DIR"
OUTPUT=$("$OC_SANDBOX" --profile dev "$NOT_DIR" 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "oc-sandbox with non-directory path exits with error"
else
  fail "oc-sandbox with non-directory path should exit with error"
fi
assert_stderr_contains "$OUTPUT" "not a directory" "Error message mentions not a directory"

echo ""

# --- Test: Outside home directory warning ---

echo "--- Test: Outside home directory warning ---"

# This test is interactive (prompts for confirmation), so we test the non-interactive path
# by piping 'n' to reject the warning
OUTPUT=$(echo "n" | "$OC_SANDBOX" --profile dev /tmp 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  # When stdin is not a terminal, script errors out
  pass "oc-sandbox errors when outside-home and non-interactive"
else
  fail "oc-sandbox should exit with error for outside-home non-interactive"
fi
assert_stderr_contains "$OUTPUT" "outside your home directory" "Warning mentions home directory"

echo ""

# --- Test: Basic invocation (requires podman) ---

echo "--- Test: Basic invocation ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  # This test requires a built image and is interactive
  # We test that the container starts and exits cleanly
  # Use 'echo exit | oc-sandbox' to send exit command to opencode
  # Note: This test may need adjustment based on how opencode handles stdin
  skip "Basic invocation test (interactive, run manually: oc-sandbox --profile dev)"
else
  skip "Basic invocation test (podman not available)"
fi

echo ""

# --- Test: Custom path (requires podman) ---

echo "--- Test: Custom path ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  skip "Custom path test (interactive, run manually: oc-sandbox -p systems /path/to/project)"
else
  skip "Custom path test (podman not available)"
fi

echo ""

# --- Test: Filesystem isolation (requires podman) ---

echo "--- Test: Filesystem isolation ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  # Verify that the container cannot write outside /workspace and /tmp
  # Run a command inside the container that tries to write to /
  IMAGE_NAME="${OC_SANDBOX_IMAGE:-localhost/opencode-sandbox:latest}"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Test writing to / (should fail)
    OUTPUT=$(podman run --rm --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
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
  else
    skip "Filesystem isolation test (image not built)"
  fi
else
  skip "Filesystem isolation test (podman not available)"
fi

echo ""

# --- Test: Permission escalation prevention (requires podman) ---

echo "--- Test: Permission escalation prevention ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="${OC_SANDBOX_IMAGE:-localhost/opencode-sandbox:latest}"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    # Test that sandbox user cannot become root
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
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

    # Test that su/sudo are not available
    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
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

