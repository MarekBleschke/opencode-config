# TODO

Remaining work after renames and mounts config:
- Make oc-sandbox usable by other users:
  - adding new profiles shouldn't require changes in @sandbox/ scripts:
  - all code related to profiles should be generic and not tied to names. `profiles/<profile-name>/` - this is contract for profile
  - no hardcoded profile names
  - no hardcoded agents paths, ARGs, ENVS etc.
  - proposition: instead of multiple ARGs in Containerfile, use a single ARG with JSON, BASE64 or create temporary file to copy to image during build. To discuss pros and cons.
