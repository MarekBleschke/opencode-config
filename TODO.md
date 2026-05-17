# TODO
1. Flag for specifying oc-sandbox configuration file. This will override the default config file
2. Make oc-sandbox a generic tool:
  - add support for multiple Containerfiles:
    - different setup of development environments, i.e. for java, python, shell scripts etc.
    - one base Containerfile with basic dependencies that other will inherit
    - keep in mind optimal layers caching, so openconde install will not invalidate basic system dependencies (apt-get)
  - separate profiles configs:
    - move `[profile.superpowers]` section as separate profile config - this will be profiles
    - profile config should have key with path to profile directory - this is source of truth where profile is
    - create default profile configs for `base` and `superpowers`
    - installation should copy default profile configs to config dir
    - autocomplete should load profiles dynamically (no caching) from list of profile config files
  - profiles are dynamically mounted when running container, not at build phase:
    - after building container it should have installed dependencies, but not profiles
    - profiles should be loaded when `run` command is invoked
    - models definition for agents should be resolved when running container, but without modifying source profile files
    - oc-sandbox config should have default profile (already has) and default image (new key)
    - this is significant change to how sandbox works: images are more static working environments and running container has more dynamic configuration
  - profiles and sandbox should be independent of each other, adding new profiles shouldn't require changes in @sandbox/ scripts:
      - no hardcoded profile names
      - no hardcoded agents paths, ARGs, ENVS etc.
      - proposition: instead of multiple ARGs in Containerfile, use a single ARG with JSON, BASE64 or create temporary file to copy to image during build. To discuss pros and cons.
