#!/usr/bin/env bash
set -euo pipefail

# oc-sandbox-init.sh — Container entrypoint
# Resolves profile config, processes agent templates, launches opencode.
# Receives the container's CMD as $@.

# Debug mode: if CMD was overridden (e.g., /bin/bash), exec it directly
if [ $# -gt 0 ]; then
  exec "$@"
fi

# Parse OC_SANDBOX_PROFILE env var
# Format: "profilename" or "profilename:variant"
PROFILE_SPEC="${OC_SANDBOX_PROFILE:-}"
if [ -z "$PROFILE_SPEC" ]; then
  echo "Error: OC_SANDBOX_PROFILE environment variable not set" >&2
  exit 1
fi

PROFILE_NAME="${PROFILE_SPEC%%:*}"
PROFILE_VARIANT="${PROFILE_SPEC#*:}"
# If no colon was present, PROFILE_VARIANT equals PROFILE_NAME — reset it
if [ "$PROFILE_VARIANT" = "$PROFILE_NAME" ]; then
  PROFILE_VARIANT=""
fi

# Validate profile name is not empty
if [ -z "$PROFILE_NAME" ]; then
  echo "Error: Empty profile name in OC_SANDBOX_PROFILE='${PROFILE_SPEC}'" >&2
  exit 1
fi

PROFILE_DIR="/mnt/oc-sandbox-profiles"
CONFIG_FILE="/mnt/oc-sandbox-config/config"

# Verify profile directory is mounted
if [ ! -d "$PROFILE_DIR" ]; then
  echo "Error: Profile directory not mounted at $PROFILE_DIR" >&2
  exit 1
fi

# Verify profile.conf exists (or variant)
if [ -n "$PROFILE_VARIANT" ]; then
  CONF_FILE="${PROFILE_DIR}/profile.${PROFILE_VARIANT}.conf"
else
  CONF_FILE="${PROFILE_DIR}/profile.conf"
fi

if [ ! -f "$CONF_FILE" ]; then
  echo "Error: Profile config not found: $CONF_FILE" >&2
  exit 1
fi

# --- Read git config from mounted config file ---
GIT_USER_NAME=""
GIT_USER_EMAIL=""
if [ -f "$CONFIG_FILE" ]; then
  # Parse [git] section
  in_git="false"
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$trimmed" ] && continue
    [[ "$trimmed" == \#* ]] && continue
    [[ "$trimmed" == \;* ]] && continue
    if [[ "$trimmed" == \[*\] ]]; then
      if [ "$trimmed" = "[git]" ]; then
        in_git="true"
      else
        in_git="false"
      fi
      continue
    fi
    if [ "$in_git" = "true" ]; then
      key_part="$(echo "$trimmed" | cut -d= -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      value_part="$(echo "$trimmed" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      case "$key_part" in
        user_name) GIT_USER_NAME="$value_part" ;;
        user_email) GIT_USER_EMAIL="$value_part" ;;
      esac
    fi
  done < "$CONFIG_FILE"
fi

# Write .gitconfig
if [ -n "$GIT_USER_NAME" ] || [ -n "$GIT_USER_EMAIL" ]; then
  {
    printf '[user]\n'
    printf '\tname = %s\n' "$GIT_USER_NAME"
    printf '\temail = %s\n' "$GIT_USER_EMAIL"
  } > /home/sandbox/.gitconfig
fi

# --- Read profile config (models section) ---
declare -A MODELS
in_models="false"
while IFS= read -r line || [ -n "$line" ]; do
  trimmed="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$trimmed" ] && continue
  [[ "$trimmed" == \#* ]] && continue
  [[ "$trimmed" == \;* ]] && continue
  if [[ "$trimmed" == \[*\] ]]; then
    if [ "$trimmed" = "[models]" ]; then
      in_models="true"
    else
      in_models="false"
    fi
    continue
  fi
  if [ "$in_models" = "true" ]; then
    key_part="$(echo "$trimmed" | cut -d= -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    value_part="$(echo "$trimmed" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    MODELS["$key_part"]="$value_part"
  fi
done < "$CONF_FILE"

# --- Create resolved output directory ---
RESOLVED_DIR="$HOME/.cache/oc-sandbox/resolved"
if [ -n "$PROFILE_VARIANT" ]; then
  RESOLVED_NAME="${PROFILE_NAME}-${PROFILE_VARIANT}"
else
  RESOLVED_NAME="${PROFILE_NAME}"
fi
RESOLVED_PATH="${RESOLVED_DIR}/${RESOLVED_NAME}"

# Guard against empty resolved name (shouldn't happen, but safety)
if [ -z "$RESOLVED_NAME" ]; then
  echo "Error: Could not determine resolved profile name" >&2
  exit 1
fi

# Clean and recreate
rm -rf "$RESOLVED_PATH"
mkdir -p "$RESOLVED_PATH"

# --- Process agent files: copy + placeholder replacement ---
if [ -d "${PROFILE_DIR}/agents" ]; then
  mkdir -p "${RESOLVED_PATH}/agents"
  for agent_file in "${PROFILE_DIR}"/agents/*.md; do
    [ -f "$agent_file" ] || continue
    filename="$(basename "$agent_file")"
    cp "$agent_file" "${RESOLVED_PATH}/agents/${filename}"
    # Replace {{MODEL_<KEY>}} placeholders
    for model_key in "${!MODELS[@]}"; do
      placeholder="MODEL_$(echo "$model_key" | tr 'a-z-' 'A-Z_')"
      model_value="${MODELS[$model_key]}"
      if [ -n "$model_value" ]; then
        # Escape &, |, and \ for safe sed replacement (| is the delimiter)
        escaped_value="$(printf '%s' "$model_value" | sed 's/[&\|\\]/\\&/g')"
        sed -i "s|{{${placeholder}}}|${escaped_value}|g" "${RESOLVED_PATH}/agents/${filename}"
      fi
    done
  done

  # Validate no unresolved placeholders remain
  if grep -rq '{{MODEL_' "${RESOLVED_PATH}/agents/" 2>/dev/null; then
    echo "Warning: Unresolved MODEL placeholders in agent files" >&2
    grep -rn '{{MODEL_' "${RESOLVED_PATH}/agents/" >&2 || true
  fi
fi

# --- Symlink everything from profile dir except agents/ ---
# Agents are already copied and resolved above; all other items
# (opencode.json, skills, plugins, commands, etc.) are symlinked directly
for profile_item in "${PROFILE_DIR}"/*; do
  item_name="$(basename "$profile_item")"
  # Skip agents/ — already processed above
  [ "$item_name" = "agents" ] && continue
  # Skip profile config files — already consumed by init.sh above
  [ "$item_name" = "profile.conf" ] && continue
  [[ "$item_name" == profile.*.conf ]] && continue
  ln -s "$profile_item" "${RESOLVED_PATH}/${item_name}"
done

# --- Launch opencode ---
# Note: $@ is empty at this point (debug mode already handled above),
# but preserved for future CMD passthrough support
export OPENCODE_CONFIG_DIR="${RESOLVED_PATH}"
exec opencode "$@"
