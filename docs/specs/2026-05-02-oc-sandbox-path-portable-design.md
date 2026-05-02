# oc-sandbox PATH-Portable Design

## Problem

The `oc-sandbox` script uses `SCRIPT_DIR` (derived from `BASH_SOURCE[0]`) to locate sibling files: `Containerfile`, `opencode-install.sha256`, and the build context (`../`). When the script is symlinked or copied into `$PATH` (e.g., `~/.local/bin/`), `SCRIPT_DIR` resolves to the PATH directory instead of the repo's `sandbox/` directory, causing `build` to fail with missing file errors. The `run` command works from anywhere since it only needs podman and an image.

## Goal

Make `oc-sandbox` work as a global command from any directory, with both `build` and `run` fully functional, using a dev-mode install that symlinks into the live repo so working-tree changes are immediately available.

## Design

### Symlink-Resolving SCRIPT_DIR

Replace the current `SCRIPT_DIR` derivation with symlink-aware resolution so the script always finds its real location:

```bash
_resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [ -L "$source" ]; do
    local dir
    dir="$(cd "$(dirname "$source")" && pwd -P)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  SCRIPT_DIR="$(cd "$(dirname "$source")" && pwd -P)"
}
_resolve_script_dir
```

This replaces:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

The resolution loop is portable (works on macOS and Linux, avoids `readlink -f`). After resolution, `SCRIPT_DIR` points to the real `sandbox/` directory regardless of how the script was invoked.

### Install Subcommand

`oc-sandbox install` creates a symlink from `~/.local/bin/oc-sandbox` to the script's real path. Since `_resolve_script_dir` runs at startup, `SCRIPT_DIR` already contains the resolved real path — `cmd_install` uses `${SCRIPT_DIR}/oc-sandbox` as the symlink target.

**Behavior:**

1. Use `${SCRIPT_DIR}/oc-sandbox` as the real script path (already resolved by `_resolve_script_dir`)
2. Validate `~/.local/bin/` exists; offer to create it if missing
3. Check if `~/.local/bin/oc-sandbox` already exists:
   - If it's a symlink to the same target → report "already installed", exit 0
   - If it's a symlink to a different target → update the symlink, report "updated"
   - If it's a regular file → warn and refuse to overwrite, exit 1
4. Create the symlink: `ln -sf "${SCRIPT_DIR}/oc-sandbox" ~/.local/bin/oc-sandbox`
5. Check if `~/.local/bin` is in `$PATH`; warn if not
6. Report success with the install location

**Flags:** None for now. The future git-based mode will add `--mode=release`.

### Uninstall Subcommand

`oc-sandbox uninstall` removes the symlink created by `install`.

**Behavior:**

1. Resolve the real path of the running script
2. Check if `~/.local/bin/oc-sandbox` exists:
   - If it's a symlink pointing to our script → remove it, report "uninstalled"
   - If it's a symlink pointing elsewhere → warn, refuse to remove, exit 1
   - If it's a regular file → warn "not a symlink, refusing to remove", exit 1
   - If it doesn't exist → report "not installed", exit 0
3. Report success

### Help Text Updates

Add `install` and `uninstall` to the main usage:

```
Commands:
    build       Build a container image
    run         Run opencode in a sandbox
    install     Install oc-sandbox as a global command
    uninstall   Uninstall the global oc-sandbox command
```

Add `oc-sandbox install --help` and `oc-sandbox uninstall --help` with usage details.

### What Stays the Same

- `build` and `run` subcommands — unchanged
- All existing flags — unchanged
- Containerfile, sha256, bootstrap.sh — unchanged
- Test script — unchanged (already uses `SCRIPT_DIR` to find `oc-sandbox`)
- Build context still uses `${SCRIPT_DIR}/..` — now correctly resolved through symlinks

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Script copied (not symlinked) to PATH | `SCRIPT_DIR` resolves to the copy's directory. `build` fails with "Containerfile not found". `run` works fine. |
| Repo moved after install | Symlink becomes dangling — clear "command not found" or "No such file or directory" error. Re-run `oc-sandbox install` from the new location to fix. |
| `~/.local/bin` not in PATH | `install` succeeds but warns: "Warning: ~/.local/bin is not in PATH. Add it with: export PATH=\"$HOME/.local/bin:$PATH\"" |
| Already installed, same target | `install` reports "Already installed" and exits 0 |
| Already installed, different target | `install` updates the symlink and reports "Updated" |
| Existing regular file at install path | `install` warns "Refusing to overwrite a regular file" and exits 1 |
| `uninstall` when not installed | Reports "Not installed" and exits 0 |
| `uninstall` when file is not a symlink | Warns "Not a symlink, refusing to remove" and exits 1 |
| `uninstall` when symlink points elsewhere | Warns "Symlink points to a different location, refusing to remove" and exits 1 |

## Future: Git-Based Build Mode (Release Mode)

This design supports a future `--mode=release` flag on `install` that would:

1. Clone or pull the repo into `~/.local/share/oc-sandbox/`
2. Create the `~/.local/bin/oc-sandbox` symlink
3. In this mode, `build` would `git pull` before building to get latest changes

This is **not** implemented now. The `install` subcommand structure makes it a natural extension point. When implemented, the script could detect which mode it's in by checking whether `SCRIPT_DIR` is inside `~/.local/share/oc-sandbox/` vs. a git checkout.

## Implementation Checklist

- [ ] Replace `SCRIPT_DIR` derivation with symlink-resolving version
- [ ] Add `_resolve_script_dir` function
- [ ] Add `cmd_install` function
- [ ] Add `cmd_uninstall` function
- [ ] Add `usage_install` and `usage_uninstall` functions
- [ ] Update `usage_main` to include `install` and `uninstall`
- [ ] Add `install` and `uninstall` to the main `case` dispatch
- [ ] Add tests for `install` and `uninstall` in `test-sandbox.sh`
- [ ] Test symlink resolution on macOS and Linux