# Sandbox QoL Improvements Design

**Date:** 2026-05-02  
**Type:** Technical Design  
**Status:** Draft  
**Supersedes:** Extends `2026-05-01-opencode-sandbox-design.md`

## Summary

Four quality-of-life improvements to the opencode sandbox: GitHub SSH host key pre-configuration, opencode plugin warmup during build, SSH key injection from host, and authenticated provider configuration injection from host. These changes eliminate common friction points when using the sandbox for the first time — interactive host key prompts, ~10 second plugin installation delays, and missing git/auth credentials.

## Goals

- **Seamless GitHub SSH** — `git clone` via SSH to github.com works without interactive host key confirmation
- **Fast first launch** — Opencode plugins are pre-installed during build, eliminating the ~10 second hang on first interactive run
- **Git authentication** — Host SSH keys are available inside the container for git operations
- **Provider authentication** — Host opencode auth credentials are available inside the container for authenticated providers
- **Security** — Injected credentials are read-only inside the container; container processes cannot modify host files
- **Graceful degradation** — Missing credentials produce warnings, not errors; the container still starts

## Non-Goals

- Network isolation or restriction changes
- Supporting SSH keys other than `id_rsa`/`id_rsa.pub`
- Supporting git hosts other than GitHub (can be added later)
- Modifying host files from inside the container

## Design Decisions

1. **Direct bind mounts with `relabel=private`** — Verified that rootless Podman correctly maps ownership for bind mounts when using the existing `--user sandbox` configuration. No entrypoint script or UID mapping workaround needed.
2. **Read-only mounts** — All host file injections use `ro,readonly` to prevent container processes from modifying host credentials.
3. **Auto-detect with opt-out** — Host files are automatically detected and mounted if present. `--no-ssh` and `--no-auth` flags allow explicit opt-out.
4. **Build-time warmup** — Plugin warmup runs during `Containerfile` build, not at runtime. Uses `|| true` to tolerate network-unavailable builds.
5. **Permission warnings, not errors** — Missing files produce warnings; overly permissive SSH keys produce warnings. The container always starts unless files are present but unreadable.

## Containerfile Changes

### 1. Add `openssh-client` dependency

The `ssh-keyscan` command requires the `openssh-client` package. Add it to the existing dependency installation step:

```dockerfile
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  git \
  golang-go \
  curl \
  ca-certificates \
  openssh-client \
  && rm -rf /var/lib/apt/lists/*
```

### 2. Pre-configure GitHub SSH host keys

After creating the sandbox user, add GitHub's SSH host keys to `known_hosts`:

```dockerfile
# Pre-configure GitHub SSH host keys so git+ssh works without interactive prompt
RUN mkdir -p /home/sandbox/.ssh && \
    ssh-keyscan github.com >> /home/sandbox/.ssh/known_hosts && \
    chown -R sandbox:sandbox /home/sandbox/.ssh
```

This runs as root before the `USER sandbox` directive. The `known_hosts` file is copied into the named volume on first run, so it persists across container sessions.

### 3. Create directory scaffolding for runtime mounts

Ensure directories exist for runtime bind mounts so Podman can mount into subdirectories of the named volume:

```dockerfile
# Create directory structure for runtime bind mounts (SSH keys, auth config)
# Must set ownership to sandbox:sandbox so the user can write to these directories
RUN mkdir -p /home/sandbox/.local/share/opencode && \
    chown -R sandbox:sandbox /home/sandbox/.local
```

Note: `/home/sandbox/.ssh` is already created in step 2 with correct ownership.

### 4. Opencode plugin warmup

After all setup (user creation, config copy, bootstrap), run opencode as the sandbox user to pre-install plugins:

```dockerfile
USER sandbox

# Pre-warm opencode plugins to avoid ~10s hang on first interactive run.
# Tolerate failure in case network is unavailable during build.
RUN opencode run --agent plan "say hi" || true
```

**Important:** This must run as `USER sandbox` so plugin files are installed with correct ownership in `/home/sandbox/`. The `|| true` ensures the build doesn't fail if the warmup can't reach the network.

The full Containerfile ordering is:

1. Install dependencies (including `openssh-client`)
2. Install opencode CLI with SHA256 verification
3. Create sandbox user
4. Create `.ssh` directory and add GitHub host keys
5. Create `.local/share/opencode` directory
6. COPY opencode-config repository
7. Run bootstrap script
8. Set ownership of `/home/sandbox/` contents
9. Switch to sandbox user
10. Run opencode warmup
11. Set working directory to `/workspace`
12. Set CMD to `opencode`

## Wrapper Script Changes

### New CLI Flags for `oc-sandbox run`

| Option | Default | Description |
|--------|---------|-------------|
| `--no-ssh` | — | Skip mounting SSH keys even if they exist on host |
| `--no-auth` | — | Skip mounting auth.json even if it exists on host |

### Auto-Detection Logic

The `cmd_run` function in `oc-sandbox` gains host file detection before launching the container:

1. **SSH keys** — Check if `$HOME/.ssh/id_rsa` exists:
   - Exists and `--no-ssh` not set → mount `id_rsa` and `id_rsa.pub` (if `.pub` exists) read-only
   - Exists and `--no-ssh` set → skip, print info: `"Skipping SSH key mount (--no-ssh)"`
   - Doesn't exist → print warning: `"Warning: SSH key not found at ~/.ssh/id_rsa. Git SSH operations may not work."`

2. **auth.json** — Check if `$HOME/.local/share/opencode/auth.json` exists:
   - Exists and `--no-auth` not set → mount read-only
   - Exists and `--no-auth` set → skip, print info: `"Skipping auth.json mount (--no-auth)"`
   - Doesn't exist → print warning: `"Warning: auth.json not found at ~/.local/share/opencode/auth.json. Authenticated providers may not work."`

### Permission Check

Before mounting `id_rsa`, check its permissions. If the file has any group or other read/write bits set (i.e., `(mode & 077) != 0`), warn:

```
Warning: SSH key at ~/.ssh/id_rsa has overly permissive permissions (0644).
SSH may refuse to use it. Consider: chmod 600 ~/.ssh/id_rsa
```

This is a warning, not an error — the mount still proceeds. SSH itself will reject the key at runtime, but the user gets a clear hint about why.

### Bind Mount Configuration

When files exist and are not opted out, add these mount flags to the `podman run` command:

```bash
# SSH key mounts (conditional)
--mount type=bind,src="${SSH_KEY}",dst=/home/sandbox/.ssh/id_rsa,ro,readonly,relabel=private
--mount type=bind,src="${SSH_PUB_KEY}",dst=/home/sandbox/.ssh/id_rsa.pub,ro,readonly,relabel=private  # if .pub exists

# Auth.json mount (conditional)
--mount type=bind,src="${AUTH_JSON}",dst=/home/sandbox/.local/share/opencode/auth.json,ro,readonly,relabel=private
```

The `relabel=private` flag matches the existing workspace mount convention and ensures proper SELinux labeling.

### Updated `podman run` Command

The full `podman run` command becomes:

```bash
podman run \
  --rm \
  --interactive \
  --tty \
  --read-only \
  --tmpfs /tmp:rw,nosuid,size=100m \
  --volume "opencode-sandbox-home-${TAG}:/home/sandbox" \
  --user sandbox \
  --cap-drop ALL \
  --cap-add CHOWN \
  --security-opt no-new-privileges:true \
  --mount type=bind,src="${WORKSPACE_PATH}",dst=/workspace,relabel=private \
  ${SSH_MOUNTS[@]} \
  ${AUTH_MOUNT[@]} \
  --env "OPENCODE_CONFIG_DIR=/home/sandbox/opencode-config/profiles/${PROFILE}" \
  "$IMAGE_NAME" \
  opencode
```

Where `${SSH_MOUNTS[@]}` and `${AUTH_MOUNT[@]}` are bash arrays populated by the auto-detection logic. Empty arrays produce no additional flags.

### Updated Usage

```bash
oc-sandbox run [OPTIONS] [PATH]

Options:
    -t, --tag <TAG>         Tag of the image to run (default: main)
    -p, --profile <NAME>    Opencode profile to activate (default: dev)
    --no-ssh                Skip mounting SSH keys from host
    --no-auth               Skip mounting auth.json from host
    -h, --help              Show this help message
```

## Error Handling

### New Error Cases for `oc-sandbox run`

| Condition | Handling |
|-----------|----------|
| `~/.ssh/id_rsa` doesn't exist | Warning: `"SSH key not found at ~/.ssh/id_rsa. Git SSH operations may not work."` Continue without mount. |
| `~/.ssh/id_rsa.pub` doesn't exist (but `id_rsa` does) | Mount only `id_rsa`. No error — public key is optional. |
| `~/.ssh/id_rsa` has overly permissive permissions | Warning: `"SSH key at ~/.ssh/id_rsa has overly permissive permissions (MODE). SSH may refuse to use it. Consider: chmod 600 ~/.ssh/id_rsa"` Continue with mount. |
| `~/.ssh/id_rsa` exists but is unreadable | Error: `"Cannot read SSH key at ~/.ssh/id_rsa. Check file permissions."` Exit 1. |
| `~/.local/share/opencode/auth.json` doesn't exist | Warning: `"auth.json not found at ~/.local/share/opencode/auth.json. Authenticated providers may not work."` Continue without mount. |
| `auth.json` exists but is unreadable | Error: `"Cannot read auth.json at ~/.local/share/opencode/auth.json. Check file permissions."` Exit 1. |
| `--no-ssh` set | Info: `"Skipping SSH key mount (--no-ssh)"`. No mount. |
| `--no-auth` set | Info: `"Skipping auth.json mount (--no-auth)"`. No mount. |

### Build-Time Error Cases

| Condition | Handling |
|-----------|----------|
| `openssh-client` unavailable | Build fails (apt-get install failure) |
| `ssh-keyscan` fails | Build fails (RUN step failure) |
| Opencode warmup fails | Build continues (`|| true` tolerance) |

## Testing Approach

### New Test Scenarios

1. **GitHub SSH known_hosts** — Verify `github.com` entries exist in `/home/sandbox/.ssh/known_hosts` inside the container
2. **SSH key mount** — Verify `id_rsa` is readable inside container at `/home/sandbox/.ssh/id_rsa`
3. **SSH key read-only** — Verify container cannot modify the mounted `id_rsa`
4. **SSH public key mount** — Verify `id_rsa.pub` is readable inside container when it exists on host
5. **Auth.json mount** — Verify `auth.json` is readable inside container at `/home/sandbox/.local/share/opencode/auth.json`
6. **Auth.json read-only** — Verify container cannot modify the mounted `auth.json`
7. **Missing SSH key warning** — Run without `id_rsa`, verify warning is printed to stderr
8. **Missing auth.json warning** — Run without `auth.json`, verify warning is printed to stderr
9. **`--no-ssh` flag** — Verify SSH keys are not mounted when flag is set, even if files exist
10. **`--no-auth` flag** — Verify `auth.json` is not mounted when flag is set, even if file exists
11. **Permissive SSH key warning** — Run with `id_rsa` having 644 permissions, verify warning about permissive permissions (group/other readable)
12. **Unreadable SSH key error** — Run with `id_rsa` having 000 permissions, verify error and exit
13. **Plugin warmup** — Verify opencode plugins are pre-installed in the built image (check for plugin files in `/home/sandbox/`)
14. **Git SSH clone** — Verify `git clone git@github.com:some/repo.git` works without host key prompt inside container

## Files Changed

| File | Changes |
|------|---------|
| `sandbox/Containerfile` | Add `openssh-client` dependency, ssh-keyscan step, directory scaffolding, opencode warmup step |
| `sandbox/oc-sandbox` | Add `--no-ssh`/`--no-auth` flags, auto-detection logic, bind mount flags, permission check |
| `sandbox/test-sandbox.sh` | Add test scenarios for SSH, auth, warmup, and known_hosts |

## Relationship to Existing Spec

This spec extends the sandbox design in `2026-05-01-opencode-sandbox-design.md`. All existing behavior is preserved. The changes are additive:

- Containerfile gains new `RUN` steps (no existing steps modified)
- `oc-sandbox run` gains new flags (existing flags unchanged)
- `oc-sandbox build` is unchanged
- Security model is unchanged (read-only rootfs, dropped capabilities, no-new-privileges)