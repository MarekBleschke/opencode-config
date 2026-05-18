FROM localhost/oc-sandbox-base:latest
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    default-jdk-headless maven gradle \
  && rm -rf /var/lib/apt/lists/*
