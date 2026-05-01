#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for opencode-sandbox container image
# Initializes git submodules and ensures directory structure is ready
# Run during container image build (called from Containerfile)

REPO_DIR="/home/sandbox/opencode-config"

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
if [ ! -f "profiles/dev/opencode.json" ]; then
    echo "Error: dev profile opencode.json not found (submodules may not be fully initialized)" >&2
    exit 1
fi

echo "Bootstrap complete."
