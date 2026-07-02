FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    iproute2 \
    iputils-ping \
    jq \
    linux-tools-common \
    linux-tools-generic \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/lib/linux-tools/$(ls /usr/lib/linux-tools/ | head -1)/bpftool /usr/local/bin/bpftool
LABEL maintainer="clab-softnet-project"
LABEL description="Ubuntu 24.04 + bpftool + jq — entrypoint and helper scripts bind-mounted at runtime, not baked in"
CMD ["sleep", "infinity"]
