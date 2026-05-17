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
# The dev profile uses symlinks that point into submodules
# After submodule init, these should resolve
if [ ! -f "profiles/dev/plugins/superpowers.js" ]; then
    echo "Error: superpowers plugin symlink not resolved (submodules may not be fully initialized)" >&2
    exit 1
fi

# Agent placeholder replacement
AGENTS_DIR="/home/sandbox/oc-sandbox/profiles/dev/agents"

echo "Configuring agent models..."
for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue

  # Use sed with backup for macOS+Linux portability, then remove backup
  sed -i.bak \
    -e "s|{{MODEL_DEV_BRAINSTORM}}|${MODEL_DEV_BRAINSTORM:-}|g" \
    -e "s|{{MODEL_DEV_PLANNER}}|${MODEL_DEV_PLANNER:-}|g" \
    -e "s|{{MODEL_DEV_DEBUGGER}}|${MODEL_DEV_DEBUGGER:-}|g" \
    -e "s|{{MODEL_DEV_EXECUTION_ORCHESTRATOR}}|${MODEL_DEV_EXECUTION_ORCHESTRATOR:-}|g" \
    -e "s|{{MODEL_DEV_SOFTWARE_ENGINEER}}|${MODEL_DEV_SOFTWARE_ENGINEER:-}|g" \
    -e "s|{{MODEL_DEV_SENIOR_SOFTWARE_ENGINEER}}|${MODEL_DEV_SENIOR_SOFTWARE_ENGINEER:-}|g" \
    -e "s|{{MODEL_DEV_CODE_REVIEWER}}|${MODEL_DEV_CODE_REVIEWER:-}|g" \
    -e "s|{{MODEL_DEV_SPEC_REVIEWER}}|${MODEL_DEV_SPEC_REVIEWER:-}|g" \
    -e "s|{{MODEL_DEV_UTILITY}}|${MODEL_DEV_UTILITY:-}|g" \
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
