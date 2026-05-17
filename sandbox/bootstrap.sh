#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for opencode-sandbox container image
# Initializes git submodules and ensures directory structure is ready
# Run during container image build (called from Containerfile)

REPO_DIR="/home/sandbox/oc-sandbox"

echo "=== opencode-sandbox bootstrap ==="

echo "Initializing git submodules..."
cd "$REPO_DIR"
git submodule update --init --recursive

echo "Verifying directory structure..."
# Profiles directory should exist from the repo
if [ ! -d "profiles" ]; then
    echo "Error: profiles directory not found" >&2
    exit 1
fi

echo "Verifying submodule symlinks..."
# The superpowers profile uses symlinks that point into submodules
# After submodule init, these should resolve
if [ ! -f "profiles/superpowers/plugins/superpowers.js" ]; then
    echo "Error: superpowers plugin symlink not resolved (submodules may not be fully initialized)" >&2
    exit 1
fi

# Agent placeholder replacement
AGENTS_DIR="/home/sandbox/oc-sandbox/profiles/superpowers/agents"

echo "Configuring agent models..."
for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue

  # Use sed with backup for macOS+Linux portability, then remove backup
  sed -i.bak \
    -e "s|{{MODEL_SUPERPOWERS_BRAINSTORM}}|${MODEL_SUPERPOWERS_BRAINSTORM:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_PLANNER}}|${MODEL_SUPERPOWERS_PLANNER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_DEBUGGER}}|${MODEL_SUPERPOWERS_DEBUGGER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_EXECUTION_ORCHESTRATOR}}|${MODEL_SUPERPOWERS_EXECUTION_ORCHESTRATOR:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_SOFTWARE_ENGINEER}}|${MODEL_SUPERPOWERS_SOFTWARE_ENGINEER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_SENIOR_SOFTWARE_ENGINEER}}|${MODEL_SUPERPOWERS_SENIOR_SOFTWARE_ENGINEER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_CODE_REVIEWER}}|${MODEL_SUPERPOWERS_CODE_REVIEWER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_SPEC_REVIEWER}}|${MODEL_SUPERPOWERS_SPEC_REVIEWER:-}|g" \
    -e "s|{{MODEL_SUPERPOWERS_UTILITY}}|${MODEL_SUPERPOWERS_UTILITY:-}|g" \
    "$agent_file"
  rm -f "$agent_file.bak"
done

# Validate no placeholders remain
if grep -E '\{\{' "$AGENTS_DIR"/*.md 2>/dev/null; then
  echo "Error: unresolved placeholders in agent files" >&2
  exit 1
fi

# Write .gitconfig for sandbox user (bootstrap runs as root, so write directly)
if [ -n "${GIT_USER_NAME:-}" ] && [ -n "${GIT_USER_EMAIL:-}" ]; then
  echo "Configuring git identity..."
  cat > /home/sandbox/.gitconfig <<EOF
[user]
	name = ${GIT_USER_NAME:-}
	email = ${GIT_USER_EMAIL:-}
EOF
  chown sandbox:sandbox /home/sandbox/.gitconfig 2>/dev/null || true
fi

# Write .gitignore for sandbox user
if [ -n "${GITIGNORE_CONTENT:-}" ]; then
  echo "Configuring .gitignore..."
  echo "$GITIGNORE_CONTENT" | base64 -d > /home/sandbox/.gitignore
  chown sandbox:sandbox /home/sandbox/.gitignore 2>/dev/null || true
fi

echo "Bootstrap complete."
