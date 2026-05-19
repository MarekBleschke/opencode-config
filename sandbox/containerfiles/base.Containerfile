FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    git curl ca-certificates openssh-client zsh vim \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings && \
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
  apt-get update && \
  apt-get install -y --no-install-recommends gh && \
  rm -rf /var/lib/apt/lists/*

# Install opencode
ARG OPENCODE_INSTALL_SHA256
RUN curl -fsSL https://opencode.ai/install -o /tmp/install.sh && \
  echo "${OPENCODE_INSTALL_SHA256}  /tmp/install.sh" | sha256sum -c - && \
  bash /tmp/install.sh && \
  cp /root/.opencode/bin/opencode /usr/local/bin/opencode && \
  rm /tmp/install.sh

# Create sandbox user
RUN groupadd -g 1001 sandbox && \
  useradd -m -u 1001 -g 1001 -s /bin/bash sandbox && \
  mkdir -p /home/sandbox/.ssh && \
  ssh-keyscan github.com >> /home/sandbox/.ssh/known_hosts && \
  chown -R sandbox:sandbox /home/sandbox/.ssh && \
  mkdir -p /home/sandbox/.local/share/opencode && \
  chown -R sandbox:sandbox /home/sandbox/.local

# Init script
COPY --chmod=755 sandbox/containerfiles/init.sh /usr/local/bin/oc-sandbox-init.sh

USER sandbox
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/oc-sandbox-init.sh"]
CMD []
