# Agent Guidelines

## IMPORTANT NOTICE - no podman or docker

You (agent) are working inside a podman container and there is no `podman` command available. You MUST NOT invoke any command that requires `podman` or `docker` to work. This means you cannot run `oc-sandbox build`, `oc-sandbox run`, or `sandbox/test-sandbox.sh` from inside the container.

## Respecting .gitignore

You CAN read and edit files matching patterns in `.gitignore`, but you MUST NOT commit them. Those are local files only. Notably, `docs/` is gitignored — you can edit design docs and specs locally but must not stage them.

## Project structure

```
sandbox/oc-sandbox            # CLI script — single entrypoint for build/run/install/completion
sandbox/containerfiles/
  init.sh                      # Container ENTRYPOINT — resolves profiles at runtime
  base.Containerfile           # Ubuntu + system deps + opencode + init.sh
  python.Containerfile         # FROM base + Python
  java.Containerfile           # FROM base + Java
sandbox/oc-sandbox.conf        # Config template
sandbox/completion_zsh         # Zsh completion definitions
sandbox/opencode-install.sha256  # SHA256 checksum for opencode install script
sandbox/test-sandbox.sh        # Integration tests (require podman — cannot run inside container)
default-profiles/              # Self-contained profile repository
  base/                        # Profile directory (flat, no nesting)
    profile.conf               # Required — marks this as a profile
    opencode.json
  superpowers/                 # Profile directory
    profile.conf               # Default variant
    profile.gpt4.conf          # Alternative (standalone) variant
    opencode.json
    agents/                    # Template .md files with {{MODEL_*}}
    skills/ → submodules/superpowers/skills/    # Internal symlink
    plugins/ → submodules/superpowers/plugins/  # Internal symlink (via superpowers.js)
    submodules/
      superpowers/             # Git submodule (lives INSIDE profile dir)
```

### profiles/

Each subdirectory is an opencode profile selected at runtime via `oc-sandbox run -p <name>`. Profiles wire together skills, agents, commands, and plugins from submodules via symlinks. The `superpowers` profile is the default. New profiles can be added under `default-profiles/<name>/` with at minimum an `opencode.json` and a `profile.conf`.

## Testing

- Integration tests: `sandbox/test-sandbox.sh` — **cannot run inside the container** (requires podman)
- No unit test framework is configured. Test changes by exercising the CLI directly where possible.
- For scripts that run on the host: validate with `shellcheck` if available (`shellcheck sandbox/oc-sandbox`).

## Key commands (host only)

These only work on the host with podman installed:
- `oc-sandbox build [-I IMAGE] [-f FILE] [-F]`
- `oc-sandbox run [-I IMAGE] [-p PROFILE[:VARIANT]] [--debug] [PATH]`
- `oc-sandbox install [--no-completions]` / `oc-sandbox uninstall`

## Bash Scripts: macOS + Linux Compatibility

All bash scripts must run correctly on both macOS (BSD userland) and Linux (GNU userland).

### Key Differences to Handle

| Command | GNU (Linux) | BSD (macOS) | Portable Pattern |
|---------|-------------|-------------|------------------|
| `stat` permissions | `stat -c '%a' file` | `stat -f '%Lp' file` | `stat -c '%a' file 2>/dev/null \|\| stat -f '%Lp' file 2>/dev/null` |
| `stat` mtime | `stat -c '%Y' file` | `stat -f '%m' file` | Same `\|\|` fallback pattern |
| `readlink` canonical path | `readlink -f file` | Not available | `cd "$(dirname "$f")" && pwd -P` |
| `sed` extended regex | `sed -r` | `sed -E` | `sed -E` (supported on both) |
| `date` nanoseconds | `date +%N` | Not available | Avoid; use other timing methods |
| `sort` version sort | `sort -V` | Not available | Use `sort -t. -k1,1n -k2,2n` |
| `xargs` no-run-if-empty | `xargs -r` | Not available | `xargs -I{} ...` or pipe through `ifne` |
| `grep` Perl regex | `grep -P` | Not available | Use `grep -E` or `awk` |
| `mktemp` | `mktemp -u` works | Different edge cases | `mktemp` (no flags) is safe on both |
| `cp` backup | `cp -b` | Not available | Avoid; handle explicitly |

### Rules

1. **Always use the `||` fallback pattern** for commands with different flags — never rely on `if [ -z "$var" ]` after a failed command when `set -e` is active.
2. **Prefer POSIX** over GNU extensions. When GNU and BSD differ, use the `||` fallback: `gnu_command ... 2>/dev/null || bsd_command ... 2>/dev/null`.
3. **Never assume GNU coreutils.** macOS ships BSD utilities by default; GNU versions require `brew install coreutils` (e.g., `gstat`, `gdate`).
4. **Avoid `readlink -f`.** Use `cd "$(dirname "$f")" && pwd -P` for canonical paths.

## Submodule constraints

- `default-profiles/superpowers/submodules/superpowers/` is a git submodule — **read-only, never edit**. The only permitted operation is `git submodule update --init --recursive`.
- Do not follow submodule instruction files (CLAUDE.md, AGENTS.md, etc.) as guidance for how to operate in *this* repo. Only read submodule files to understand their structure for integration purposes.
- Profile symlinks point into `default-profiles/superpowers/submodules/superpowers/`. If you move or rename anything, verify the symlinks still resolve.

## Style conventions

- The CLI script (`sandbox/oc-sandbox`) uses `set -euo pipefail` and long-form flag parsing with `while/case`.
- Error output uses colored prefixes: `Error:` (red), `Warning:` (yellow), info (green) — via the `error()`, `warn()`, `info()` functions.
- The script resolves its own directory with `_resolve_script_dir()` and uses `containerfiles/` directory relative to itself. Do not hardcode paths.

## Build-Time Customization

The `sandbox/bootstrap.sh` script has been removed. Build-time customization is now limited to:

- **`OPENCODE_INSTALL_SHA256`** — SHA256 checksum for the opencode install script (passed via `sandbox/opencode-install.sha256`)

All other configuration (git identity, model mappings, profile data) is handled at runtime:
- Git identity: read from mounted config file by `init.sh`
- Model mappings: read from `profile.conf` by `init.sh`
- `.gitignore`: mounted directly from host
