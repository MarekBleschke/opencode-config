#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/MarekBleschke/oc-sandbox.git"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

error() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

warn() {
  echo -e "${YELLOW}Warning: $1${NC}" >&2
}

info() {
  echo -e "${GREEN}$1${NC}"
}

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Install oc-sandbox to ~/.local/bin/ with XDG-standard data and config directories.

Options:
    --dev               Development mode: symlink files from local repository
    --no-completions    Skip shell completion setup
    -h, --help          Show this help message
EOF
}

main() {
  local dev_mode="false"
  local no_completions="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --dev)
      dev_mode="true"
      shift
      ;;
    --no-completions)
      no_completions="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      error "Unknown option: $1\nUse 'install.sh --help' for usage information."
      ;;
    *)
      error "Unknown argument: $1\nUse 'install.sh --help' for usage information."
      ;;
    esac
  done

  local script_source="${BASH_SOURCE[0]:-}"
  local script_dir=""
  local is_local="false"
  local repo_dir=""

  if [ -n "$script_source" ] && [ "$script_source" != "-" ] && [[ "$script_source" != /dev/fd/* ]] && [ -f "$script_source" ]; then
    script_dir="$(cd "$(dirname "$script_source")" 2>/dev/null && pwd -P)" || true
  fi

  if [ -n "$script_dir" ] && [ -f "${script_dir}/sandbox/oc-sandbox" ]; then
    is_local="true"
    repo_dir="$script_dir"
  fi

  if [ "$dev_mode" = "true" ] && [ "$is_local" = "false" ]; then
    error "--dev requires running from a local repository"
  fi

  local temp_dir=""
  if [ "$is_local" = "false" ]; then
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT
    info "Cloning repository..."
    git clone --depth 1 "$REPO_URL" "$temp_dir"
    repo_dir="$temp_dir"
  fi

  local install_dir="${HOME}/.local/bin"
  local install_path="${install_dir}/oc-sandbox"
  local data_dir="${HOME}/.local/share/oc-sandbox"
  local config_dir="${HOME}/.config/oc-sandbox"

  mkdir -p "$install_dir"
  mkdir -p "$data_dir"
  mkdir -p "$config_dir"

  if [ "$dev_mode" = "true" ]; then
    ln -sf "${repo_dir}/sandbox/oc-sandbox" "$install_path"
    info "Symlinked ${install_path} → ${repo_dir}/sandbox/oc-sandbox"
  else
    cp "${repo_dir}/sandbox/oc-sandbox" "$install_path"
    chmod +x "$install_path"
    info "Installed ${install_path}"
  fi

  local data_items=("containerfiles" "init.sh" "opencode-install.sha256" "completion_zsh")
  for item in "${data_items[@]}"; do
    local src="${repo_dir}/sandbox/${item}"
    local dst="${data_dir}/${item}"
    if [ "$dev_mode" = "true" ]; then
      ln -sf "$src" "$dst"
      info "Symlinked ${dst} → ${src}"
    else
      if [ -d "$src" ]; then
        rm -rf "$dst" 2>/dev/null || true
        cp -R "$src" "$dst"
      else
        cp "$src" "$dst"
      fi
      info "Copied ${dst}"
    fi
  done

  local config_file="${config_dir}/config"
  local config_created="false"
  if [ ! -f "$config_file" ]; then
    cp "${repo_dir}/sandbox/oc-sandbox.conf" "$config_file"
    config_created="true"
    info "Created default config at ${config_file}"
  else
    info "Config already exists at ${config_file} — preserving existing configuration"
  fi

  if [ "$config_created" = "true" ]; then
    local git_name git_email
    git_name="$(git config --global user.name 2>/dev/null || true)"
    git_email="$(git config --global user.email 2>/dev/null || true)"

    if [ -n "$git_name" ] || [ -n "$git_email" ]; then
      if [ -n "$git_name" ]; then
        local escaped_name
        escaped_name="${git_name//&/\\&}"
        sed -i.bak "s|^user_name =.*|user_name = ${escaped_name}|" "$config_file"
        rm -f "$config_file.bak"
      fi
      if [ -n "$git_email" ]; then
        local escaped_email
        escaped_email="${git_email//&/\\&}"
        sed -i.bak "s|^user_email =.*|user_email = ${escaped_email}|" "$config_file"
        rm -f "$config_file.bak"
      fi
      info "Populated git identity in config"
    else
      warn "No git identity found in host ~/.gitconfig. Edit ${config_file} manually to add git identity."
    fi
  fi

  if [ "$config_created" = "true" ]; then
    if ! grep -q '^\[mounts\]' "$config_file" 2>/dev/null; then
      cat >>"$config_file" <<'MOUNTS_EOF'

[mounts]
# Host paths mounted into the sandbox container: src_path|container_dst_path
# Use ~/ for home directory references (expanded at runtime)
ssh_key = ~/.ssh/id_rsa|/home/sandbox/.ssh/id_rsa
auth_json = ~/.local/share/opencode/auth.json|/home/sandbox/.local/share/opencode/auth.json
MOUNTS_EOF
      info "Pre-filled [mounts] section with default paths"
    fi
  fi

  local profiles_source="${repo_dir}/default-profiles"
  local profiles_target="${config_dir}/profiles"

  if [ -d "$profiles_source" ]; then
    mkdir -p "$profiles_target"
    local profile_dir name
    for profile_dir in "$profiles_source"/*/; do
      [[ -d "$profile_dir" ]] || continue
      [[ -f "$profile_dir/profile.conf" ]] || continue
      name="$(basename "$profile_dir")"
      local abs_path
      abs_path="$(cd "$profile_dir" && pwd)"
      local target_path="${profiles_target}/${name}"
      if [ "$dev_mode" = "true" ]; then
        ln -sf "$abs_path" "$target_path"
        info "Symlinked profile: $name"
      else
        rm -rf "$target_path" 2>/dev/null || true
        cp -R "$abs_path" "$target_path"
        info "Installed profile: $name"
      fi
    done
  fi

  if [ "$no_completions" = "false" ]; then
    local shell
    shell="$(basename "${SHELL:-}")"
    case "$shell" in
    zsh)
      local rc_file="${HOME}/.zshrc"
      local completion_line='source <(oc-sandbox completion zsh)'
      if [ -L "$rc_file" ]; then
        info ".zshrc is a symlink; completions will be added to the target file"
      fi
      if [ ! -f "$rc_file" ]; then
        touch "$rc_file"
      fi
      if grep -qF "$completion_line" "$rc_file" 2>/dev/null; then
        info "Shell completions already set up in ${rc_file}"
      else
        echo '' >>"$rc_file"
        echo "$completion_line" >>"$rc_file"
        info "Added shell completions to ${rc_file}"
      fi
      ;;
    bash)
      warn "Bash completion is not yet implemented."
      ;;
    fish)
      warn "Fish completion is not yet implemented."
      ;;
    *)
      warn "Unknown shell '${shell}'. Add to your shell config: source <(oc-sandbox completion zsh)"
      ;;
    esac
  fi

  if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
    warn "${install_dir} is not in PATH. Add it with:"
    warn "  export PATH=\"${install_dir}:\$PATH\""
  fi

  info "Installation complete."
  info "Config file location: ${config_file}"
  info "Customize agent models and git identity there."
}

main "$@"
