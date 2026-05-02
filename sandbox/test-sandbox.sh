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

# Helper: run a command with a timeout, capturing stdout and stderr
# Returns the command's exit code if it exits before timeout, or 124 if killed by timeout
run_with_timeout() {
  local timeout_secs="$1"
  shift
  python3 -c "
import sys, subprocess, signal, time
timeout = int(sys.argv[1])
args = sys.argv[2:]
proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
time.sleep(timeout)
if proc.poll() is not None:
    sys.stdout.buffer.write(proc.stdout.read())
    sys.exit(proc.returncode)
proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=2)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
sys.stdout.buffer.write(proc.stdout.read())
rc = proc.returncode
if rc < 0:
    rc = 124
sys.exit(rc)
" "$timeout_secs" "$@"
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
assert_stderr_contains "$OUTPUT" "install" "Help output mentions install command"
assert_stderr_contains "$OUTPUT" "uninstall" "Help output mentions uninstall command"

echo ""

# --- Test 2: Main help flag ---

echo "--- Test 2: Main help flag ---"

OUTPUT=$("$OC_SANDBOX" --help 2>&1)
exit_code=$?
assert_exit_code 0 $exit_code "oc-sandbox --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Main --help contains usage"
assert_stderr_contains "$OUTPUT" "install" "Main --help mentions install"
assert_stderr_contains "$OUTPUT" "uninstall" "Main --help mentions uninstall"

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

# --- Test 17: GitHub SSH known_hosts ---

echo "--- Test 17: GitHub SSH known_hosts ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
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
      bash -c "grep github.com /home/sandbox/.ssh/known_hosts 2>/dev/null || echo 'not found'") || true

    if printf '%s' "$OUTPUT" | grep -q "github.com"; then
      pass "GitHub host keys present in known_hosts"
    else
      fail "GitHub host keys not found in known_hosts: $OUTPUT"
    fi
  else
    skip "GitHub SSH known_hosts test (image not built)"
  fi
else
  skip "GitHub SSH known_hosts test (podman not available)"
fi

echo ""

# --- Test 18: SSH key mount ---

echo "--- Test 18: SSH key mount ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_18"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key-data" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"

    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.ssh/id_rsa",dst=/home/sandbox/.ssh/id_rsa,ro,readonly,relabel=private \
      "$IMAGE_NAME" \
      bash -c "cat /home/sandbox/.ssh/id_rsa 2>/dev/null || echo 'not found'") || true

    if printf '%s' "$OUTPUT" | grep -q "fake-ssh-key-data"; then
      pass "SSH key is readable inside container"
    else
      fail "SSH key not readable inside container: $OUTPUT"
    fi
  else
    skip "SSH key mount test (image not built)"
  fi
else
  skip "SSH key mount test (podman not available)"
fi

echo ""

# --- Test 19: SSH key read-only ---

echo "--- Test 19: SSH key read-only ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_19"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key-data" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"

    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.ssh/id_rsa",dst=/home/sandbox/.ssh/id_rsa,ro,readonly,relabel=private \
      "$IMAGE_NAME" \
      bash -c "echo modified > /home/sandbox/.ssh/id_rsa 2>&1; echo exit_code=\$?") || true

    if printf '%s' "$OUTPUT" | grep -q "exit_code=1\|Permission denied\|Read-only file system"; then
      pass "Container cannot modify mounted SSH key"
    else
      fail "Container should not be able to modify mounted SSH key: $OUTPUT"
    fi
  else
    skip "SSH key read-only test (image not built)"
  fi
else
  skip "SSH key read-only test (podman not available)"
fi

echo ""

# --- Test 20: SSH public key mount ---

echo "--- Test 20: SSH public key mount ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_20"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key-data" > "${TEMP_HOME}/.ssh/id_rsa"
    echo "fake-ssh-pub-key-data" > "${TEMP_HOME}/.ssh/id_rsa.pub"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"

    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.ssh/id_rsa",dst=/home/sandbox/.ssh/id_rsa,ro,readonly,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.ssh/id_rsa.pub",dst=/home/sandbox/.ssh/id_rsa.pub,ro,readonly,relabel=private \
      "$IMAGE_NAME" \
      bash -c "cat /home/sandbox/.ssh/id_rsa.pub 2>/dev/null || echo 'not found'") || true

    if printf '%s' "$OUTPUT" | grep -q "fake-ssh-pub-key-data"; then
      pass "SSH public key is readable inside container"
    else
      fail "SSH public key not readable inside container: $OUTPUT"
    fi
  else
    skip "SSH public key mount test (image not built)"
  fi
else
  skip "SSH public key mount test (podman not available)"
fi

echo ""

# --- Test 21: Auth.json mount ---

echo "--- Test 21: Auth.json mount ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_21"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.local/share/opencode/auth.json",dst=/home/sandbox/.local/share/opencode/auth.json,ro,readonly,relabel=private \
      "$IMAGE_NAME" \
      bash -c "cat /home/sandbox/.local/share/opencode/auth.json 2>/dev/null || echo 'not found'") || true

    if printf '%s' "$OUTPUT" | grep -q '"providers"'; then
      pass "Auth.json is readable inside container"
    else
      fail "Auth.json not readable inside container: $OUTPUT"
    fi
  else
    skip "Auth.json mount test (image not built)"
  fi
else
  skip "Auth.json mount test (podman not available)"
fi

echo ""

# --- Test 22: Auth.json read-only ---

echo "--- Test 22: Auth.json read-only ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_22"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(podman run --rm \
      --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,size=100m \
      --volume "opencode-sandbox-home-main:/home/sandbox" \
      --user sandbox \
      --cap-drop ALL \
      --cap-add CHOWN \
      --security-opt no-new-privileges:true \
      --mount type=bind,src="${TEST_DIR}",dst=/workspace,relabel=private \
      --mount type=bind,src="${TEMP_HOME}/.local/share/opencode/auth.json",dst=/home/sandbox/.local/share/opencode/auth.json,ro,readonly,relabel=private \
      "$IMAGE_NAME" \
      bash -c "echo modified > /home/sandbox/.local/share/opencode/auth.json 2>&1; echo exit_code=\$?") || true

    if printf '%s' "$OUTPUT" | grep -q "exit_code=1\|Permission denied\|Read-only file system"; then
      pass "Container cannot modify mounted auth.json"
    else
      fail "Container should not be able to modify mounted auth.json: $OUTPUT"
    fi
  else
    skip "Auth.json read-only test (image not built)"
  fi
else
  skip "Auth.json read-only test (podman not available)"
fi

echo ""

# --- Test 23: Missing SSH key warning ---

echo "--- Test 23: Missing SSH key warning ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_23"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "SSH key not found" "Missing SSH key produces warning"
  else
    skip "Missing SSH key warning test (image not built)"
  fi
else
  skip "Missing SSH key warning test (podman not available)"
fi

echo ""

# --- Test 24: Missing auth.json warning ---

echo "--- Test 24: Missing auth.json warning ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_24"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "auth.json not found" "Missing auth.json produces warning"
  else
    skip "Missing auth.json warning test (image not built)"
  fi
else
  skip "Missing auth.json warning test (podman not available)"
fi

echo ""

# --- Test 25: --no-ssh flag ---

echo "--- Test 25: --no-ssh flag ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_25"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run --no-ssh "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "Skipping SSH key mount" "--no-ssh flag skips SSH key mount"
  else
    skip "--no-ssh flag test (image not built)"
  fi
else
  skip "--no-ssh flag test (podman not available)"
fi

echo ""

# --- Test 26: --no-auth flag ---

echo "--- Test 26: --no-auth flag ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_26"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 600 "${TEMP_HOME}/.ssh/id_rsa"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run --no-auth "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "Skipping auth.json mount" "--no-auth flag skips auth.json mount"
  else
    skip "--no-auth flag test (image not built)"
  fi
else
  skip "--no-auth flag test (podman not available)"
fi

echo ""

# --- Test 27: Permissive SSH key warning ---

echo "--- Test 27: Permissive SSH key warning ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_27"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 644 "${TEMP_HOME}/.ssh/id_rsa"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "overly permissive permissions" "Permissive SSH key produces warning"
  else
    skip "Permissive SSH key warning test (image not built)"
  fi
else
  skip "Permissive SSH key warning test (podman not available)"
fi

echo ""

# --- Test 28: Unreadable SSH key error ---

echo "--- Test 28: Unreadable SSH key error ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_28"
    mkdir -p "${TEMP_HOME}/workspace"
    mkdir -p "${TEMP_HOME}/.ssh"
    echo "fake-ssh-key" > "${TEMP_HOME}/.ssh/id_rsa"
    chmod 000 "${TEMP_HOME}/.ssh/id_rsa"
    mkdir -p "${TEMP_HOME}/.local/share/opencode"
    echo '{"providers":{"test":"key"}}' > "${TEMP_HOME}/.local/share/opencode/auth.json"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run "$TEMP_HOME/workspace" 2>&1)
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -ne 0 ]; then
      pass "Unreadable SSH key causes non-zero exit"
    else
      fail "Unreadable SSH key should cause non-zero exit, got $EXIT_CODE"
    fi
    assert_stderr_contains "$OUTPUT" "Cannot read SSH key" "Unreadable SSH key produces error message"
  else
    skip "Unreadable SSH key error test (image not built)"
  fi
else
  skip "Unreadable SSH key error test (podman not available)"
fi

echo ""

# --- Test 29: Plugin warmup ---

echo "--- Test 29: Plugin warmup ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
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
      bash -c "test -d /home/sandbox/.config/opencode/node_modules && echo 'warmup_done' || echo 'no_warmup'") || true

    if printf '%s' "$OUTPUT" | grep -q "warmup_done"; then
      pass "Plugin warmup created opencode files in home directory"
    else
      fail "Plugin warmup did not create opencode files: $OUTPUT"
    fi
  else
    skip "Plugin warmup test (image not built)"
  fi
else
  skip "Plugin warmup test (podman not available)"
fi

echo ""

# --- Test 30: Git SSH clone ---

echo "--- Test 30: Git SSH clone ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
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
      bash -c "if ! command -v git >/dev/null 2>&1 || ! command -v ssh >/dev/null 2>&1; then echo 'missing_tools'; exit 1; fi; GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=yes' git clone git@github.com:some/nonexistent-repo-12345.git /tmp/test_clone 2>&1 || true") || true

    if printf '%s' "$OUTPUT" | grep -q "missing_tools"; then
      fail "Git or SSH not available in container"
    elif printf '%s' "$OUTPUT" | grep -q "Host key verification failed"; then
      fail "Git SSH clone failed with host key verification: $OUTPUT"
    else
      pass "Git SSH clone works without host key prompt"
    fi
  else
    skip "Git SSH clone test (image not built)"
  fi
else
  skip "Git SSH clone test (podman not available)"
fi

echo ""

# --- Test 31: Symlink resolution ---

echo "--- Test 31: Symlink resolution ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  SYMLINK_DIR="${TEST_DIR}/symlink_test"
  mkdir -p "$SYMLINK_DIR"
  ln -s "$OC_SANDBOX" "${SYMLINK_DIR}/oc-sandbox"

  OUTPUT=$("${SYMLINK_DIR}/oc-sandbox" build --help 2>&1)
  EXIT_CODE=$?
  assert_exit_code 0 "$EXIT_CODE" "Symlinked oc-sandbox build --help exits with 0"
  assert_stderr_contains "$OUTPUT" "Usage:" "Symlinked build --help shows usage"
  assert_stderr_contains "$OUTPUT" "--tag" "Symlinked build --help mentions --tag"

  # Verify that SCRIPT_DIR resolves correctly by checking build can find Containerfile
  # We do this indirectly: the real script is in a directory with Containerfile,
  # so if SCRIPT_DIR resolved to the symlink dir, build --help would still work
  # but a real build would fail. We test the real build via symlink in Test 32.
  pass "Symlink resolution: build --help works through symlink"
else
  skip "Symlink resolution (podman not available)"
fi

echo ""

# --- Test 32: Build through symlink (requires podman) ---

echo "--- Test 32: Build through symlink ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  SYMLINK_BUILD_DIR="${TEST_DIR}/symlink_build"
  mkdir -p "$SYMLINK_BUILD_DIR"
  ln -s "$OC_SANDBOX" "${SYMLINK_BUILD_DIR}/oc-sandbox"

  # Use a unique tag so we don't interfere with other tests
  OUTPUT=$("${SYMLINK_BUILD_DIR}/oc-sandbox" build --tag symlink-test --force 2>&1)
  EXIT_CODE=$?
  assert_exit_code 0 "$EXIT_CODE" "Build through symlink exits with 0"
  assert_stderr_contains "$OUTPUT" "built successfully" "Build through symlink reports success"
else
  skip "Build through symlink (podman not available)"
fi

echo ""

# --- Test 33: Install help ---

echo "--- Test 33: Install help ---"

OUTPUT=$("$OC_SANDBOX" install --help 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "oc-sandbox install --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Install help contains usage"
assert_stderr_contains "$OUTPUT" "install" "Install help mentions install"

echo ""

# --- Test 34: Install command (dry-run via temp HOME) ---

echo "--- Test 34: Install command ---"

TEMP_HOME="${TEST_DIR}/temp_home_install"
mkdir -p "${TEMP_HOME}/.local/bin"

# Run install with a fake HOME so we don't pollute the real one
OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" install 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Install command exits with 0"

# Verify symlink was created
if [ -L "${TEMP_HOME}/.local/bin/oc-sandbox" ]; then
  pass "Install creates symlink at ~/.local/bin/oc-sandbox"
else
  fail "Install did not create symlink at ~/.local/bin/oc-sandbox"
fi

# Verify symlink points to the real script
SYMLINK_TARGET=$(readlink "${TEMP_HOME}/.local/bin/oc-sandbox")
if [ "$SYMLINK_TARGET" = "$OC_SANDBOX" ]; then
  pass "Install symlink points to correct target"
else
  fail "Install symlink points to wrong target: $SYMLINK_TARGET (expected $OC_SANDBOX)"
fi

assert_stderr_contains "$OUTPUT" "Installed" "Install output mentions success"

echo ""

# --- Test 35: Install idempotency ---

echo "--- Test 35: Install idempotency ---"

TEMP_HOME="${TEST_DIR}/temp_home_idempotency"
mkdir -p "${TEMP_HOME}/.local/bin"

# First install
HOME="$TEMP_HOME" "$OC_SANDBOX" install >/dev/null 2>&1

# Second install should report already installed
OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" install 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Re-install exits with 0"
assert_stderr_contains "$OUTPUT" "Already installed" "Re-install reports already installed"

echo ""

# --- Test 36: Install refuses to overwrite regular file ---

echo "--- Test 36: Install refuses regular file ---"

TEMP_HOME="${TEST_DIR}/temp_home_regular"
mkdir -p "${TEMP_HOME}/.local/bin"
echo "not a symlink" > "${TEMP_HOME}/.local/bin/oc-sandbox"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" install 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Install refuses to overwrite regular file (non-zero exit)"
else
  fail "Install should refuse to overwrite regular file"
fi
assert_stderr_contains "$OUTPUT" "Refusing to overwrite" "Install warns about regular file"

echo ""

# --- Test 37: Install updates different symlink ---

echo "--- Test 37: Install updates different symlink ---"

TEMP_HOME="${TEST_DIR}/temp_home_update"
mkdir -p "${TEMP_HOME}/.local/bin"
ln -s /some/other/path "${TEMP_HOME}/.local/bin/oc-sandbox"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" install 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Install updates different symlink exits with 0"
assert_stderr_contains "$OUTPUT" "Updated" "Install reports updated symlink"

# Verify it now points to us
SYMLINK_TARGET=$(readlink "${TEMP_HOME}/.local/bin/oc-sandbox")
if [ "$SYMLINK_TARGET" = "$OC_SANDBOX" ]; then
  pass "Updated symlink points to correct target"
else
  fail "Updated symlink points to wrong target: $SYMLINK_TARGET"
fi

echo ""

# --- Test 38: Install offers to create ~/.local/bin ---

echo "--- Test 38: Install creates ~/.local/bin ---"

TEMP_HOME="${TEST_DIR}/temp_home_nobin"
mkdir -p "$TEMP_HOME"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" install 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Install with missing ~/.local/bin exits with 0"

if [ -d "${TEMP_HOME}/.local/bin" ] && [ -L "${TEMP_HOME}/.local/bin/oc-sandbox" ]; then
  pass "Install creates ~/.local/bin and symlink when missing"
else
  fail "Install did not create ~/.local/bin or symlink"
fi

echo ""

# --- Test 39: Uninstall help ---

echo "--- Test 39: Uninstall help ---"

OUTPUT=$("$OC_SANDBOX" uninstall --help 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "oc-sandbox uninstall --help exits with 0"
assert_stderr_contains "$OUTPUT" "Usage:" "Uninstall help contains usage"
assert_stderr_contains "$OUTPUT" "uninstall" "Uninstall help mentions uninstall"

echo ""

# --- Test 40: Uninstall command ---

echo "--- Test 40: Uninstall command ---"

TEMP_HOME="${TEST_DIR}/temp_home_uninstall"
mkdir -p "${TEMP_HOME}/.local/bin"
ln -s "$OC_SANDBOX" "${TEMP_HOME}/.local/bin/oc-sandbox"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" uninstall 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Uninstall command exits with 0"
assert_stderr_contains "$OUTPUT" "Uninstalled" "Uninstall reports success"

if [ ! -e "${TEMP_HOME}/.local/bin/oc-sandbox" ]; then
  pass "Uninstall removes symlink"
else
  fail "Uninstall did not remove symlink"
fi

echo ""

# --- Test 41: Uninstall when not installed ---

echo "--- Test 41: Uninstall when not installed ---"

TEMP_HOME="${TEST_DIR}/temp_home_notinstalled"
mkdir -p "${TEMP_HOME}/.local/bin"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" uninstall 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "Uninstall when not installed exits with 0"
assert_stderr_contains "$OUTPUT" "Not installed" "Uninstall reports not installed"

echo ""

# --- Test 42: Uninstall refuses regular file ---

echo "--- Test 42: Uninstall refuses regular file ---"

TEMP_HOME="${TEST_DIR}/temp_home_uninstall_regular"
mkdir -p "${TEMP_HOME}/.local/bin"
echo "not a symlink" > "${TEMP_HOME}/.local/bin/oc-sandbox"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" uninstall 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Uninstall refuses regular file (non-zero exit)"
else
  fail "Uninstall should refuse regular file"
fi
assert_stderr_contains "$OUTPUT" "Not a symlink" "Uninstall warns about regular file"

echo ""

# --- Test 43: Uninstall refuses symlink to different target ---

echo "--- Test 43: Uninstall refuses different symlink ---"

TEMP_HOME="${TEST_DIR}/temp_home_uninstall_diff"
mkdir -p "${TEMP_HOME}/.local/bin"
ln -s /some/other/path "${TEMP_HOME}/.local/bin/oc-sandbox"

OUTPUT=$(HOME="$TEMP_HOME" "$OC_SANDBOX" uninstall 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  pass "Uninstall refuses symlink to different target (non-zero exit)"
else
  fail "Uninstall should refuse symlink to different target"
fi
assert_stderr_contains "$OUTPUT" "points to a different location" "Uninstall warns about different symlink"

echo ""

# --- Test 44: GitHub CLI available ---

echo "--- Test 44: GitHub CLI available ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
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
      bash -c "command -v gh >/dev/null 2>&1 && echo 'gh_found' || echo 'gh_not_found'") || true

    if printf '%s' "$OUTPUT" | grep -q "gh_found"; then
      pass "GitHub CLI is available in container"
    else
      fail "GitHub CLI not found in container: $OUTPUT"
    fi
  else
    skip "GitHub CLI available test (image not built)"
  fi
else
  skip "GitHub CLI available test (podman not available)"
fi

echo ""

# --- Test 45: --debug in help ---

echo "--- Test 45: --debug in help ---"

OUTPUT=$("$OC_SANDBOX" run --help 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "run --help exits with 0"
assert_stderr_contains "$OUTPUT" "--debug" "run --help mentions --debug"

echo ""

# --- Test 46: --debug runs bash ---

echo "--- Test 46: --debug runs bash ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_46"
    mkdir -p "${TEMP_HOME}/workspace"

    OUTPUT=$(HOME="$TEMP_HOME" echo 'echo running_bash; exit' | run_with_timeout 5 "$OC_SANDBOX" run --debug "$TEMP_HOME/workspace" 2>&1) || true

    if printf '%s' "$OUTPUT" | grep -q "running_bash"; then
      pass "--debug runs /bin/bash in container"
    else
      fail "--debug did not run /bin/bash: $OUTPUT"
    fi
  else
    skip "--debug runs bash test (image not built)"
  fi
else
  skip "--debug runs bash test (podman not available)"
fi

echo ""

# --- Test 47: --no-gh-token flag ---

echo "--- Test 47: --no-gh-token flag ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_47"
    mkdir -p "${TEMP_HOME}/workspace"

    OUTPUT=$(HOME="$TEMP_HOME" run_with_timeout 3 "$OC_SANDBOX" run --no-gh-token "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "Skipping GH_TOKEN detection" "--no-gh-token prints skip message"
  else
    skip "--no-gh-token flag test (image not built)"
  fi
else
  skip "--no-gh-token flag test (podman not available)"
fi

echo ""

# --- Test 48: --gh-token flag ---

echo "--- Test 48: --gh-token flag ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_48"
    mkdir -p "${TEMP_HOME}/workspace"

    OUTPUT=$(HOME="$TEMP_HOME" echo 'echo GH_TOKEN=$GH_TOKEN; exit' | run_with_timeout 5 "$OC_SANDBOX" run --gh-token my-test-token "$TEMP_HOME/workspace" 2>&1) || true

    if printf '%s' "$OUTPUT" | grep -q "GH_TOKEN=my-test-token"; then
      pass "--gh-token passes GH_TOKEN into container"
    else
      fail "--gh-token did not pass GH_TOKEN: $OUTPUT"
    fi
  else
    skip "--gh-token flag test (image not built)"
  fi
else
  skip "--gh-token flag test (podman not available)"
fi

echo ""

# --- Test 49: GH_TOKEN auto-detect warning ---

echo "--- Test 49: GH_TOKEN auto-detect warning ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_49"
    mkdir -p "${TEMP_HOME}/workspace"

    # Use a PATH that does not include gh
    OUTPUT=$(HOME="$TEMP_HOME" PATH="/usr/bin:/bin" run_with_timeout 3 "$OC_SANDBOX" run "$TEMP_HOME/workspace" 2>&1) || true

    assert_stderr_contains "$OUTPUT" "gh CLI not found on host" "Missing gh CLI produces warning"
  else
    skip "GH_TOKEN auto-detect warning test (image not built)"
  fi
else
  skip "GH_TOKEN auto-detect warning test (podman not available)"
fi

echo ""

# --- Test 50: --debug + --no-gh-token ---

echo "--- Test 50: --debug + --no-gh-token ---"

if [ "$PODMAN_AVAILABLE" = "true" ]; then
  IMAGE_NAME="localhost/opencode-sandbox:main"
  if podman image exists "$IMAGE_NAME" 2>/dev/null; then
    TEMP_HOME="${TEST_DIR}/temp_home_50"
    mkdir -p "${TEMP_HOME}/workspace"

    OUTPUT=$(HOME="$TEMP_HOME" echo 'echo combined_test; exit' | run_with_timeout 5 "$OC_SANDBOX" run --debug --no-gh-token "$TEMP_HOME/workspace" 2>&1) || true

    if printf '%s' "$OUTPUT" | grep -q "combined_test"; then
      pass "--debug and --no-gh-token work together"
    else
      fail "--debug + --no-gh-token did not work: $OUTPUT"
    fi
  else
    skip "--debug + --no-gh-token test (image not built)"
  fi
else
  skip "--debug + --no-gh-token test (podman not available)"
fi

echo ""

# --- Test 51: --no-gh-token + --gh-token conflict ---

echo "--- Test 51: --no-gh-token + --gh-token conflict ---"

OUTPUT=$("$OC_SANDBOX" run --no-gh-token --gh-token fake-token "$TEST_DIR" 2>&1) || true
if printf '%s' "$OUTPUT" | grep -q "Cannot use --gh-token with --no-gh-token"; then
  pass "conflicting --no-gh-token and --gh-token produces error"
else
  fail "conflicting flags did not produce expected error: $OUTPUT"
fi

echo ""

# --- Test 52: --gh-token in help ---

echo "--- Test 52: --gh-token in help ---"

OUTPUT=$("$OC_SANDBOX" run --help 2>&1)
EXIT_CODE=$?
assert_exit_code 0 "$EXIT_CODE" "run --help exits with 0"
assert_stderr_contains "$OUTPUT" "--gh-token" "run --help mentions --gh-token"

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
