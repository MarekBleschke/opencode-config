# oc-sandbox

A containerized sandbox for running [opencode](https://opencode.ai) agents with filesystem isolation and protection against permission escalation. Built on rootless Podman with a read-only root filesystem, dropped capabilities, and `no-new-privileges` — agents can only write to `/workspace`, `/tmp`, and `/home/sandbox`.

## How to use it

1. **Clone** the repository and install oc-sandbox:

   ```bash
   git clone git@github.com:MarekBleschke/oc-sandbox.git && cd oc-sandbox
   git submodule update --init --recursive
   ./sandbox/oc-sandbox install
   ```

2. **Build** the container image (required before first run or after config changes):

   ```bash
   oc-sandbox build
   ```

   Useful options:

   | Flag | Default | Description |
   |------|---------|-------------|
   | `-t, --tag <tag>` | —  | Image tag |

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

   Install as a global command:

   ```bash
   oc-sandbox install       # adds symlink to ~/.local/bin/ + shell completions
   oc-sandbox uninstall     # removes it
   ```

## Project structure

```
.
├── sandbox/                  # Container image and CLI
│   ├── oc-sandbox            # CLI script (build, run, install, completion)
│   ├── Containerfile         # Podman container image definition
│   ├── bootstrap.sh          # Initializes submodules during image build
│   └── opencode-install.sha256
├── profiles/                 # Opencode configuration profiles
│   └── superpowers/          # Default profile (agents, skills, plugins, commands)
├── docs/specs/               # Design documents
└── submodules/               # Git submodules (e.g. superpowers)
```

## Adding a new profile

1. Create a directory under `profiles/<name>/` with at minimum an `opencode.json` config file.
2. Reference any submodules or shared resources via symlinks (see `profiles/superpowers/` for the pattern).
3. Rebuild the image: `oc-sandbox build --force`
4. Run with the new profile: `oc-sandbox run --profile <name>`
