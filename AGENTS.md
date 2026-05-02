# Agent Guidelines

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
