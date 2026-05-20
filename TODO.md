1. curl | bash install doesn't init submodules and superpowers skills are not loaded
  - add recursive initialization of submodules in install script or resign from submodules and install superpowers normally
2. java and python containerfiles does not work
   ```
   STEP 1/2: FROM localhost/oc-sandbox:base
    STEP 2/2: RUN apt-get update &&   apt-get install -y --no-install-recommends     python3 python3-pip python3-venv   && rm -rf /var/lib/apt/lists/* Reading package lists... E: List directory /var/lib/apt/lists/partial is missing. - Acquire (13: Permission denied)
    Error: building at STEP "RUN apt-get update &&   apt-get install -y --no-install-recommends     python3 python3-pip python3-venv   && rm -rf /var/lib/apt/lists/*": while running runtime: exit status 100
   ```
3.  `~` from oc-sandbox:base is not expanded 
   - change `~` to `${HOME}` or fix `~` not expanding in `oc-sandbox run` command
4. install.sh --dev does not work with `oc-sandbox build` due to symlinks and context of build. Let's remove --dev. Rerunning install.sh works good enough.
