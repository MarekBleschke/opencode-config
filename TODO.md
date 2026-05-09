# TODO
- [ ] setup default profile in config
- [ ] rename opencode-config to oc-sandbox
- [ ] rename `dev` profile to `superpowers`
- [ ] add id-rsa key path in config
- [ ] adding new profiles shoudn't require changes in @sandbox/ scripts:
  - no hardcoded profile names
  - no hardcoded agents paths, ARGs, ENVS etc.
  - proposition: instead of multiple ARGs in Containerfile, use a single ARG with JSON, BASE64 or create temporary file to copy to image during build
