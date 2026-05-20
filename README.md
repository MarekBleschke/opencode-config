# oc-sandbox

A containerized sandbox for running [opencode](https://opencode.ai) agents with filesystem isolation and protection against permission escalation. Built on rootless Podman with a read-only root filesystem, dropped capabilities, and `no-new-privileges` — agents can only write to `/workspace`, `/tmp`, and `/home/sandbox`.

## How to use it

1. **Install** oc-sandbox:

   ```bash
   # Remote install (no git required):
   curl -fsSL https://raw.githubusercontent.com/MarekBleschke/oc-sandbox/main/install.sh | bash

   # Or install from a cloned repo (normal mode):
   git clone git@github.com:MarekBleschke/oc-sandbox.git && cd oc-sandbox
   ./install.sh

   # Or install in dev mode (symlinks to source for live editing):
   ./install.sh --dev
   ```

2. **Build** the container image (required before first run or after config changes):

   ```bash
   oc-sandbox build
   ```

   Useful options:

   | Flag | Default | Description |
   |------|---------|-------------|
   | `-I, --image <NAME>` | `base` | Image name to build |
   | `-F, --force` | — | Force rebuild even if image exists |

3. **Run** opencode inside the sandbox:

   ```bash
   oc-sandbox run
   ```

   Useful options:

   | Flag | Default | Description |
   |------|---------|-------------|
   | `-p, --profile <name>` | `superpowers` | Opencode profile to activate |
   | `-t, --tag <tag>` | `main` | Image tag to run |
   | `--debug` | — | Drop into `/bin/bash` instead of opencode |
   | `--no-ssh` | — | Skip mounting SSH keys from host |
   | `--no-auth` | — | Skip mounting auth.json from host |

## Configuration

The config file at `~/.config/oc-sandbox/config` controls defaults:

```ini
[general]
default_profile = superpowers
default_image = base

[git]
user_name =
user_email =

[mounts]
ssh_key = ~/.ssh/id_rsa|/home/sandbox/.ssh/id_rsa
auth_json = ~/.local/share/opencode/auth.json|/home/sandbox/.local/share/opencode/auth.json
```

The `[mounts]` section uses `src_path|container_dst_path` pairs with `~/` expansion. If a mount key is missing or malformed, the CLI falls back to the default paths. Use `--no-ssh` or `--no-auth` to skip mounts regardless of config.

## Project structure

```
.
├── install.sh                  # Curl-able installation script
├── sandbox/
│   ├── oc-sandbox              # CLI script (build, run, uninstall, completion)
│   ├── oc-sandbox.conf          # Config template
│   ├── completion_zsh           # Zsh completion definitions
│   ├── init.sh                  # Container ENTRYPOINT — resolves profiles at runtime
│   ├── opencode-install.sha256  # SHA256 checksum for opencode install script
│   ├── containerfiles/
│   │   ├── base.Containerfile   # Ubuntu + system deps + opencode + init.sh
│   │   ├── python.Containerfile # FROM base + Python
│   │   └── java.Containerfile   # FROM base + Java
│   └── test-sandbox.sh          # Integration tests (require podman)
├── default-profiles/            # Self-contained profile repository
│   ├── base/                    # Profile directory (flat, no nesting)
│   │   ├── profile.conf         # Required — marks this as a profile
│   │   └── opencode.json
│   └── superpowers/             # Profile directory
│       ├── profile.conf         # Default variant
│       ├── profile.eco.conf     # Alternative variant (eco model)
│       ├── profile.free.conf    # Alternative variant (free model)
│       ├── opencode.json
│       ├── agents/              # Template .md files with {{MODEL_*}}
│       ├── skills/ → submodules/superpowers/skills/    # Internal symlink
│       ├── plugins/ → submodules/superpowers/plugins/  # Internal symlink
│       └── submodules/
│           └── superpowers/     # Git submodule (lives INSIDE profile dir)
└── docs/specs/                  # Design documents
```

## Adding a new profile

1. Create a directory under `default-profiles/<name>/` with at minimum an `opencode.json` config file.
2. Reference any submodules or shared resources via symlinks (see `default-profiles/superpowers/` for the pattern).
3. Rebuild the image: `oc-sandbox build -F`
4. Run with the new profile: `oc-sandbox run -p <name>`
