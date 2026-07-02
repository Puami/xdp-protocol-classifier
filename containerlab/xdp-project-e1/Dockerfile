FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    iproute2 \
    iputils-ping \
    linux-tools-common \
    linux-tools-generic \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/lib/linux-tools/$(ls /usr/lib/linux-tools/ | head -1)/bpftool /usr/local/bin/bpftool
COPY --chmod=755 bin/entrypoint.sh /entrypoint.sh
LABEL maintainer="clab-softnet-project"
CMD ["sleep", "infinity"]
