# TODO
1. setup default profile in config
  - remove hardcoded `dev` profile from oc-sanbox script
  - set `base` profile as default in ox-sanbox.conf
  - if profile is not set in config, running `oc-sandbox run` without `--profile` throws error and asks user to set default profile in config or use `--profile` flag.
2. Migrate to new name: rename every occurrence of opencode-config to oc-sandbox
3. rename `dev` profile to `superpowers`. Update all occurrences
4. add id-rsa and auth file paths in config. Prefil oc-sandbox.conf with current values, with `~` or `$HOME` - don't hardcode my home dir
5. Make oc-sandbox usable by other users:
  - adding new profiles shouldn't require changes in @sandbox/ scripts:
  - all code related to profiles should be generic and not tied to names. `profiles/<profile-name>/` - this is contract for profile
  - no hardcoded profile names
  - no hardcoded agents paths, ARGs, ENVS etc.
  - proposition: instead of multiple ARGs in Containerfile, use a single ARG with JSON, BASE64 or create temporary file to copy to image during build. To discuss pros and cons.
