# oc-sandbox: GitHub CLI Installation, GH_TOKEN Auth, and Debug Mode

**Date:** 2026-05-02  
**Status:** Draft  
**Applies to:** `sandbox/Containerfile`, `sandbox/oc-sandbox`, `sandbox/test-sandbox.sh`

## Overview

Three improvements to the `oc-sandbox` tool:

1. Install GitHub CLI (`gh`) in the container image
2. Auto-detect and pass the GitHub auth token (`GH_TOKEN`) from the host to the container
3. Add a `--debug` flag that drops the user into an interactive bash shell instead of running opencode

## Design Approach

**Pattern-consistent approach** — new features follow the established `--no-ssh`/`--no-auth` conventions in the codebase. This means:
- Auto-detection by default with `--no-gh-token` to skip
- Explicit override with `--gh-token <value>`
- Warning on failure, but continue running

---

## 1. Containerfile: Install GitHub CLI

Add `gh` to the container image using the official GitHub CLI apt repository.

### Implementation

Add a new `RUN` layer after the existing system dependencies layer (before the opencode installation). This keeps the base packages layer cache-friendly and the gh installation independently updateable.

```dockerfile
# Install GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*
```

### Rationale

- **Separate layer**: Keeps the base Ubuntu packages layer cache-friendly. The gh layer can be rebuilt independently.
- **Official apt repo**: Enables future `apt upgrade gh` and matches the recommended installation method from GitHub's docs.
- **`--no-install-recommends`**: Minimizes image size by skipping recommended (non-essential) packages.
- **`rm -rf /var/lib/apt/lists/*`**: Cleans up apt cache to reduce image size, consistent with the existing system dependencies layer.

---

## 2. GH_TOKEN Auto-Detection and Passing

### New CLI Flags

| Flag | Description |
|------|-------------|
| `--no-gh-token` | Skip GH_TOKEN detection entirely. Prints info message and continues. |
| `--gh-token <value>` | Use the provided token value directly. Skips auto-detection. Conflicts with `--no-gh-token`. |

### Auto-Detection Logic

After the existing `auth.json` detection block in `cmd_run()`, add GH_TOKEN detection:

1. If `--no-gh-token` is set:
   - Print: `"Skipping GH_TOKEN detection (--no-gh-token)"`
   - Skip all detection
   - If `--gh-token` was also provided, error: `"Cannot use --gh-token with --no-gh-token"`

2. If `--gh-token <value>` is provided:
   - Use the provided value directly as `GH_TOKEN`
   - Skip auto-detection

3. Default (no flags): Auto-detect from host:
   - Check if `gh` command exists on the host (`command -v gh`)
   - If `gh` not found: warn `"gh CLI not found on host. GitHub operations inside the container may not work."` and continue
   - If `gh` found: run `gh auth token` and capture output
     - If `gh auth token` fails (non-zero exit): warn `"gh auth token failed: <stderr>. GitHub operations inside the container may not work."` and continue
     - If successful: strip whitespace from the token
       - If the token is empty after stripping: warn `"gh auth token returned empty token. GitHub operations inside the container may not work."` and continue
       - If the token is non-empty: add `--env GH_TOKEN=<token>` to the podman run command

### Argument Validation

- `--gh-token <value>` requires a non-empty value (error if missing or empty), matching the existing pattern for `--tag` and `--profile`.
- The `--no-gh-token` / `--gh-token` conflict is checked after all arguments are parsed, before detection logic runs.

### Podman Integration

The token is passed via `--env GH_TOKEN=<token>` in the `podman run` command, alongside the existing `--env OPENCODE_CONFIG_DIR=...`.

### Security Consideration

The token appears in the host's process list (visible via `ps`) because it's passed as a `--env` flag. This is acceptable for a local development tool — the same pattern is used for `OPENCODE_CONFIG_DIR`. For production or multi-user environments, a secrets-mounting approach would be more appropriate, but that's out of scope for this sandbox tool.

### Help Text Updates

Update `usage_run()` to document the new flags:

```
Options:
    -t, --tag <TAG>            Tag of the image to run (default: main)
    -p, --profile <NAME>      Opencode profile to activate (default: dev)
    --no-ssh                  Skip mounting SSH keys from host
    --no-auth                 Skip mounting auth.json from host
    --no-gh-token             Skip GH_TOKEN detection from host
    --gh-token <TOKEN>        Use the provided GitHub token instead of auto-detecting
    --debug                   Run /bin/bash instead of opencode for debugging
    -h, --help                Show this help message
```

---

## 3. `--debug` Flag

### Behavior

When `--debug` is passed to `oc-sandbox run`:

- The container command changes from `opencode` to `/bin/bash`
- All other settings are preserved: SSH mounts, auth.json mount, GH_TOKEN, `--read-only`, `--cap-drop ALL`, volume mounts, etc.
- The startup info output includes a `Debug:` line showing `/bin/bash`

### Startup Info Output

Without `--debug`:
```
Starting opencode sandbox
  Profile:   dev
  Workspace: /path/to/project
  Image:     localhost/opencode-sandbox:main
```

With `--debug`:
```
Starting opencode sandbox
  Profile:   dev
  Workspace: /path/to/project
  Image:     localhost/opencode-sandbox:main
  Debug:     /bin/bash
```

### Implementation

In `cmd_run()`:
- Add `local debug="false"` variable
- Add `--debug` / `-d` case in the argument parsing loop
- At the podman invocation, conditionally set the command:
  ```bash
  local container_cmd="opencode"
  if [ "$debug" = "true" ]; then
      container_cmd="/bin/bash"
  fi
  ```
- Pass `"$container_cmd"` as the final argument to `podman run` instead of the hardcoded `opencode`

---

## 4. Test Coverage

New tests to add to `test-sandbox.sh`:

| # | Test | Description |
|---|------|-------------|
| 1 | GitHub CLI available | Run `command -v gh` inside container, verify it succeeds |
| 2 | `--debug` in help | Verify `run --help` mentions `--debug` |
| 3 | `--debug` runs bash | Start container with `--debug`, verify it enters `/bin/bash` |
| 4 | `--no-gh-token` flag | Verify it skips GH_TOKEN detection and prints skip message |
| 5 | `--gh-token` flag | Verify explicit token is passed as `GH_TOKEN` env var |
| 6 | GH_TOKEN auto-detect warning | Set HOME to temp dir without gh, verify warning message |
| 7 | `--debug` + `--no-gh-token` | Verify both flags work together |
| 8 | `--no-gh-token` + `--gh-token` conflict | Verify error when both flags are provided |
| 9 | `--gh-token` in help | Verify `run --help` mentions `--gh-token` |

---

## Files Modified

| File | Changes |
|------|---------|
| `sandbox/Containerfile` | Add GitHub CLI installation layer |
| `sandbox/oc-sandbox` | Add `--debug`, `--no-gh-token`, `--gh-token` flags to `cmd_run()`; add GH_TOKEN detection logic; update `usage_run()` |
| `sandbox/test-sandbox.sh` | Add tests for new features |