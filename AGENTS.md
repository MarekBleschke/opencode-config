# Agent Guidelines

## IMPORTANT NOTICE - no podman or docker

You (agent) are working inside a podman container and there is no `podman` command available. You MUST NOT invoke any command that requires `podman` or `docker` to work. This means you cannot run `oc-sandbox build`, `oc-sandbox run`, or `sandbox/test-sandbox.sh` from inside the container.

## Respecting .gitignore

You CAN read and edit files matching patterns in `.gitignore`, but you MUST NOT commit them. Those are local files only. Notably, `docs/` is gitignored — you can edit design docs and specs locally but must not stage them.

## Project structure

```
sandbox/oc-sandbox          # CLI script — single entrypoint for build/run/install/completion
sandbox/Containerfile       # Podman image (Ubuntu 24.04, installs git, go, gh, opencode)
sandbox/bootstrap.sh        # Runs during image build: inits submodules, verifies symlinks
sandbox/test-sandbox.sh    # Integration tests (require podman — cannot run inside container)
sandbox/opencode-install.sha256  # SHA256 checksum for opencode install script
sandbox/completion_zsh     # Zsh completion definitions
profiles/                  # Opencode config directories, one per profile
  dev/                     # Default profile
    opencode.json          # Opencode configuration
    agents/                # Agent definitions (markdown)
    commands/              # Command definitions (markdown)
    plugins/               # Plugins (JS modules loaded by opencode)
    skills/                # Skills (markdown with frontmatter) — local or symlinked
submodules/                # Pinned external repositories (READ ONLY — never edit these)
  superpowers/             # Git submodule — skills, agents, plugins for opencode
docs/specs/, docs/plans/   # Design documents (gitignored)
```

### profiles/

Each subdirectory is an opencode profile selected at runtime via `oc-sandbox run -p <name>`. Profiles wire together skills, agents, commands, and plugins from submodules via symlinks. The `dev` profile is the default. New profiles can be added under `profiles/<name>/` with at minimum an `opencode.json`.

## Testing

- Integration tests: `sandbox/test-sandbox.sh` — **cannot run inside the container** (requires podman)
- No unit test framework is configured. Test changes by exercising the CLI directly where possible.
- For scripts that run on the host: validate with `shellcheck` if available (`shellcheck sandbox/oc-sandbox sandbox/bootstrap.sh`).

## Key commands (host only)

These only work on the host with podman installed:
- `oc-sandbox build [--tag TAG] [--force]`
- `oc-sandbox run [-p PROFILE] [-t TAG] [--debug] [PATH]`
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

- `submodules/superpowers/` is a git submodule — **read-only, never edit**. The only permitted operation is `git submodule update --init --recursive`.
- Do not follow submodule instruction files (CLAUDE.md, AGENTS.md, etc.) as guidance for how to operate in *this* repo. Only read submodule files to understand their structure for integration purposes.
- Profile symlinks point into `submodules/superpowers/`. If you move or rename anything, verify the symlinks still resolve.

## Style conventions

- The CLI script (`sandbox/oc-sandbox`) uses `set -euo pipefail` and long-form flag parsing with `while/case`.
- Error output uses colored prefixes: `Error:` (red), `Warning:` (yellow), info (green) — via the `error()`, `warn()`, `info()` functions.
- The script resolves its own directory with `_resolve_script_dir()` to find `Containerfile` relative to itself. Do not hardcode paths.

## Build-Time Customization

The `sandbox/bootstrap.sh` script is the designated place for all build-time customization logic. This includes:

- **Placeholder replacement** in profile agent files (e.g., replacing `{{MODEL_DEV_*}}` placeholders with values from the build configuration)
- **File generation from build arguments** (e.g., writing `.gitconfig` and `.gitignore` from `GIT_USER_NAME`, `GIT_USER_EMAIL`, and `GITIGNORE_CONTENT` build args)

When adding new build-time behavior:

1. Pass the required data as `ARG` declarations in `sandbox/Containerfile`
2. Forward them as environment variables to `bootstrap.sh` in the `RUN` command
3. Implement the customization logic in `bootstrap.sh`
4. Update `AGENTS.md` to document the new build arguments

Do not add build-time logic outside of `bootstrap.sh` — keeping it centralized makes the build process easier to understand and maintain.
